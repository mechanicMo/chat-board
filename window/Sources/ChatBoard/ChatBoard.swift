import AppKit
import ChatBoardCore
import SwiftUI

// MARK: Views

private func age(_ ms: Double) -> String {
    guard ms > 0 else { return "" }
    let minutes = Int(max(0, Date().timeIntervalSince1970 * 1000 - ms) / 60000)
    if minutes < 1 { return "now" }
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    return hours < 48 ? "\(hours)h" : "\(hours / 24)d"
}

struct ChatRow: View {
    let chat: Chat
    let isCurrent: Bool
    let isUnread: Bool
    var isSelected = false
    // Shown instead of the full title, e.g. just the task inside a project.
    var displayTitle: String? = nil
    // The chat's priority: 1 is the normal size, 0.85 low, 1.3 high. Every font and gap scales with it.
    var scale: Double = 1
    // Set while the title is being edited in place: the field, and what Return and Esc do.
    var editText: Binding<String>? = nil
    var onCommit: () -> Void = {}
    var onCancel: () -> Void = {}
    // The question's one or two buttons, or an orange chat's go-ahead, drawn side by side under the line. Empty for low priority chats.
    var buttons: [AnswerButton] = []
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 7 * scale) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isCurrent ? Color.white.opacity(0.9) : chat.kind.color.opacity(isUnread ? 1 : 0.4))
                .frame(width: 3 * max(scale, 0.67))
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    if let editText {
                        TitleField(text: editText, size: 16 * scale, onCommit: onCommit, onCancel: onCancel)
                    } else {
                        if chat.routineId != nil {
                            // A run of a scheduled routine, which Claude keeps out of its own chat list.
                            Text("ROUTINE")
                                .font(.system(size: 10 * scale, weight: .bold))
                                .foregroundStyle(isCurrent ? chat.kind.color : Color.white)
                                .padding(.horizontal, 5 * scale)
                                .padding(.vertical, 1.5 * scale)
                                .background(Capsule().fill(isCurrent ? Color.white : Color.purple.opacity(0.8)))
                                .fixedSize()
                                .help("Started by the \(chat.routineId ?? "") routine")
                        }
                        // Up to two lines, so a narrow window still shows enough of the title to recognize it.
                        Text(displayTitle ?? chat.title)
                            .font(.system(size: 16 * scale, weight: isUnread || isCurrent ? .bold : .regular))
                            .foregroundStyle(isCurrent ? Color.white : Color.primary.opacity(isUnread ? 1 : 0.62))
                            .lineLimit(scale < 1 ? 1 : 2)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 4)
                    if isUnread {
                        Circle().fill(chat.kind.color).frame(width: 8 * scale, height: 8 * scale)
                    }
                    Text(age(chat.activeAt))
                        .font(.system(size: 13 * scale).monospacedDigit())
                        .foregroundStyle(isCurrent ? Color.white.opacity(0.85) : .secondary)
                }
                if !chat.line.isEmpty {
                    Text(chat.line)
                        .font(.system(size: 14 * scale))
                        .foregroundStyle(isCurrent ? Color.white.opacity(0.85) : Color.primary.opacity(isUnread ? 0.75 : 0.42))
                        .lineLimit(scale < 1 ? 1 : 2)
                        .truncationMode(.tail)
                }
                if !buttons.isEmpty {
                    HStack(spacing: 6 * scale) {
                        ForEach(Array(buttons.enumerated()), id: \.offset) { index, button in
                            AnswerButtonView(button: button, color: chat.kind.color, scale: scale, isCurrent: isCurrent)
                                .background(reportHit("answer:\(index):\(chat.id)"))
                        }
                    }
                    .padding(.top, 4 * scale)
                }
            }
        }
        .foregroundStyle(isCurrent ? Color.white : Color.primary)
        .padding(.vertical, 6 * scale)
        .padding(.horizontal, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrent ? chat.kind.color : (isHovered || isSelected ? Color.primary.opacity(0.08) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help(chat.line)
    }
}

// One of a question's buttons on the board. It takes no clicks itself: its frame goes to BoardModel.click(at:),
// which presses the same button in Claude's window.
struct AnswerButtonView: View {
    let button: AnswerButton
    let color: Color
    let scale: Double
    let isCurrent: Bool
    @State private var isHovered = false

    var body: some View {
        Text(button.label)
            .font(.system(size: 13 * scale, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(isCurrent ? color : Color.white)
            .padding(.vertical, 4 * scale)
            .padding(.horizontal, 10 * scale)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrent ? Color.white : color.opacity(isHovered ? 1 : 0.85))
            )
            .onHover { isHovered = $0 }
            .help(button.reply.map { "Sends \"\($0)\" to the chat" }
                ?? (button.action == nil ? "Answers \"\(button.label)\" in the chat" : "Presses \(button.label) in the chat"))
    }
}

// Right-click > Priority: High draws the item 30% bigger, Low at 85%, one line for the title and one for the summary. The current one is ticked.
struct PriorityMenu: View {
    @ObservedObject var board: BoardModel
    let node: Node

    var body: some View {
        Menu("Priority") {
            ForEach(Priority.allCases, id: \.self) { level in
                Button {
                    board.setPriority(node, to: level)
                } label: {
                    if board.priority(of: node) == level { Label(level.label, systemImage: "checkmark") } else { Text(level.label) }
                }
            }
        }
    }
}

