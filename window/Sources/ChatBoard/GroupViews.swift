import ChatBoardCore
import SwiftUI

// The pieces the grouped board is drawn from: status bars, section headers, project cards and the project page's
// pinned header. None of them take clicks themselves. The panel never becomes the key window, so SwiftUI would drop
// the first click; instead each reports its frame (HitFrames) and BoardModel.click(at:) decides what a click did.

// Frames of cards, section headers and the ways home, in window space, keyed like "group:<id>".
struct HitFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// Everything that can be dragged, with its container and window frame, for working out where a drop lands.
struct DragSlots: PreferenceKey {
    static let defaultValue: [Node: DropSlot] = [:]
    static func reduce(value: inout [Node: DropSlot], nextValue: () -> [Node: DropSlot]) {
        value.merge(nextValue()) { $1 }
    }
}

func reportHit(_ key: String) -> some View {
    GeometryReader { geometry in
        Color.clear.preference(key: HitFrames.self, value: [key: geometry.frame(in: .global)])
    }
}


// The task part of a chat title, for rows inside a project where the tag and project would only repeat the header.
func taskTitle(_ chat: Chat) -> String {
    let parsed = TitleParse.parse(chat.title)
    return parsed.project == nil || parsed.task.isEmpty ? chat.title : parsed.task
}

// A chat title without its `[tag]`, for loose chats inside a section, where the header already says the tag.
func untaggedTitle(_ chat: Chat) -> String {
    let parsed = TitleParse.parse(chat.title)
    guard parsed.tag != nil else { return chat.title }
    return parsed.project.map { "\($0) - \(parsed.task)" } ?? parsed.task
}

// One bar split by status, in the same four colors as the rows, most urgent on the left.
struct StatusBar: View {
    let counts: [Kind: Int]
    var height: CGFloat = 4

