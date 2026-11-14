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
    // Sections, project groups and loose chats, as the board draws them (see ChatBoardCore/Tree.swift).
    @Published private(set) var tree: [Tree.TopEntry] = []
    // The project page being shown, or nil for the whole board.
    @Published private(set) var openGroupId: String?
    private(set) var layout = BoardLayout()
    private var layoutLoaded = false
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
        refreshLayout(list)
        settleArchives()
    }

    // MARK: Sections and project groups

    private var layoutPath: String { shareDir + "/layout.json" }

    // Files new and renamed chats, saves the layout when that changed it, and rebuilds what the board draws.
    // Skipped while no chats are listed (an unreadable config), so groups never dissolve over a passing error.
    private func refreshLayout(_ list: [Chat]) {
        if !layoutLoaded {
            layoutLoaded = true
            if let data = FileManager.default.contents(atPath: layoutPath),
               let saved = try? JSONDecoder().decode(BoardLayout.self, from: data) {
                layout = saved
            }
        }
        if !list.isEmpty {
            let updated = AutoFile.update(layout, chats: list, priorOrder: readOrder())
            if updated != layout { layout = updated; saveLayout() }
        }
        let built = Tree.build(layout, chats: list)
        if built != tree { tree = built }
        if let open = openGroupId, openCard == nil { _ = open; openGroupId = nil }
    }

    private func saveLayout() {
        try? FileManager.default.createDirectory(atPath: shareDir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(layout) {
            try? data.write(to: URL(fileURLWithPath: layoutPath), options: .atomic)
        }
    }

    private func apply(_ next: BoardLayout) {
        guard next != layout else { return }
        layout = next
        saveLayout()
        tree = Tree.build(layout, chats: chats)
    }

    // Every card on the board, wherever it sits.
    var cards: [Tree.Card] {
        tree.flatMap { top -> [Tree.Entry] in
            switch top {
            case .section(let block): block.entries
            case .entry(let entry): [entry]
            }
        }.compactMap { if case .group(let card) = $0 { card } else { nil } }
    }

    var openCard: Tree.Card? { openGroupId.flatMap { id in cards.first { $0.id == id } } }

    // The section an open card sits in, for the breadcrumb.
    var openSectionName: String? {
        guard let id = openGroupId, case .section(let section)? = layout.container(of: .group(id)) else { return nil }
        return layout.sections[section]?.name
    }

    // True when a chat outside the open project is asking the person something.
    var questionElsewhere: Bool {
        guard let card = openCard else { return false }
        let inside = Set(card.chats.map(\.id))
        return chats.contains { $0.kind == .question && !inside.contains($0.id) }
    }

    func openProject(_ id: String) {
        endSearch()
        openGroupId = id
    }

    func goHome() { openGroupId = nil }

    func toggleSection(_ id: String) { apply(Moves.toggleCollapsed(layout, section: id)) }

    func move(_ node: Node, to container: Container, before: Node?) {
        apply(Moves.move(layout, node, to: container, before: before))
    }

    // MARK: Dragging
    // The panel reports the mouse (see ClickThroughPanel), so a drag lives here rather than in a view: it survives
    // the project page switching back to the whole board while the button is still down.

    struct DragState: Equatable {
        var node: Node
        var point: CGPoint
        var label: String
        var target: DropTarget?
    }

    // Everything draggable on screen, in window space, reported by the views.
    var slots: [Node: DropSlot] = [:]
    @Published private(set) var drag: DragState?
    private var press: (node: Node, at: CGPoint)?
    private var homeHover: Date?

    private func label(_ node: Node) -> String {
        switch node {
        case .chat(let id): chats.first { $0.id == id }.map { TitleParse.parse($0.title).task } ?? ""
        case .group(let id): layout.groups[id]?.name ?? ""
        case .section(let id): layout.sections[id]?.name ?? ""
        }
    }

    func mousePressed(at point: CGPoint) {
        guard !isSearching, let node = Drop.pick(at: point, slots: Array(slots.values)) else { press = nil; return }
        press = (node, point)
    }

    func mouseDragged(to point: CGPoint) {
        guard let press else { return }
        if drag == nil {
            guard hypot(point.x - press.at.x, point.y - press.at.y) > 6 else { return }
            drag = DragState(node: press.node, point: point, label: label(press.node), target: nil)
        }
        drag?.point = point
        drag?.target = Drop.target(for: press.node, at: point, slots: Array(slots.values))
        // Held on the banner or breadcrumb for half a second, the board goes back to all chats and the drag goes on.
        let overHome = openGroupId != nil && hitsInWindow.contains { $0.key.hasPrefix("home") && $0.value.contains(point) }
        if !overHome { homeHover = nil; return }
        if homeHover == nil {
            let started = Date()
            homeHover = started
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.homeHover == started, self.drag != nil else { return }
                self.homeHover = nil
                self.goHome()
            }
        }
    }

    // True when the press was a drag, so the panel doesn't also treat it as a click.
    @discardableResult
    func mouseReleased(at point: CGPoint) -> Bool {
        defer { press = nil; drag = nil; homeHover = nil }
        guard let drag else { return false }
        if let target = Drop.target(for: drag.node, at: point, slots: Array(slots.values)) {
            apply(Drop.apply(layout, drag.node, target, name: { [chats] other in
                chats.first { $0.id == other }.flatMap { TitleParse.parse($0.title).project } ?? "New group"
            }))
        }
        return true
    }

    // The other loose chats beside this one, which it can be grouped with by hand.
    func groupPartners(_ id: String) -> [Chat] {
        guard let here = layout.container(of: .chat(id)) else { return [] }
        if case .group = here { return [] }
        let ids = layout.items(in: here).compactMap { if case .chat(let other) = $0, other != id { other } else { nil } }
        return ids.compactMap { other in chats.first { $0.id == other } }
    }

    // Groups two loose chats by hand, named after their project when the title has one.
    func makeGroup(_ id: String, with other: String) {
        let title = chats.first { $0.id == other }?.title ?? ""
        let name = TitleParse.parse(title).project ?? "New group"
        apply(Moves.makeGroup(layout, dropping: id, onto: other, name: name))
    }

    func ungroup(_ id: String) {
        if openGroupId == id { openGroupId = nil }
        apply(Moves.ungroup(layout, id))
    }

    // Set by the app: asks for a new name. Nil when the person cancels.
    var askName: (String) -> String? = { _ in nil }

    func renameGroup(_ id: String) {
        guard let current = layout.groups[id]?.name, let name = askName(current) else { return }
        apply(Moves.rename(layout, group: id, to: name))
    }

    // Where the Move to menu can send a chat: each group and section with its name, plus the top level.
    var moveTargets: (groups: [(id: String, name: String)], sections: [(id: String, name: String)]) {
        let sectionOrder = layout.top.compactMap { if case .section(let id) = $0 { id } else { nil } }
        let sections = sectionOrder.compactMap { id in layout.sections[id].map { (id: id, name: $0.name) } }
        let groups = cards.map { (id: $0.id, name: $0.name) }
        return (groups, sections)
    }

    // The chat rows on screen, top to bottom: search results, the open project's chats, or the loose chats of the
    // board (cards show their chats only once opened). Collapsed sections show none.
    var visibleChats: [Chat] {
        if isSearching { return shown }
        if let card = openCard { return Tree.page(card).flatMap(\.chats) }
        return tree.flatMap { top -> [Chat] in
            func rows(_ entry: Tree.Entry) -> [Chat] {
                if case .chat(let chat, let children) = entry { return [chat] + children }
                return []
            }
            switch top {
            case .section(let block): return block.collapsed ? [] : block.entries.flatMap(rows)
            case .entry(let entry): return rows(entry)
            }
        }
    }

    func container(of node: Node) -> Container? { layout.container(of: node) }

    func items(in container: Container) -> [Node] { layout.items(in: container) }

    func isUnread(_ card: Tree.Card) -> Bool { card.chats.contains { isUnread($0) } }

    // A section lights up when any chat in it is unread, with the dot in the most urgent unread chat's color.
    func unreadKind(_ block: Tree.SectionBlock) -> Kind? {
        let chats = block.entries.flatMap { entry -> [Chat] in
            switch entry {
            case .chat(let chat, let children): [chat] + children
            case .group(let card): card.chats
            }
        }
        let unread = Set(chats.filter { isUnread($0) }.map(\.kind))
        return [Kind.question, .yourMove, .ready, .working].first { unread.contains($0) }
    }

    func holdsCurrent(_ card: Tree.Card) -> Bool { card.chats.contains { $0.id == currentId } }

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
    var controlsInWindow: [String: CGRect] = [:]
    // Cards ("group:<id>"), section headers ("section:<id>") and the ways home ("home:<n>"), for the same reason.
    var hitsInWindow: [String: CGRect] = [:]

    // True when the click landed on a chat and opened it.
    @discardableResult
    func click(at point: CGPoint) -> Bool {
        if let id = rowsInWindow.first(where: { $0.value.contains(point) })?.key,
           let chat = chats.first(where: { $0.id == id }) {
            endSearch()
            open(chat)
            return true
        }
        guard !isSearching, let hit = hitsInWindow.first(where: { $0.value.contains(point) })?.key else { return false }
        if hit.hasPrefix("group:") { openProject(String(hit.dropFirst(6))) }
        else if hit.hasPrefix("section:") { toggleSection(String(hit.dropFirst(8))) }
        else if hit.hasPrefix("home") { goHome() }
        return false
    }

    // MARK: Search (Cmd+F, or the magnifier in the header)

    @Published private(set) var isSearching = false
    // A new query starts back at the first match. The search box also writes its text back unchanged when Return
    // is pressed, which used to reset the selection and open the first match instead of the one picked.
    @Published var query = "" { didSet { if query != oldValue { selected = 0 } } }
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
        guard let url = URL(string: "claude://claude.ai/epitaxy/\(chat.localId)") else { return }
        // CHAT_BOARD_OPEN_LOG=<file>: the end-to-end tests record the link instead of opening the real app.
        if let log = ProcessInfo.processInfo.environment["CHAT_BOARD_OPEN_LOG"] {
            let line = Data((url.absoluteString + "\n").utf8)
            if let handle = FileHandle(forWritingAtPath: log) {
                handle.seekToEndOfFile()
                handle.write(line)
                try? handle.close()
            } else {
                FileManager.default.createFile(atPath: log, contents: line)
            }
            return
        }
        NSWorkspace.shared.open(url)
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