// Lays its items left to right and wraps to a new line when the row is full, so the color key fits any width.
struct Flow: Layout {
    var spacing: CGFloat = 10
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += line + lineSpacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += line + lineSpacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

struct RowFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// Where the search button and search box sit in the window, for the end-to-end tests to click.
struct ControlFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private func reportFrame(_ name: String) -> some View {
    GeometryReader { geometry in
        Color.clear.preference(key: ControlFrames.self, value: [name: geometry.frame(in: .global)])
    }
}

struct WindowFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// Watches the notice on its own, so the X and the 5-second auto-clear redraw just this bar.
// It floats over the bottom of the board, so showing or clearing it never moves the list.
struct NoticeBar: View {
    @ObservedObject var notice: Notice

    var body: some View {
        if let text = notice.text {
            HStack(alignment: .top, spacing: 6) {
                Text(text)
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    notice.text = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
            .padding(10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// The search box. Typing filters the list, up and down pick a chat, Return opens it, Escape closes the search.
// A chat's title, edited in place on its row. Return saves, Esc cancels.
struct TitleField: View {
    @Binding var text: String
    let size: Double
    let onCommit: () -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Chat name", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: size))
            .lineLimit(1...3)
            .focused($focused)
            .onSubmit(onCommit)
            .onKeyPress(.return) { onCommit(); return .handled }
            .onKeyPress(.escape) { onCancel(); return .handled }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 1.5))
            .onAppear { focused = true }
            // The panel only takes the keyboard a moment after the field appears, so ask again once it has.
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in focused = true }
    }
}

struct SearchField: View {
    @ObservedObject var board: BoardModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search chats", text: $board.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focused)
                .onSubmit { board.openSelected() }
                .onKeyPress(.downArrow) { board.moveSelection(by: 1); return .handled }
                .onKeyPress(.upArrow) { board.moveSelection(by: -1); return .handled }
                .onKeyPress(.escape) { board.endSearch(); return .handled }
            Button {
                board.endSearch()
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close search (Esc)")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 7)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.07)))
        .background(reportFrame("searchField"))
        .onAppear { focused = true }
        // The panel only takes the keyboard a moment after the field appears, so ask again once it has.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in focused = true }
    }
}

struct BoardView: View {
    @ObservedObject var board: BoardModel
    // Reports a draggable thing's frame and container, and fades it while it's being dragged. The drag itself is
    // run by BoardModel from the panel's mouse events.
    private func draggable<V: View>(_ view: V, _ node: Node, in container: Container) -> some View {
        view
            .background(GeometryReader { geometry in
                Color.clear.preference(key: DragSlots.self,
                                       value: [node: DropSlot(node: node, container: container, frame: geometry.frame(in: .global))])
            })
            .opacity(board.drag?.node == node ? 0.35 : 1)
    }