    var body: some View {
        let kinds = [Kind.question, .yourMove, .ready, .working].filter { (counts[$0] ?? 0) > 0 }
        GeometryReader { geometry in
            let total = CGFloat(kinds.reduce(0) { $0 + (counts[$1] ?? 0) })
            let gaps = CGFloat(max(kinds.count - 1, 0)) * 1.5
            HStack(spacing: 1.5) {
                ForEach(kinds, id: \.self) { kind in
                    Rectangle().fill(kind.color)
                        .frame(width: max(0, (geometry.size.width - gaps) * CGFloat(counts[kind] ?? 0) / max(total, 1)))
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

struct SectionHeader: View {
    let block: Tree.SectionBlock
    // The most urgent kind among the section's unread chats; nil when all are read, which dims the header.
    var unreadKind: Kind? = nil
    private var isUnread: Bool { unreadKind != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: block.collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Text(block.name)
                    .font(.system(size: 13, weight: isUnread ? .bold : .semibold))
                    .foregroundStyle(isUnread ? Color.primary : Color.secondary)
                    .textCase(.uppercase)
                Spacer(minLength: 4)
                if let kind = unreadKind {
                    Circle().fill(kind.color).frame(width: 8, height: 8)
                }
                Text("\(block.counts.values.reduce(0, +))")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            if block.collapsed { StatusBar(counts: block.counts, height: 3).opacity(isUnread ? 1 : 0.4) }
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .contentShape(Rectangle())
    }
}

// Under a parent chat that started side chats: a fold arrow, how many there are, and their status bar. A click on it
// folds or opens the side chats (BoardModel.click). Folded, the side chats that need the person still show below it.
struct FamilyStrip: View {
    let block: Family.Block
    @State private var isHovered = false

    private var summary: String {
        let total = block.children.count
        var parts = [total == 1 ? "1 side chat" : "\(total) side chats"]
        if block.folded {
            let hidden = total - block.shown.count
            if hidden > 0, block.shown.count > 0 { parts.append("\(hidden) hidden") }
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: block.folded ? "chevron.right" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            Text(summary)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            StatusBar(counts: block.counts, height: 3).opacity(block.folded ? 0.9 : 0.4)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(isHovered ? 0.07 : 0.03)))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help(block.folded ? "Show the side chats" : "Fold the side chats")
        .padding(.leading, 18)
    }
}

// A project card. A click anywhere on it folds or opens it in place (the up/down arrow left of the name shows which),
// showing its chats inside the card like a section; only the right arrow opens the project's own page (Mo, 2026-11-14).
// Folded, it shows the chat that needs the person most.
struct GroupCardView<Rows: View>: View {
    let card: Tree.Card
    let isUnread: Bool
    let holdsCurrent: Bool
    // The card's priority: 1 is the normal size, 0.85 low, 1.3 high.
    var scale: Double = 1
    var expanded: Bool = false
    @ViewBuilder var rows: () -> Rows
    @State private var isHovered = false

    private func arrow(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12 * scale, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 22 * scale, height: 20 * scale)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(isHovered ? 0.07 : 0)))
            .contentShape(Rectangle())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            HStack(alignment: .center, spacing: 6) {
                arrow(expanded ? "chevron.up" : "chevron.down")
                    .help(expanded ? "Fold this project back" : "Show this project's chats here")
                    .padding(.leading, -4)
                Text(card.name)
                    .font(.system(size: 16 * scale, weight: isUnread ? .bold : .regular))
                    .foregroundStyle(Color.primary.opacity(isUnread ? 1 : 0.62))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isUnread, let lead = card.lead { Circle().fill(lead.kind.color).frame(width: 8 * scale, height: 8 * scale) }
                Text(card.chats.count == 1 ? "1 task" : "\(card.chats.count) tasks")
                    .font(.system(size: 12 * scale))
                    .foregroundStyle(.secondary)
                arrow("chevron.right")
                    .help("Open this project on its own")
                    .background(reportHit("open:" + card.id))
            }
            // Read cards dim like a read chat row, so a bright card always means something new inside.
            StatusBar(counts: card.counts).opacity(isUnread ? 1 : 0.4)
            if expanded {
                // Rows sit a little wider than the header so their status stripes line up under the card's edge.
                VStack(spacing: 2) { rows() }.padding(.horizontal, -4)
            } else if let lead = card.lead {
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(lead.kind.color.opacity(isUnread ? 1 : 0.4)).frame(width: 7 * scale, height: 7 * scale).padding(.top, 5 * scale)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(taskTitle(lead)).font(.system(size: 14 * scale))
                            .foregroundStyle(Color.primary.opacity(isUnread ? 1 : 0.62)).lineLimit(1)
                        if !lead.line.isEmpty {
                            Text(lead.line).font(.system(size: 13 * scale))
                                .foregroundStyle(Color.primary.opacity(isUnread ? 0.75 : 0.42)).lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8 * scale)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.primary.opacity(isHovered && !expanded ? 0.09 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(holdsCurrent ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: holdsCurrent ? 1.5 : 0.5)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

// Pinned above the list while a project is open: a banner that says the board is filtered and leads home,
// the path to the project (each part leads home too), and the project's name with its status bar.
struct ProjectHeader: View {
    let card: Tree.Card
    let sectionName: String?
    let total: Int
    let questionElsewhere: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.left").font(.system(size: 13, weight: .semibold))
                    Text("All chats").font(.system(size: 14, weight: .semibold))
                    if questionElsewhere {
                        Circle().fill(Kind.question.color).frame(width: 8, height: 8)
                            .help("A chat outside this project is asking you something")
                    }
                }
                Spacer(minLength: 6)
                Text("\(card.chats.count) of \(total) shown").font(.system(size: 12)).opacity(0.85)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.14)))
            .background(reportHit("home:banner"))

            HStack(spacing: 4) {
                Text("All chats").foregroundStyle(Color.accentColor).background(reportHit("home:crumb-all"))
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                if let sectionName {
                    Text(sectionName).foregroundStyle(Color.accentColor).background(reportHit("home:crumb-section"))
                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                Text(card.name).fontWeight(.medium).lineLimit(1)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(card.name).font(.system(size: 20, weight: .bold)).lineLimit(1)
                StatusBar(counts: card.counts, height: 6)
            }
            .padding(.horizontal, 2)
        }
    }
}

// The right-click Move to menu for a chat: every project group, every section, or out of all of them.
struct MoveToMenu: View {
    @ObservedObject var board: BoardModel
    let node: Node

