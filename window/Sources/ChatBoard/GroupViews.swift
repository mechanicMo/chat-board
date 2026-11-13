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

// Frames of everything that can be dragged, in the list's space, for working out where a drop lands.
struct NodeFrames: PreferenceKey {
    static let defaultValue: [Node: CGRect] = [:]
    static func reduce(value: inout [Node: CGRect], nextValue: () -> [Node: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

func reportHit(_ key: String) -> some View {
    GeometryReader { geometry in
        Color.clear.preference(key: HitFrames.self, value: [key: geometry.frame(in: .global)])
    }
}

func reportNode(_ node: Node) -> some View {
    GeometryReader { geometry in
        Color.clear.preference(key: NodeFrames.self, value: [node: geometry.frame(in: .named("list"))])
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: block.collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Text(block.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer(minLength: 4)
                Text("\(block.counts.values.reduce(0, +))")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            if block.collapsed { StatusBar(counts: block.counts, height: 3) }
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .contentShape(Rectangle())
    }
}

struct GroupCardView: View {
    let card: Tree.Card
    let isUnread: Bool
    let holdsCurrent: Bool
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(card.name)
                    .font(.system(size: 16, weight: isUnread ? .bold : .semibold))
                    .foregroundStyle(Color.primary.opacity(isUnread ? 1 : 0.8))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isUnread, let lead = card.lead { Circle().fill(lead.kind.color).frame(width: 8, height: 8) }
                Text(card.chats.count == 1 ? "1 task" : "\(card.chats.count) tasks")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
            StatusBar(counts: card.counts)
            if let lead = card.lead {
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(lead.kind.color).frame(width: 7, height: 7).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(taskTitle(lead)).font(.system(size: 14)).lineLimit(1)
                        if !lead.line.isEmpty {
                            Text(lead.line).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.primary.opacity(isHovered ? 0.09 : 0.05))
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
            Button("Out of all groups and sections") { board.move(node, to: .top, before: board.items(in: .top).first) }
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