    // `card` is the project card the row sits in: a low priority card hides its chats' buttons too.
    private func row(_ chat: Chat, title: String? = nil, card: String? = nil, indent: Bool = true) -> some View {
        let isLow = board.priority(of: .chat(chat.id)) == .low || card.map { board.priority(of: .group($0)) == .low } == true
        return ChatRow(chat: chat, isCurrent: chat.id == board.currentId, isUnread: board.isUnread(chat),
                displayTitle: board.pendingName(chat) ?? title,
                scale: board.priority(of: .chat(chat.id)).scale,
                editText: board.editingId == chat.id ? $board.editText : nil,
                onCommit: { board.commitRename() }, onCancel: { board.cancelRename() },
                buttons: isLow || board.editingId == chat.id ? [] : chat.buttons)
            .padding(.leading, indent && chat.depth > 0 ? 18 : 0)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: WindowFrames.self, value: [chat.id: geometry.frame(in: .global)])
            })
            .id(chat.id)
            .contextMenu {
                Button("Open") { board.open(chat) }
                if chat.depth == 0 { MoveToMenu(board: board, node: .chat(chat.id)) }
                PriorityMenu(board: board, node: .chat(chat.id))
                Button("Rename chat") { board.startRename(chat) }
                if chat.depth > 0 { Button("Detach to top level") { board.detach(chat) } }
                Divider()
                Button("Archive") { board.archive(chat) }
            }
    }

    @ViewBuilder
    private func entryView(_ entry: Tree.Entry, in container: Container) -> some View {
        switch entry {
        case .chat(let chat, let children):
            let inSection = container != .top
            if children.isEmpty {
                draggable(row(chat, title: inSection ? untaggedTitle(chat) : nil), .chat(chat.id), in: container)
            } else {
                draggable(familyCard(board.family(chat, children: children), short: inSection), .chat(chat.id), in: container)
                    .padding(.vertical, 2)
            }
        case .group(let card):
            let expanded = board.isExpanded(card.id)
            draggable(
                GroupCardView(card: card, isUnread: board.isUnread(card), holdsCurrent: board.holdsCurrent(card),
                              scale: board.priority(of: .group(card.id)).scale, expanded: expanded) {
                    cardRows(card)
                }
                    .background(reportHit("group:" + card.id))
                    .contextMenu {
                        Button("Open project") { board.openProject(card.id) }
                        Button(expanded ? "Fold here" : "Expand here") { board.toggleExpanded(card.id) }
                        Button("Rename group...") { board.renameGroup(card.id) }
                        Button("Ungroup") { board.ungroup(card.id) }
                        MoveToMenu(board: board, node: .group(card.id))
                        PriorityMenu(board: board, node: .group(card.id))
                    }
                    .padding(.vertical, 2),
                .group(card.id), in: container)
        }
    }

    private static func node(_ entry: Tree.Entry) -> Node {
        switch entry {
        case .chat(let chat, _): .chat(chat.id)
        case .group(let card): .group(card.id)
        }
    }

    private static func node(_ top: Tree.TopEntry) -> Node {
        switch top {
        case .section(let block): .section(block.id)
        case .entry(let entry): node(entry)
        }
    }

    // The whole board: sections with their cards and loose chats, and loose chats outside every section.
    @ViewBuilder
    private var home: some View {
        ForEach(board.tree, id: \.key) { top in
            switch top {
            case .section(let block):
                // A faint panel marks where a section ends, so a loose chat after it never reads as part of it.
                VStack(spacing: 2) {
                    SectionHeader(block: block, unreadKind: board.unreadKind(block)).background(reportHit("section:" + block.id))
                    if !block.collapsed {
                        ForEach(block.entries, id: \.key) { entry in
                            entryView(entry, in: .section(block.id))
                        }
                    }
                }
                .padding(.horizontal, 3)
                .padding(.bottom, block.collapsed ? 6 : 4)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035)))
                .padding(.vertical, 3)
                .modifier(Dragged(view: self, node: .section(block.id)))
            case .entry(let entry):
                entryView(entry, in: .top)
            }
        }
    }

    // A section moves as a whole at the top level.
    private struct Dragged: ViewModifier {
        let view: BoardView
        let node: Node
        func body(content: Content) -> some View { view.draggable(content, node, in: .top) }
    }

    // One project: its chats in the order the person put them, never sorted by status (Mo, 2026-11-14).
    @ViewBuilder
    private func page(_ card: Tree.Card) -> some View {
        cardRows(card)
    }

    // A parent chat and its side chats, drawn as a project card: the parent's title in the header, a click on the card
    // folds it, the right arrow opens the parent chat. Inside, the parent's row and then its side chats.
    @ViewBuilder
    private func familyCard(_ family: Family.Block, short: Bool, card: String? = nil) -> some View {
        let shown = family.card
        let title = { (chat: Chat) in short ? taskTitle(chat) : chat.title }
        GroupCardView(card: Tree.Card(id: shown.id, name: title(family.parent), chats: shown.chats, counts: shown.counts,
                                      lead: shown.lead),
                      isUnread: board.isUnread(shown), holdsCurrent: board.holdsCurrent(shown),
                      scale: board.priority(of: .chat(family.parent.id)).scale, expanded: !family.folded,
                      noun: "chat", openHelp: "Open this chat") {
            ForEach(shown.chats) { chat in row(chat, title: title(chat), card: card, indent: false) }
        }
        .background(reportHit(shown.id))
        .contextMenu {
            Button("Open") { board.open(family.parent) }
            Button(family.folded ? "Expand here" : "Fold here") { board.toggleFamily(family.parent.id) }
            Button("Rename chat") { board.startRename(family.parent) }
            if card == nil { MoveToMenu(board: board, node: .chat(family.parent.id)) }
            PriorityMenu(board: board, node: .chat(family.parent.id))
            Divider()
            Button("Archive") { board.archive(family.parent) }
        }
    }

    // A project's chats, on its page or inside its card when expanded on the board.
    @ViewBuilder
    private func cardRows(_ card: Tree.Card) -> some View {
        VStack(spacing: 2) {
            ForEach(board.families(card.chats), id: \.parent.id) { family in
                if family.children.isEmpty {
                    draggable(row(family.parent, title: taskTitle(family.parent), card: card.id), .chat(family.parent.id),
                              in: .group(card.id))
                } else {
                    draggable(familyCard(family, short: true, card: card.id), .chat(family.parent.id), in: .group(card.id))
                }
            }
        }
        .padding(.top, 4)
    }

    // While searching, every matching chat in one flat list, as before groups existed.
    @ViewBuilder
    private var results: some View {
        let shown = board.shown
        if shown.isEmpty {
            Text("No chats match.").font(.system(size: 14)).foregroundStyle(.secondary).padding(8)
        }
        ForEach(Array(shown.enumerated()), id: \.element.id) { index, chat in
            ChatRow(chat: chat, isCurrent: chat.id == board.currentId, isUnread: board.isUnread(chat),
                    isSelected: index == board.selected, scale: board.priority(of: .chat(chat.id)).scale)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: WindowFrames.self, value: [chat.id: geometry.frame(in: .global)])
                })
                .id(chat.id)
        }
    }

    private var boardHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Counts sit beside the title when there's room, under it when the window is narrow.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Chats").font(.system(size: 20, weight: .bold))
                    searchButton
                    Spacer(minLength: 8)
                    counts
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Chats").font(.system(size: 20, weight: .bold))
                        searchButton
                    }
                    counts
                }
            }
            Flow(spacing: 12) {
                ForEach(Kind.allCases, id: \.self) { kind in
                    HStack(spacing: 3) {
                        Circle().fill(kind.color).frame(width: 10, height: 10)
                        Text(kind.label).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    var body: some View {
        let card = board.isSearching ? nil : board.openCard
        VStack(alignment: .leading, spacing: 6) {
            // Pinned: everything above the scrolling list stays put while it scrolls.
            if let card {
                ProjectHeader(card: card, sectionName: board.openSectionName, total: board.chats.count,
                              questionElsewhere: board.questionElsewhere)
            } else {
                boardHeader
            }
            if board.isSearching { SearchField(board: board) }
            // A plain stack rather than a List: a List drops the first click in a window that isn't focused,
            // and the panel is never focused (Claude stays in front). Click and drag are handled here instead.
            ScrollViewReader { scroller in
            ScrollView {
                VStack(spacing: 2) {
                    Color.clear.frame(height: 0).id("top")
                    if board.isSearching { results } else if let card { page(card) } else { home }
                }
                .padding(.vertical, 2)
            }
            .coordinateSpace(name: "list")
            .onChange(of: board.selected) { _, index in
                let shown = board.shown
                if shown.indices.contains(index) { scroller.scrollTo(shown[index].id) }
            }
            // Opening a project, or going back, starts at the top of the list.
            .onChange(of: board.openGroupId) { _, _ in scroller.scrollTo("top", anchor: .top) }
            }
            .onPreferenceChange(DragSlots.self) { board.slots = $0 }
            .onPreferenceChange(WindowFrames.self) { board.rowsInWindow = $0 }
        }
        .onPreferenceChange(ControlFrames.self) { board.controlsInWindow = $0 }
        // Read here, above both the pinned header and the list, so the banner and breadcrumb report too.
        .onPreferenceChange(HitFrames.self) { board.hitsInWindow = $0 }
        .padding(10)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        // While dragging: where it will land, and the dragged thing under the pointer.
        .overlay(alignment: .topLeading) { DragOverlay(board: board) }
        // Notices float over the bottom of the board instead of pushing the list down.
        .overlay(alignment: .bottom) { NoticeBar(notice: board.notice).animation(.easeOut(duration: 0.2), value: board.notice.text) }
        // The whole board is framed while a project is open, so it never passes for the full list.
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(card == nil ? 0 : 1)
                .allowsHitTesting(false)
        )
    }

    private var searchButton: some View {
        Button {
            board.startSearch()
        } label: {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Search chats (Cmd+F)")
        .background(reportFrame("searchButton"))
    }

    private var counts: some View {
        Text("\(board.chats.filter { $0.kind == .question }.count) questions · \(board.chats.filter { $0.kind == .yourMove }.count) your move · \(board.chats.filter { $0.kind == .ready }.count) ready")
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

// MARK: App

// The panel never becomes the active window, so without this the first click on it only focuses it.
final class FirstClickHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// Gives the keyboard back to Claude. Activating Claude alone isn't enough: once the board has held the keyboard,
// Claude can still be the front app while its window no longer has focus, and activating an app that is already in
// front does nothing. So the board lets go of the keyboard first, then Claude's window is raised through Accessibility.
@MainActor
func returnFocusToClaude(from panel: NSPanel?) {
    if let panel = panel as? ClickThroughPanel { panel.allowsKey = false }
    if let panel, panel.isKeyWindow { panel.resignKey() }
    if NSApp.isActive { NSApp.deactivate() }
    guard let claude = NSRunningApplication.runningApplications(withBundleIdentifier: AppDelegate.claude).first else { return }
    claude.activate()
    guard AXIsProcessTrusted() else { return }
    let app = AXUIElementCreateApplication(claude.processIdentifier)
    AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    var window: CFTypeRef?
    for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
        if AXUIElementCopyAttributeValue(app, attribute as CFString, &window) == .success, let window {
            AXUIElementPerformAction(window as! AXUIElement, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(window as! AXUIElement, kAXMainAttribute as CFString, kCFBooleanTrue)
            return
        }
    }
}

// The board only takes the keyboard while you search: clicks and drags work without it, and typing stays in Claude.
final class ClickThroughPanel: NSPanel {
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }

    // A window that isn't focused loses SwiftUI's first click, but every click still passes through here.
    // A press and release within a few points is a click; anything longer is a drag, left to the list.
    // onClick says whether the click opened a chat.
    var onClick: ((CGPoint) -> Bool)?
    // True while the search box is open, so a click in it keeps the keyboard here.
    var keepsKeyboard: () -> Bool = { false }
    private var pressedAt: CGPoint?

    // The board's drag handling: press, move and release, in the window's top-left space. A release returns true
    // when it ended a drag, so that it isn't also taken for a click.
    var onPress: ((CGPoint) -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onRelease: ((CGPoint) -> Bool)?

    private func topLeft(_ event: NSEvent) -> CGPoint {
        CGPoint(x: event.locationInWindow.x, y: frame.height - event.locationInWindow.y)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { pressedAt = event.locationInWindow; onPress?(topLeft(event)) }
        if event.type == .leftMouseDragged { onDrag?(topLeft(event)) }
        if event.type == .leftMouseUp, onRelease?(topLeft(event)) == true {
            pressedAt = nil
            super.sendEvent(event)
            returnFocusToClaude(from: self)
            return
        }
        if event.type == .leftMouseUp, let start = pressedAt {
            let end = event.locationInWindow
            var openedChat = false
            if hypot(end.x - start.x, end.y - start.y) < 4 {
                // AppKit counts from the window's bottom; SwiftUI's window space counts from the top.
                openedChat = onClick?(CGPoint(x: end.x, y: frame.height - end.y)) ?? false
            }
            pressedAt = nil
            super.sendEvent(event)
            if !openedChat && keepsKeyboard() { return }
            // Whatever the click or drag did, the keyboard belongs to Claude afterwards.
            returnFocusToClaude(from: self)
            return
        }
        super.sendEvent(event)
    }

}

// Keeps the board pinned to the screen's left edge at full height and Claude's window filling the rest,
// so the two always add up to the screen's width. Resizing either one resizes the other.
// Moving Claude's window needs the Accessibility permission; without it only the board docks.
@MainActor
final class ClaudeDock: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private var observer: AXObserver?
    private var watchedWindow: AXUIElement?
    private var watchedPid: pid_t = 0
    private var isAdjusting = false
    private let geometry = DockGeometry(minPanelWidth: 200)

    init(panel: NSPanel) {
        self.panel = panel
        super.init()
        panel.delegate = self
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        if !AXIsProcessTrusted() {
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        }
    }

    private var area: NSRect { (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero }

    // Pins the board to the left edge and fits Claude beside it.
    func dock() {
        setPanel(width: geometry.clampPanelWidth(panel.frame.width, area: area))
        attach()
        fitClaude()
    }

    private func setPanel(width: CGFloat) {
        let frame = geometry.panelFrame(width: width, area: area)
        if panel.frame != frame {
            isAdjusting = true
            panel.setFrame(frame, display: true)
            isAdjusting = false
        }
    }

    // The board only grows or shrinks from its right edge, and always stays full height.
    func windowWillResize(_ sender: NSWindow, to size: NSSize) -> NSSize {
        geometry.panelSizeForResize(to: size, area: area)
    }

    func windowDidResize(_ notification: Notification) {
        guard !isAdjusting else { return }
        setPanel(width: panel.frame.width)
        fitClaude()
    }

    // MARK: Claude's window, through the Accessibility API

    private var claudeApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: AppDelegate.claude).first
    }

    private func claudeWindow() -> AXUIElement? {
        guard AXIsProcessTrusted(), let pid = claudeApp?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            if AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success, let value {
                return (value as! AXUIElement)
            }
        }
        return nil
    }

    // The main screen's height, for turning Accessibility coordinates into AppKit ones.
    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private func frame(of window: AXUIElement) -> NSRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return DockGeometry.appKitFrame(axOrigin: point, size: extent, primaryHeight: primaryHeight)
    }

    private func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value) == .success && (value as? Bool) == true
    }

    func fitClaude() {
        guard panel.isVisible, let window = claudeWindow(), !isFullScreen(window) else { return }
        let target = geometry.claudeFrame(panelWidth: panel.frame.width, area: area)
        guard geometry.needsMove(frame(of: window), to: target) else { return }
        isAdjusting = true
        var point = DockGeometry.axOrigin(of: target, primaryHeight: primaryHeight)
        var size = CGSize(width: target.width, height: target.height)
        if let position = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) }
        if let extent = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, extent) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.isAdjusting = false }
    }

    // When you resize Claude, the board takes whatever width is left, then Claude is squared up beside it.
    fileprivate func claudeChanged() {
        guard !isAdjusting, panel.isVisible, let window = claudeWindow(), !isFullScreen(window), let now = frame(of: window) else {
            attach()
            return
        }
        let width = geometry.panelWidth(afterClaudeMovedTo: now, area: area)
        if geometry.panelNeedsResize(current: panel.frame.width, wanted: width) { setPanel(width: width) }
        fitClaude()
        attach()
    }

    // What docking can see, written where it can be read back when docking misbehaves.
    func writeStatus() {
        let window = claudeWindow()
        let status: [String: Any] = [
            "at": Date().timeIntervalSince1970 * 1000,
            "accessibilityAllowed": AXIsProcessTrusted(),
            "claudeRunning": claudeApp != nil,
            "claudeWindowFound": window != nil,
            "claudeFrame": window.flatMap { frame(of: $0) }.map { "\(Int($0.minX)),\(Int($0.width))" } ?? "",
            "boardFrame": "\(Int(panel.frame.minX)),\(Int(panel.frame.width))",
            "watching": watchedWindow != nil,
            // Who has the keyboard, for when focus doesn't come back to Claude after a click on the board.
            "frontApp": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "",
            "boardAppActive": NSApp.isActive,
            "boardIsKey": panel.isKeyWindow,
            "boardAllowsKey": (panel as? ClickThroughPanel)?.allowsKey ?? false,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: status) {
            FileManager.default.createFile(atPath: shareDir + "/dock-status.json", contents: data)
        }
    }

    // Watches Claude's current window for moves and resizes, and the app for switching windows.
    func attach() {
        guard AXIsProcessTrusted(), let pid = claudeApp?.processIdentifier else { return }
        if pid != watchedPid {
            if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
            observer = nil
            watchedWindow = nil
            var created: AXObserver?
            let callback: AXObserverCallback = { _, _, _, refcon in
                guard let refcon else { return }
                let dock = Unmanaged<ClaudeDock>.fromOpaque(refcon).takeUnretainedValue()
                MainActor.assumeIsolated { dock.claudeChanged() }
            }
            guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
            observer = created
            watchedPid = pid
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
            let app = AXUIElementCreateApplication(pid)
            let me = Unmanaged.passUnretained(self).toOpaque()
            AXObserverAddNotification(created, app, kAXMainWindowChangedNotification as CFString, me)
            AXObserverAddNotification(created, app, kAXFocusedWindowChangedNotification as CFString, me)
        }
        guard let observer, let window = claudeWindow() else { return }
        if let watchedWindow, CFEqual(watchedWindow, window) { return }
        let me = Unmanaged.passUnretained(self).toOpaque()
        if let watchedWindow {
            AXObserverRemoveNotification(observer, watchedWindow, kAXResizedNotification as CFString)
            AXObserverRemoveNotification(observer, watchedWindow, kAXMovedNotification as CFString)
        }
        AXObserverAddNotification(observer, window, kAXResizedNotification as CFString, me)
        AXObserverAddNotification(observer, window, kAXMovedNotification as CFString, me)
        watchedWindow = window
    }
}

