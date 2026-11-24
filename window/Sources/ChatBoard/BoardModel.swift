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

// Every chat record as it is on disk right now, with no cache: used where a stale answer would send a message to
// the wrong chat.
private func freshRecords() -> [[String: Any]] {
    var records: [[String: Any]] = []
    for case let relative as String in FileManager.default.enumerator(atPath: recordsDir) ?? NSEnumerator()
    where relative.hasSuffix(".json") && (relative as NSString).lastPathComponent.hasPrefix("local_") {
        if let record = json(recordsDir + "/" + relative), record["isArchived"] as? Bool != true { records.append(record) }
    }
    return records
}

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
    let notice = Notice(logPath: shareDir + "/board.log")

    private var recordCache: [String: (mtime: Double, record: [String: Any])] = [:]
    private var rowCache: [String: (mtime: Double, row: [String: Any])] = [:]
    private var pendingDetach: [String: String] = [:]   // localId -> title
    private var pendingRename: [String: (title: String, name: String, answeredAt: Double?)] = [:]   // by localId
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

    // Each chat's last real view, so Claude's jump to the next chat after an archive doesn't erase it.
    private var realViews: [String: Double] = [:]

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
            let archives = archiveTimes(records)
            list = records.compactMap { record in
                ChatBoardCore.chat(record: record, row: (record["cliSessionId"] as? String).flatMap { rows[$0] },
                                   privateFolders: privateFolders, archives: archives,
                                   remembered: (record["cliSessionId"] as? String).flatMap { realViews[$0] })
            }
            for chat in list { realViews[chat.id] = chat.viewedAt }
        }

        let saved = readOrder()
        let next = Board.arrange(list, order: saved)
        if let settled = Board.settledOrder(next, saved: saved) { writeOrder(settled) }
        if next != chats { chats = next }
        refreshLayout(list)
        settleDetaches()
        settleRenames()
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

    func priority(of node: Node) -> Priority { layout.priority(of: node) }
    func setPriority(_ node: Node, to level: Priority) { apply(Moves.setPriority(layout, node, to: level)) }

    func toggleSection(_ id: String) { apply(Moves.toggleCollapsed(layout, section: id)) }

    // A project card opened in place on the board (down arrow), as opposed to its own page (right arrow).
    func isExpanded(_ id: String) -> Bool { !layout.folded.contains(id) }
    func toggleExpanded(_ id: String) { apply(Moves.toggleExpanded(layout, group: id)) }

    // A parent chat and its side chats, folded or open under it (Family).
    func family(_ parent: Chat, children: [Chat]) -> Family.Block { Family.block(parent, children: children, layout: layout) }
    func families(_ list: [Chat]) -> [Family.Block] { Family.split(list, layout: layout) }
    func toggleFamily(_ parentId: String) {
        let count = Tree.children(of: chats)[chats.first { $0.id == parentId }?.localId ?? ""]?.count ?? 0
        apply(Moves.toggleFamily(layout, parent: parentId, childCount: count))
    }

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
        guard !isSearching, editingId == nil, let node = Drop.pick(at: point, slots: Array(slots.values)) else { press = nil; return }
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

    // Set by the app: asks for a new name under the given heading. Nil when the person cancels.
    var askName: (_ heading: String, _ current: String) -> String? = { _, _ in nil }

    func renameGroup(_ id: String) {
        guard let current = layout.groups[id]?.name, let name = askName("Rename group", current) else { return }
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
    // board (a card shows its chats unless folded). Collapsed sections show none.
    var visibleChats: [Chat] {
        if isSearching { return shown }
        if let card = openCard { return families(card.chats).flatMap(Family.rows) }
        let layout = layout
        return tree.flatMap { top -> [Chat] in
            func rows(_ entry: Tree.Entry) -> [Chat] {
                switch entry {
                case .chat(let chat, let children): return Family.rows(Family.block(chat, children: children, layout: layout))
                case .group(let card):
                    return layout.folded.contains(card.id) ? [] : Family.split(card.chats, layout: layout).flatMap(Family.rows)
                }
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
    // Cards ("group:<id>"), their right arrows ("open:<id>"), section headers ("section:<id>") and the ways home
    // ("home:<n>"), for the same reason.
    var hitsInWindow: [String: CGRect] = [:]

    // True when the click landed on a chat and opened it.
    @discardableResult
    func click(at point: CGPoint) -> Bool {
        // A click inside the title being edited stays in the field; a click anywhere else saves it first.
        if let id = editingId {
            if rowsInWindow[id]?.contains(point) == true { return false }
            commitRename()
        }
        // A question's button sits inside its chat's row, so it is checked first.
        if !isSearching, let hit = hitsInWindow.first(where: { $0.key.hasPrefix("answer:") && $0.value.contains(point) })?.key {
            let parts = hit.split(separator: ":", maxSplits: 2).map(String.init)
            if parts.count == 3, let index = Int(parts[1]), let chat = chats.first(where: { $0.id == parts[2] }),
               chat.buttons.indices.contains(index) {
                answer(chat, chat.buttons[index])
                return true
            }
        }
        if let id = rowsInWindow.first(where: { $0.value.contains(point) })?.key,
           let chat = chats.first(where: { $0.id == id }) {
            endSearch()
            open(chat)
            return true
        }
        // The smallest frame wins: a card's right arrow sits inside the card. The arrow opens the project's page; a click
        // anywhere else on the card folds or opens it in place (Mo, 2026-11-14).
        guard !isSearching, let hit = hitsInWindow.filter({ $0.value.contains(point) })
                .min(by: { $0.value.width * $0.value.height < $1.value.width * $1.value.height })?.key else { return false }
        if hit.hasPrefix("open:") { openProject(String(hit.dropFirst(5))) }
        else if hit.hasPrefix("group:") { toggleExpanded(String(hit.dropFirst(6))) }
        else if hit.hasPrefix("family:") { toggleFamily(String(hit.dropFirst(7))) }
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

    // Closes the search without handing the keyboard to Claude, for when you have already moved to another app.
    var onSearchDropped: () -> Void = {}
    func dropSearch() {
        guard isSearching else { return }
        isSearching = false
        query = ""
        onSearchDropped()
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

    // Presses a chat's own question button in Claude's window (see ClaudeAnswer.swift).
    private var answering: ClaudeAnswer?

    func answer(_ chat: Chat, _ button: AnswerButton) {
        if let reply = button.reply { return sendReply(chat, button, reply) }
        guard answering == nil else { notice.text = "Still answering the last one..."; return }
        notice.text = "Answering \(chat.title): \(button.label)..."
        // The press needs that chat open in Claude. Remember where Mo was so a good press puts him back there.
        let before = chats.first { $0.id == currentId && $0.id != chat.id }
        let front = NSWorkspace.shared.frontmostApplication
        let job = ClaudeAnswer(title: chat.title, button: button, openChat: { [weak self] in self?.open(chat) }) { [weak self] message in
            self?.notice.text = message
            self?.answering = nil
            // A failed press stays on that chat so the reason is in view.
            guard message.hasPrefix("Answered") else { return }
            self?.goBack(to: before, front: front)
        }
        answering = job
        job.start()
    }

    // Types an orange chat's go-ahead into it (see ClaudeReply.swift). Every check reads the files fresh, never the
    // board's last poll, because the board can be up to three seconds behind.
    private var replying: ClaudeReply?

    private func sendReply(_ chat: Chat, _ button: AnswerButton, _ reply: String) {
        guard replying == nil, answering == nil else { notice.text = "Still answering the last one..."; return }
        notice.text = "Sending \"\(reply)\" to \(chat.title)..."
        let before = chats.first { $0.id == currentId && $0.id != chat.id }
        let front = NSWorkspace.shared.frontmostApplication
        let rowPath = shareDir + "/rows/" + chat.id + ".json"
        let job = ClaudeReply(
            title: chat.title, reply: reply,
            openChat: { [weak self] in self?.open(chat) },
            isStillOffered: { stillOffered(button, row: json(rowPath)) },
            isOpen: { isFrontChat(chat.localId, records: freshRecords()) },
            wasSent: { at in
                guard let row = json(rowPath) else { return false }
                return number(row["userAt"]) >= at - 2000
            }
        ) { [weak self] message in
            self?.notice.text = message
            self?.replying = nil
            guard message.hasPrefix("Sent") else { return }
            self?.goBack(to: before, front: front)
        }
        replying = job
        job.start()
    }

    private func goBack(to chat: Chat?, front: NSRunningApplication?) {
        if let chat { open(chat) }
        guard let front, front.bundleIdentifier != AppDelegate.claude,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        // Opening a chat link brings Claude forward, so hand the front back once that has happened.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { front.activate() }
    }

    // Archives through Claude's own window (see ClaudeArchive.swift). A plugin can't archive from a chat in auto mode.
    private var archiving: ClaudeArchive?

    func archive(_ chat: Chat) {
        guard archiving == nil else { notice.text = "Still archiving the last one..."; return }
        notice.text = "Archiving \(chat.title)..."
        let job = ClaudeArchive(title: chat.title, openChat: { [weak self] in self?.open(chat) }) { [weak self] message in
            self?.notice.text = message
            self?.archiving = nil
            // The click is only a claim until the chat leaves the list. The list refreshes every few seconds and
            // Claude can take a moment to save, so this keeps looking for 15 seconds and only speaks up if it never goes.
            guard message.hasPrefix("Archived") else { return }
            self?.confirmGone(chat, checks: 15)
        }
        archiving = job
        job.start()
    }

    private func confirmGone(_ chat: Chat, checks: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.chats.contains(where: { $0.id == chat.id }) else { return }
            if checks > 1 { return self.confirmGone(chat, checks: checks - 1) }
            self.notice.text = "Claude didn't archive \(chat.title). Try it from Claude's sidebar."
        }
    }

    func detach(_ chat: Chat) {
        guard let parent = chat.parentLocalId else { return }
        let dir = shareDir + "/requests"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // Session ids too: a chat's mod always knows its own, but only learns the app's id once it finds its record.
        let request = DetachRequest(localId: chat.localId, parentLocalId: parent, title: chat.title,
                                    sessionId: chat.id, parentSessionId: chats.first(where: { $0.localId == parent })?.id)
        if let data = request.data() {
            FileManager.default.createFile(atPath: "\(dir)/\(request.fileName)", contents: data)
        }
        pendingDetach[chat.localId] = chat.title
        notice.text = "Moving \(chat.title) to top level..."
    }

    // Only the side chat itself or the chat that started it can do this, so one of them has to be open.
    private func settleDetaches() {
        for (localId, title) in pendingDetach {
            let clear = { for name in DetachRequest.fileNames(localId) { try? FileManager.default.removeItem(atPath: "\(shareDir)/requests/\(name)") } }
            if let result = json("\(shareDir)/requests/\(DetachRequest.resultFileName(localId))") {
                notice.text = result["text"] as? String ?? "Moved \(title) to top level."
                pendingDetach[localId] = nil
                clear()
            } else if let request = json("\(shareDir)/requests/detach-\(localId).json"),
                      Date().timeIntervalSince1970 * 1000 - number(request["at"]) > 20000 {
                notice.text = "Couldn't move \(title): open it, or the chat that started it, and try again."
                pendingDetach[localId] = nil
                clear()
            }
        }
    }

    // MARK: Rename a chat in place

    // The chat whose title is being edited on the board, and the text in its field.
    @Published private(set) var editingId: String?
    @Published var editText = ""
    // Set by the app: gives the board the keyboard while a title is edited, and hands it back to Claude after.
    var onEditChange: (Bool) -> Void = { _ in }

    // Right-click > Rename chat turns the row's title into a text field holding the FULL title (a card's row shows
    // only the task, and saving that would drop the [tag] project part). Return saves, Esc or an unchanged name cancels.
    func startRename(_ chat: Chat) {
        guard pendingRename[chat.localId] == nil else { notice.text = "Still renaming \(chat.title)..."; return }
        endSearch()
        editText = chat.title
        editingId = chat.id
        onEditChange(true)
    }

    func commitRename() {
        guard let id = editingId else { return }
        let typed = editText
        finishEditing(handBack: true)
        if let chat = chats.first(where: { $0.id == id }) { submitRename(chat, typed: typed) }
    }

    func cancelRename() {
        guard editingId != nil else { return }
        finishEditing(handBack: true)
    }

    // The board lost the keyboard (you clicked into Claude or another app): what you typed is kept, like Finder,
    // but the keyboard stays where you clicked.
    func dropRename() {
        guard let id = editingId else { return }
        let typed = editText
        finishEditing(handBack: false)
        if let chat = chats.first(where: { $0.id == id }) { submitRename(chat, typed: typed) }
    }

    private func finishEditing(handBack: Bool) {
        editingId = nil
        editText = ""
        if handBack { onEditChange(false) }
    }

    // The name the board shows for a chat while Claude hasn't caught up with a rename yet.
    func pendingName(_ chat: Chat) -> String? {
        guard let pending = pendingRename[chat.localId], chat.title != pending.name else { return nil }
        return pending.name
    }

    // Any open chat's mod carries out the rename through Claude's own rename tool.
    func submitRename(_ chat: Chat, typed: String) {
        guard pendingRename[chat.localId] == nil else { notice.text = "Still renaming \(chat.title)..."; return }
        guard let name = RenameRequest.cleanName(typed, current: chat.title) else {
            if typed.trimmingCharacters(in: .whitespacesAndNewlines).count > 200 {
                notice.text = "That name is too long: Claude allows 200 characters."
            }
            return
        }
        // A name typed in Claude's own sidebar can only be replaced there.
        if chat.nameIsPersons { return renameInClaude(chat, to: name) }
        let dir = shareDir + "/requests"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for leftover in RenameRequest.fileNames(chat.localId) { try? FileManager.default.removeItem(atPath: "\(dir)/\(leftover)") }
        let request = RenameRequest(localId: chat.localId, title: chat.title, name: name)
        guard let data = request.data(), FileManager.default.createFile(atPath: "\(dir)/\(request.fileName)", contents: data) else {
            notice.text = "Couldn't rename \(chat.title): the request file couldn't be written."
            return
        }
        pendingRename[chat.localId] = (chat.title, name, nil)
        objectWillChange.send()
        notice.text = "Renaming to \(name)..."
    }

    // Claude's own Rename, through its window (see ClaudeRename.swift). The sidebar may flash open for a moment.
    private var renamingInClaude: ClaudeRename?

    private func renameInClaude(_ chat: Chat, to name: String) {
        guard renamingInClaude == nil else { notice.text = "Still renaming the last one..."; return }
        pendingRename[chat.localId] = (chat.title, name, nil)
        objectWillChange.send()
        notice.text = "Renaming to \(name) in Claude..."
        let job = ClaudeRename(title: chat.title, name: name, openChat: { [weak self] in self?.open(chat) }) { [weak self] message in
            guard let self else { return }
            self.renamingInClaude = nil
            self.notice.text = message
            // Pressing Return is only a claim: settleRenames waits for Claude's list to show the new name.
            let now = Date().timeIntervalSince1970 * 1000
            self.pendingRename[chat.localId] = message.hasPrefix("Couldn't") ? nil : (chat.title, name, now)
            self.objectWillChange.send()
        }
        renamingInClaude = job
        job.start()
    }

    // The chat's answer is only a claim until Claude's own list shows the new title, so the board waits for that too.
    private func settleRenames() {
        let now = Date().timeIntervalSince1970 * 1000
        for (localId, pending) in pendingRename {
            let clear = { for name in RenameRequest.fileNames(localId) { try? FileManager.default.removeItem(atPath: "\(shareDir)/requests/\(name)") } }
            let shown = chats.first(where: { $0.localId == localId })?.title
            if let answeredAt = pending.answeredAt {
                if shown == pending.name {
                    pendingRename[localId] = nil
                    objectWillChange.send()
                } else if now - answeredAt > 15000 {
                    notice.text = "Claude still shows the old name for \(pending.title)."
                    pendingRename[localId] = nil
                    objectWillChange.send()
                }
            } else if let result = json("\(shareDir)/requests/\(RenameRequest.resultFileName(localId))") {
                let text = result["text"] as? String ?? "Renamed \(pending.title)."
                clear()
                // The list said Claude named it, but the person had renamed it in Claude since: use Claude's menu.
                if text.contains("set by the user"), let chat = chats.first(where: { $0.localId == localId }) {
                    pendingRename[localId] = nil
                    renameInClaude(chat, to: pending.name)
                    continue
                }
                notice.text = text
                pendingRename[localId] = text.hasPrefix("Couldn't") ? nil : (pending.title, pending.name, now)
                objectWillChange.send()
            } else if let request = json("\(shareDir)/requests/rename-\(localId).json"),
                      now - number(request["at"]) > 20000 {
                notice.text = "Couldn't rename \(pending.title): no open chat picked it up. Run /reload-plugins in any chat and try again."
                pendingRename[localId] = nil
                objectWillChange.send()
                clear()
            }
        }
    }
}