    var body: some View {
        let targets = board.moveTargets
        let here = board.container(of: node)
        Menu("Move to") {
            if case .chat = node, !targets.groups.isEmpty {
                Section("Projects") {
                    ForEach(targets.groups, id: \.id) { group in
                        Button(group.name) { board.move(node, to: .group(group.id), before: nil) }
                            .disabled(here == .group(group.id))
                    }
                }
            }
            if !targets.sections.isEmpty {
                Section("Sections") {
                    ForEach(targets.sections, id: \.id) { section in
                        Button(section.name) {
                            board.move(node, to: .section(section.id), before: board.items(in: .section(section.id)).first)
                        }
                        .disabled(here == .section(section.id))
                    }
                }
            }
            Divider()
            if case .chat(let id) = node, !board.groupPartners(id).isEmpty {
                Menu("New group with") {
                    ForEach(board.groupPartners(id)) { other in
                        Button(untaggedTitle(other)) { board.makeGroup(id, with: other.id) }
                    }
                }
            }
            Button("Out of its project") { board.move(node, to: .top, before: board.items(in: .top).first) }
                .disabled(here == .top)
        }
    }
}

// Stable ids for drawing lists of tree entries.
extension Tree.Entry {
    var key: String {
        switch self {
        case .chat(let chat, _): "chat:" + chat.id
        case .group(let card): "group:" + card.id
        }
    }
}

extension Tree.TopEntry {
    var key: String {
        switch self {
        case .section(let block): "section:" + block.id
        case .entry(let entry): entry.key
        }
    }
}

// Drawn over the whole board while dragging: a line where the thing will go, or an outline on the card or chat it
// will join, and a label following the pointer. All in window space, from the slots the views report.
struct DragOverlay: View {
    @ObservedObject var board: BoardModel

    private var line: CGRect? {
        guard case .place(let container, let before)? = board.drag?.target else { return nil }
        let slots = board.slots.values.filter { $0.container == container && $0.node != board.drag?.node }
        if let before, let slot = board.slots[before] {
            return CGRect(x: slot.frame.minX, y: slot.frame.minY - 2, width: slot.frame.width, height: 3)
        }
        if let last = slots.max(by: { $0.frame.maxY < $1.frame.maxY }) {
            return CGRect(x: last.frame.minX, y: last.frame.maxY, width: last.frame.width, height: 3)
        }
        if case .section(let id) = container, let section = board.slots[.section(id)] {
            return CGRect(x: section.frame.minX + 8, y: section.frame.maxY - 8, width: section.frame.width - 16, height: 3)
        }
        return nil
    }

    private var outline: CGRect? {
        switch board.drag?.target {
        case .into(let id)?: board.slots[.group(id)]?.frame
        case .combine(let id)?: board.slots[.chat(id)]?.frame
        default: nil
        }
    }

    // The slots and the pointer are in window space, measured from the window's top-left. This overlay sits on the
    // board content, which starts below the title bar (the window has a full-size content view), so every rect is
    // shifted by the overlay's own window-space origin before drawing. Without this the line and outline land one
    // title bar too low.
    var body: some View {
        GeometryReader { geometry in
            content(origin: geometry.frame(in: .global).origin)
        }
        .allowsHitTesting(false)
    }

    private func content(origin: CGPoint) -> some View {
        let line = line?.offsetBy(dx: -origin.x, dy: -origin.y)
        let outline = outline?.offsetBy(dx: -origin.x, dy: -origin.y)
        return ZStack(alignment: .topLeading) {
            if let line {
                Capsule().fill(Color.accentColor).frame(width: line.width, height: line.height)
                    .offset(x: line.minX, y: line.minY)
            }
            if let outline {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.accentColor, lineWidth: 2))
                    .frame(width: outline.width, height: outline.height)
                    .offset(x: outline.minX, y: outline.minY)
            }
            if let drag = board.drag {
                HStack(spacing: 6) {
                    if case .combine? = drag.target { Image(systemName: "plus.circle.fill") }
                    if case .into? = drag.target { Image(systemName: "arrow.down.circle.fill") }
                    Text(drag.label).lineLimit(1)
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(.regularMaterial))
                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1))
                .fixedSize()
                .offset(x: drag.point.x - origin.x + 12, y: drag.point.y - origin.y - 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