// Cmd+D makes Claude's microphone toggle instead of hold-to-talk: while Claude or the board is in front,
// Chat Board brings Claude forward and clicks its microphone button (an accessibility press, the same as a
// mouse click), and holds back the original keystroke. No audio is touched. If the button isn't there,
// for example while Claude is replying and shows Stop instead, the keystroke passes through unchanged.
@MainActor
final class DictationToggle {
    private var tap: CFMachPort?
    private static let dKey: Int64 = 0x02
    private static let fKey: Int64 = 0x03
    // Cmd+F: set by the app. Taken only while Claude or the board is in front and the board is showing.
    var isBoardShowing: () -> Bool = { false }
    var onFind: () -> Void = {}

    func wantsFind() -> Bool {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return (front == AppDelegate.claude || front == Bundle.main.bundleIdentifier) && isBoardShowing()
    }

    // Clicks Claude's own Edit > Find, for searching inside the chat. False when the menu item isn't there.
    @discardableResult
    func openClaudeFind() -> Bool {
        guard let claude = NSRunningApplication.runningApplications(withBundleIdentifier: AppDelegate.claude).first,
              let item = DictationToggle.findMenuItem(in: claude) else { return false }
        claude.activate()
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    // Claude's Edit > Find menu item, matched by its shortcut. Also used by `ChatBoard --check-claude`.
    static func findMenuItem(in claude: NSRunningApplication) -> AXUIElement? {
        func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
            var result: CFTypeRef?
            AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
            return result
        }
        func find(_ element: AXUIElement, depth: Int) -> AXUIElement? {
            guard depth < 6 else { return nil }
            // Cmd+F with no other modifier (0) is Find; Cmd+Shift+F is Show Files.
            if (value(element, "AXMenuItemCmdChar") as? String)?.uppercased() == "F",
               (value(element, "AXMenuItemCmdModifiers") as? Int) == 0 { return element }
            for child in (value(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
                if let found = find(child, depth: depth + 1) { return found }
            }
            return nil
        }
        let app = AXUIElementCreateApplication(claude.processIdentifier)
        guard let bar = value(app, kAXMenuBarAttribute) else { return nil }
        return find(bar as! AXUIElement, depth: 0)
    }

    init() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let toggle = Unmanaged<DictationToggle>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                MainActor.assumeIsolated { toggle.reenable() }
                return Unmanaged.passUnretained(event)
            }
            let flags = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            guard type == .keyDown, flags == .maskCommand,
                  event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return Unmanaged.passUnretained(event) }
            if key == DictationToggle.fKey {
                // Answered at once and handled after, so the tap never waits on the window.
                guard MainActor.assumeIsolated({ toggle.wantsFind() }) else { return Unmanaged.passUnretained(event) }
                DispatchQueue.main.async { MainActor.assumeIsolated { toggle.onFind() } }
                return nil
            }
            guard key == DictationToggle.dKey else { return Unmanaged.passUnretained(event) }
            let handled = MainActor.assumeIsolated { toggle.clickMicrophone() }
            return handled ? nil : Unmanaged.passUnretained(event)
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: callback,
                                userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap {
            CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    // Brings Claude forward and clicks the microphone button in its front window. False when it isn't there.
    func clickMicrophone() -> Bool {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard front == AppDelegate.claude || front == Bundle.main.bundleIdentifier,
              let claude = NSRunningApplication.runningApplications(withBundleIdentifier: AppDelegate.claude).first,
              let button = DictationToggle.microphoneButton(in: claude) else { return false }
        claude.activate()
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    // The microphone button in Claude's front window. Also used by `ChatBoard --check-claude`.
    static func microphoneButton(in claude: NSRunningApplication) -> AXUIElement? {
        let app = AXUIElementCreateApplication(claude.processIdentifier)
        // Claude is an Electron app: its page only shows up to accessibility once asked.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window else { return nil }
        return microphone(in: window as! AXUIElement, depth: 0)
    }

    private static func microphone(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 60 else { return nil }
        func text(_ attribute: String) -> String {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            return (value as? String) ?? ""
        }
        if text(kAXRoleAttribute) == kAXButtonRole as String {
            let shortcut = text("AXKeyShortcutsValue").lowercased()
            let label = (text(kAXDescriptionAttribute) + " " + text(kAXTitleAttribute)).lowercased()
            if shortcut == "meta+d" || label.contains("dictat") || label.contains("voice input") || label.contains("microphone") {
                return element
            }
        }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let list = children as? [AXUIElement] else { return nil }
        for child in list.reversed() {  // the prompt box sits at the bottom of the window
            if let found = microphone(in: child, depth: depth + 1) { return found }
        }
        return nil
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private var dock: ClaudeDock!
    private var dictation: DictationToggle!
    private var board: BoardModel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let board = BoardModel()
        panel = ClickThroughPanel(
            contentRect: NSRect(x: 40, y: 120, width: 400, height: 760),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Chats"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        // A normal window, not a floating one: it comes forward with Claude, and any other app you
        // switch to can sit on top of it. It stays on screen behind them instead of hiding.
        panel.level = .normal
        panel.hidesOnDeactivate = false
        // Lives on one Space, the one Claude is on, and moves to the current Space only when it is brought
        // forward (followClaude, toggle). Not .canJoinAllSpaces: that put the board on every Space, including
        // another app's fullscreen Space, where it sat over a fullscreen browser video.
        // .fullScreenAuxiliary still lets it sit beside Claude when Claude itself is fullscreen.
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentView = FirstClickHostingView(rootView: AnyView(BoardView(board: board).background(.regularMaterial)))
        let clickPanel = panel as! ClickThroughPanel
        clickPanel.onClick = { [weak board] point in board?.click(at: point) ?? false }
        clickPanel.onPress = { [weak board] point in board?.mousePressed(at: point) }
        clickPanel.onDrag = { [weak board] point in board?.mouseDragged(to: point) }
        clickPanel.onRelease = { [weak board] point in board?.mouseReleased(at: point) ?? false }
        clickPanel.keepsKeyboard = { [weak board] in (board?.isSearching ?? false) || board?.editingId != nil }
        // Editing a chat's title in place gives the board the keyboard; finishing gives it back to Claude.
        board.onEditChange = { [weak clickPanel] editing in
            guard let clickPanel else { return }
            if editing {
                clickPanel.allowsKey = true
                clickPanel.makeKeyAndOrderFront(nil)
            } else {
                returnFocusToClaude(from: clickPanel)
            }
        }
        // Renaming a group asks in a small dialog. The board takes the keyboard for it, then hands it back to Claude.
        board.askName = { [weak clickPanel] heading, current in
            let alert = NSAlert()
            alert.messageText = heading
            alert.addButton(withTitle: "Rename")
            alert.addButton(withTitle: "Cancel")
            let field = NSTextField(string: current)
            field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
            NSApp.activate(ignoringOtherApps: true)
            let answer = alert.runModal()
            returnFocusToClaude(from: clickPanel)
            return answer == .alertFirstButtonReturn ? field.stringValue : nil
        }
        // Searching gives the board the keyboard; closing the search gives it back to Claude.
        board.onSearchChange = { [weak clickPanel] searching in
            guard let clickPanel else { return }
            if searching {
                clickPanel.allowsKey = true
                clickPanel.makeKeyAndOrderFront(nil)
            } else {
                returnFocusToClaude(from: clickPanel)
            }
        }
        board.onSearchDropped = { [weak clickPanel] in clickPanel?.allowsKey = false }
        // Clicking anywhere else closes the search, so a leftover filter never sits there while you work.
        // The keyboard stays wherever you clicked, so another app you switched to keeps it.
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak board, weak clickPanel] _ in
            MainActor.assumeIsolated {
                board?.dropSearch()
                board?.dropRename()
                clickPanel?.allowsKey = false
            }
        }
        self.board = board
        board.isPointerHeld = { [weak panel] in
            guard let panel, panel.isVisible else { return false }
            return NSEvent.pressedMouseButtons & 1 != 0 && panel.frame.contains(NSEvent.mouseLocation)
        }
        panel.contentMinSize = NSSize(width: 200, height: 240)
        panel.setFrameAutosaveName("ChatBoardPanel")
        dock = ClaudeDock(panel: panel)
        // Until the Accessibility permission is granted, keep checking so docking starts the moment it is.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.panel.isVisible == true { self?.dock.attach(); self?.dock.fitClaude() }
                self?.dock.writeStatus()
            }
        }
        // CHAT_BOARD_STATE=<file>: the end-to-end tests read what the board is showing from here (see e2e/).
        if let statePath = ProcessInfo.processInfo.environment["CHAT_BOARD_STATE"] {
            Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.writeState(to: statePath) }
            }
        }
        followClaude(NSWorkspace.shared.frontmostApplication)
        // Launching can briefly put another app in front; look again once that settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.followClaude(NSWorkspace.shared.frontmostApplication)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.followClaude(app) }
        }
        // Swiping from another app's fullscreen Space back to Claude makes Claude active mid-animation, before the
        // Space has switched, so the board was ordered onto the old Space. Bring it forward again once the switch lands.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.followClaude(NSWorkspace.shared.frontmostApplication) }
        }
        // The board leaves only when Claude does: hidden with Cmd+H or quit. It comes back when Claude is shown again.
        for name in [NSWorkspace.didHideApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == Self.claude else { return }
                MainActor.assumeIsolated { self?.board?.dropSearch(); self?.panel.orderOut(nil) }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Self.claude else { return }
            MainActor.assumeIsolated { self?.followClaude(app) }
        }

        dictation = DictationToggle()
        dictation.isBoardShowing = { [weak self] in self?.panel.isVisible ?? false }
        // Cmd+F searches the board. Pressed again while the search is open, it opens Claude's own Find instead.
        dictation.onFind = { [weak self] in
            guard let self else { return }
            if self.board.isSearching {
                self.board.endSearch()
                self.dictation.openClaudeFind()
            } else {
                self.board.startSearch()
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "list.bullet.rectangle", accessibilityDescription: "Chat Board")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show or hide Chat Board", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(withTitle: "Chat Board sits with Claude; other apps can cover it", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Chat Board", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.first?.target = self
        statusItem.menu = menu
    }

    // Comes forward with Claude and stays on screen when another app is in front, underneath that app's
    // windows (it is a normal-level window). It goes away only when Claude is hidden or quits.
    // The panel never takes focus itself, so clicking it keeps Claude in front.
    // The app the board docks beside. Tests point it at a stand-in app with CHAT_BOARD_TARGET (see e2e/).
    nonisolated static let claude = ProcessInfo.processInfo.environment["CHAT_BOARD_TARGET"] ?? "com.anthropic.claudefordesktop"
    private var isHiddenByPerson = false

    func followClaude(_ app: NSRunningApplication?) {
        if app?.bundleIdentifier == Self.claude, !isHiddenByPerson {
            panel.orderFrontRegardless()
            dock.dock()
        } else if app?.bundleIdentifier != Bundle.main.bundleIdentifier {
            // Another app came forward: its windows now cover the board. Close any search, keep the board where it is.
            board?.dropSearch()
        }
    }

    // Rows and controls in screen coordinates (top-left origin, the same space posted mouse events use).
    private func writeState(to path: String) {
        let top = (NSScreen.screens.first?.frame.height ?? 0) - panel.frame.maxY
        func screen(_ rect: CGRect) -> [Double] {
            [panel.frame.minX + rect.minX, top + rect.minY, rect.width, rect.height].map { Double($0) }
        }
        let shown = board.visibleChats
        let state: [String: Any] = [
            "at": Date().timeIntervalSince1970 * 1000,
            "visible": panel.isVisible,
            "windowNumber": panel.windowNumber,
            "panel": [panel.frame.minX, top, panel.frame.width, panel.frame.height].map { Double($0) },
            "isSearching": board.isSearching,
            "query": board.query,
            "selected": board.selected,
            "notice": board.notice.text ?? "",
            "panelIsKey": panel.isKeyWindow,
            "rows": shown.map { chat -> [String: Any] in
                ["id": chat.id, "localId": chat.localId, "title": chat.title, "depth": chat.depth,
                 "frame": board.rowsInWindow[chat.id].map(screen) ?? []]
            },
            "controls": board.controlsInWindow.mapValues(screen),
            "hits": board.hitsInWindow.mapValues(screen),
            "openGroup": board.openGroupId ?? "",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: state) {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    @objc func toggle() {
        isHiddenByPerson = panel.isVisible
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless(); dock.dock() }
    }
}

