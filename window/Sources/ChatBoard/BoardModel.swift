// Chat Board: one floating window listing every Claude Code chat with its status.
// It reads the Claude app's own chat records and the files the chat-hud mod writes in each chat,
// so it costs no tokens. Clicking opens a chat, dragging reorders, and Archive leaves a request
// that an open chat's mod hands to the app.

import AppKit
import ChatBoardCore
import SwiftUI

let home = FileManager.default.homeDirectoryForCurrentUser.path
// CHAT_BOARD_DEMO=<folder> reads made-up chats from <folder>/records and <folder>/share instead of the real ones,
// so screenshots can be taken without anyone's real chats in them. See demo/make-demo.py.
private let demoRoot = ProcessInfo.processInfo.environment["CHAT_BOARD_DEMO"]
private let recordsDir = demoRoot.map { $0 + "/records" } ?? home + "/Library/Application Support/Claude/claude-code-sessions"
let shareDir = demoRoot.map { $0 + "/share" } ?? home + "/.claude/chat-hud"

private func json(_ path: String) -> [String: Any]? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

private func number(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? 0 }

private func mtime(_ path: String) -> Double {
    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    return (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
}

extension Kind {
    var color: Color {
        switch self {
        case .question: .purple
        case .yourMove: .orange
        case .ready: .green
        case .working: Color(nsColor: .tertiaryLabelColor)
        }
    }
}

@MainActor
final class BoardModel: ObservableObject {
    @Published var chats: [Chat] = []
    let notice = Notice()

    private var recordCache: [String: (mtime: Double, record: [String: Any])] = [:]
    private var rowCache: [String: (mtime: Double, row: [String: Any])] = [:]
    private var pendingArchive: [String: String] = [:]  // localId -> title
    private var timer: Timer?
    private var configWasUnreadable = false

    init() {
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    // The list can't tell us a drag started, so a held mouse button over the board stands in for one.
    // Redrawing the list mid-drag cancels the drag.
    var isPointerHeld: () -> Bool = { false }

    func reload() {
        if isPointerHeld() { return }
        let manager = FileManager.default
        var records: [[String: Any]] = []
        if let walker = manager.enumerator(atPath: recordsDir) {
            for case let relative as String in walker where relative.hasSuffix(".json") && (relative as NSString).lastPathComponent.hasPrefix("local_") {
                let path = recordsDir + "/" + relative
                let modified = mtime(path)
                if let cached = recordCache[path], cached.mtime == modified {
                    records.append(cached.record)
                } else if let record = json(path) {
                    recordCache[path] = (modified, record)
                    records.append(record)
                }
            }
        }

        var rows: [String: [String: Any]] = [:]
        let rowsDir = shareDir + "/rows"
        for name in (try? manager.contentsOfDirectory(atPath: rowsDir)) ?? [] where name.hasSuffix(".json") {
            let path = rowsDir + "/" + name
            let modified = mtime(path)
            let id = String(name.dropLast(5))
            if let cached = rowCache[id], cached.mtime == modified {
                rows[id] = cached.row
            } else if let row = json(path) {
                rowCache[id] = (modified, row)
                rows[id] = row
            }
        }

        // Read every time, so an edit to the config takes effect without restarting the board.
        var list: [Chat] = []
        switch Config.privateFolders(atPath: shareDir + "/config.json", home: home) {
        case .unreadable:
            if !configWasUnreadable { notice.text = "config.json can't be read, so no chats are shown. Check its JSON." }
            configWasUnreadable = true
        case .list(let privateFolders):
            configWasUnreadable = false
            list = records.compactMap { record in
                ChatBoardCore.chat(record: record, row: (record["cliSessionId"] as? String).flatMap { rows[$0] },
                                   privateFolders: privateFolders)
            }
        }

        let saved = readOrder()
        let next = Board.arrange(list, order: saved)
        if let settled = Board.settledOrder(next, saved: saved) { writeOrder(settled) }
        if next != chats { chats = next }
        settleArchives()
    }

    private func readOrder() -> [String] {
        guard let data = FileManager.default.contents(atPath: shareDir + "/order.json"),
              let order = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        return order
    }

    // The chat just clicked shows as current at once; the app's own record takes over once it catches up.
    @Published private var clicked: (id: String, at: Date)?

    var currentId: String? { Board.currentId(chats, clicked: clicked) }

    func moveGroup(_ id: String, before target: String?) {
        guard let moved = Board.moveGroup(chats, id, before: target) else { return }
        chats = moved
        let showing = Set(chats.map(\.id))
        writeOrder(chats.map(\.id) + readOrder().filter { !showing.contains($0) })
    }

    private func writeOrder(_ order: [String]) {
        try? FileManager.default.createDirectory(atPath: shareDir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: order) {
            FileManager.default.createFile(atPath: shareDir + "/order.json", contents: data)
        }
    }

    // Where each chat's row sits in the window, so a click caught by the panel can find its chat.
    var rowsInWindow: [String: CGRect] = [:]

    // True when the click landed on a chat and opened it.
    @discardableResult
    func click(at point: CGPoint) -> Bool {
        guard let id = rowsInWindow.first(where: { $0.value.contains(point) })?.key,
              let chat = shown.first(where: { $0.id == id }) else { return false }
        endSearch()
        open(chat)
        return true
    }

    // MARK: Search (Cmd+F, or the magnifier in the header)

    @Published private(set) var isSearching = false
    @Published var query = "" { didSet { selected = 0 } }
    @Published var selected = 0
    // Set by the app: gives the board the keyboard while searching, and hands it back to Claude after.
    var onSearchChange: (Bool) -> Void = { _ in }

    // What the list draws: the whole board, or just the chats that match while searching.
    var shown: [Chat] { isSearching ? Search.filter(chats, query: query) : chats }

    func startSearch() {
        guard !isSearching else { return }
        query = ""
        isSearching = true
        onSearchChange(true)
    }

    func endSearch() {
        guard isSearching else { return }
        isSearching = false
        query = ""
        onSearchChange(false)
    }

    func moveSelection(by step: Int) {
        let count = shown.count
        guard count > 0 else { return }
        selected = min(max(selected + step, 0), count - 1)
    }

    func openSelected() {
        let list = shown
        guard list.indices.contains(selected) else { return }
        let chat = list[selected]
        endSearch()
        open(chat)
    }

    func isUnread(_ chat: Chat) -> Bool {
        Board.isUnread(chat, currentId: currentId, seenAt: seen[chat.id].map { $0.timeIntervalSince1970 * 1000 })
    }

    // Chats clicked here count as looked at right away, before the app's record catches up.
    @Published private var seen: [String: Date] = [:]

    func open(_ chat: Chat) {
        seen[chat.id] = Date()
        clicked = (chat.id, Date())
        if let url = URL(string: "claude://claude.ai/epitaxy/\(chat.localId)") { NSWorkspace.shared.open(url) }
    }

    func archive(_ chat: Chat) {
        let dir = shareDir + "/requests"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let request = ArchiveRequest(localId: chat.localId, title: chat.title)
        if let data = request.data() {
            FileManager.default.createFile(atPath: "\(dir)/\(request.fileName)", contents: data)
        }
        pendingArchive[chat.localId] = chat.title
        notice.text = "Archiving \(chat.title)..."
    }

    private func clearRequest(_ localId: String) {
        for name in ArchiveRequest.fileNames(localId) {
            try? FileManager.default.removeItem(atPath: "\(shareDir)/requests/\(name)")
        }
    }

    // Reads back what the chat that took the request said, or notices nobody has picked it up.
    private func settleArchives() {
        for (localId, title) in pendingArchive {
            if let result = json("\(shareDir)/requests/\(ArchiveRequest.resultFileName(localId))") {
                notice.text = result["text"] as? String ?? "Archived \(title)."
                pendingArchive[localId] = nil
                clearRequest(localId)
            } else if let request = json("\(shareDir)/requests/archive-\(localId).json"),
                      Date().timeIntervalSince1970 * 1000 - number(request["at"]) > 20000 {
                notice.text = "No open chat picked up the archive for \(title). Open any chat and try again."
                pendingArchive[localId] = nil
                clearRequest(localId)
            }
        }
    }
}