// Debugging aid for the Cmd+D shortcut: prints every button in Claude's front window with its accessibility
// labels, so the microphone button can be found again if an app update renames it.
func listClaudeButtons() {
    guard AXIsProcessTrusted(),
          let claude = NSRunningApplication.runningApplications(withBundleIdentifier: AppDelegate.claude).first else {
        print("not allowed or Claude not running")
        return
    }
    func text(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (value as? String) ?? ""
    }
    var seen = 0
    var roles: [String: Int] = [:]
    func walk(_ element: AXUIElement, depth: Int) {
        guard depth < 60, seen < 4000 else { return }
        seen += 1
        roles[text(element, kAXRoleAttribute), default: 0] += 1
        if text(element, kAXRoleAttribute) == kAXButtonRole as String {
            var names: CFArray?
            AXUIElementCopyAttributeNames(element, &names)
            var parts: [String] = []
            for name in (names as? [String]) ?? [] {
                var value: CFTypeRef?
                AXUIElementCopyAttributeValue(element, name as CFString, &value)
                if let string = value as? String, !string.isEmpty { parts.append("\(name)=\(string.prefix(40))") }
                if let list = value as? [String], !list.isEmpty { parts.append("\(name)=\(list.joined(separator: ",").prefix(60))") }
            }
            print("button:", parts.joined(separator: " | "))
        }
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let list = children as? [AXUIElement] {
            for child in list { walk(child, depth: depth + 1) }
        }
    }
    let app = AXUIElementCreateApplication(claude.processIdentifier)
    // Electron apps only build their page's accessibility tree once asked to.
    AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    Thread.sleep(forTimeInterval: 1)
    var window: CFTypeRef?
    AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window)
    if let window { walk(window as! AXUIElement, depth: 0) } else { print("no window") }
    var windows: CFTypeRef?
    AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
    print("windows:", (windows as? [AXUIElement])?.count ?? 0, "| elements walked:", seen, "| roles:", roles.sorted { $0.value > $1.value }.prefix(12).map { "\($0.key)=\($0.value)" }.joined(separator: " "))
}

// Exit 0 when both are found, 1 when either is missing, 2 when it can't look (no permission, Claude not running).
@MainActor
func checkClaude() -> Int32 {
    guard AXIsProcessTrusted() else {
        print("Can't look: this program needs Accessibility (System Settings > Privacy & Security > Accessibility).")
        return 2
    }
    guard let claude = NSRunningApplication.runningApplications(withBundleIdentifier: AppDelegate.claude).first else {
        print("Can't look: \(AppDelegate.claude) isn't running.")
        return 2
    }
    // The page only appears to accessibility a moment after it's asked for, the first time.
    var mic = DictationToggle.microphoneButton(in: claude)
    for _ in 0..<10 where mic == nil {
        Thread.sleep(forTimeInterval: 0.3)
        mic = DictationToggle.microphoneButton(in: claude)
    }
    let find = DictationToggle.findMenuItem(in: claude)
    print("microphone button (Cmd+D): \(mic != nil ? "found" : "MISSING (the chat in front has to show its message box: not mid-reply, and no question or permission card open)")")
    print("Edit > Find menu item (second Cmd+F): \(find != nil ? "found" : "MISSING")")
    return mic != nil && find != nil ? 0 : 1
}

@MainActor
private func snapshot(to path: String, width: Double, height: Double, search: String?, project: String? = nil,
                      expand: String? = nil, notice: String? = nil) {
    let board = BoardModel()
    if let notice { board.notice.text = notice }
    if let expand, let card = board.cards.first(where: { $0.name == expand }), !board.isExpanded(card.id) {
        board.toggleExpanded(card.id)
    }
    if let search { board.startSearch(); board.query = search }
    if let project, let card = board.cards.first(where: { $0.name == project }) { board.openProject(card.id) }
    let view = NSHostingView(rootView: BoardView(board: board).background(Color(nsColor: .windowBackgroundColor)))
    view.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = view
    view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

@main
struct ChatBoardApp {
    static func main() {
        let app = NSApplication.shared
        // `ChatBoard --check-claude` checks, without pressing anything, that the real Claude app still has the
        // microphone button and the Find menu item the shortcuts press. Run it after a Claude update.
        if CommandLine.arguments.contains("--check-claude") {
            exit(MainActor.assumeIsolated { checkClaude() })
        }
        // `ChatBoard --find-buttons` lists Claude's buttons, to find the ones Chat Board presses.
        if CommandLine.arguments.contains("--find-buttons") {
            listClaudeButtons()
            return
        }
        // `ChatBoard --snapshot out.png` draws the board once to an image and exits, so it can be checked by eye.
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(flag + 1) {
            let width = arguments.firstIndex(of: "--width").flatMap { arguments.indices.contains($0 + 1) ? Double(arguments[$0 + 1]) : nil } ?? 400
            let height = arguments.firstIndex(of: "--height").flatMap { arguments.indices.contains($0 + 1) ? Double(arguments[$0 + 1]) : nil } ?? 760
            let search = arguments.firstIndex(of: "--search").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            let project = arguments.firstIndex(of: "--project").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            let expand = arguments.firstIndex(of: "--expand").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            let notice = arguments.firstIndex(of: "--notice").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            MainActor.assumeIsolated {
                snapshot(to: arguments[flag + 1], width: width, height: height, search: search, project: project, expand: expand,
                         notice: notice)
            }
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
