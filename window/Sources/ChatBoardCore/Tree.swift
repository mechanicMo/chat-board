import Foundation

// What the board draws, built from the layout and the open chats: sections, project cards and loose chats in the
// person's order, with each card's and section's status rolled up. Closed chats and empty sections are left out.
public enum Tree {
    public enum Entry: Equatable, Sendable {
        case chat(Chat, children: [Chat])
        case group(Card)
    }

    public enum TopEntry: Equatable, Sendable {
        case section(SectionBlock)
        case entry(Entry)
    }

    public struct Card: Equatable, Sendable {
        public let id: String
        public let name: String
        public let chats: [Chat]       // in the group's order, each side session right after its parent at depth 1
        public let counts: [Kind: Int]
        public let lead: Chat?         // the chat that needs the person most; nil when everything is still working
    }

    public struct SectionBlock: Equatable, Sendable {
        public let id: String
        public let name: String
        public let collapsed: Bool
        public let entries: [Entry]
        public let counts: [Kind: Int]
    }

    public struct PageSection: Equatable, Sendable {
        public let title: String
        public let chats: [Chat]
    }

    // Most urgent first: a question, then the person's move, then ready to close, then working.
    static let urgency: [Kind] = [.question, .yourMove, .ready, .working]

    public static func counts(_ chats: [Chat]) -> [Kind: Int] {
        chats.reduce(into: [:]) { $0[$1.kind, default: 0] += 1 }
    }

    // Side sessions of open parents, newest first, keyed by the parent's local id.
    public static func children(of chats: [Chat]) -> [String: [Chat]] {
        let localIds = Set(chats.map(\.localId))
        var map: [String: [Chat]] = [:]
        for chat in chats {
            guard let parent = chat.parentLocalId, parent != chat.localId, localIds.contains(parent) else { continue }
            var child = chat
            child.depth = 1
            map[parent, default: []].append(child)
        }
        return map.mapValues { $0.sorted { $0.activeAt > $1.activeAt } }
    }

    public static func card(_ group: ProjectGroup, chats: [String: Chat], children: [String: [Chat]]) -> Card? {
        var list: [Chat] = []
        for id in group.chats {
            guard var chat = chats[id] else { continue }
            chat.depth = 0
            list.append(chat)
            list += children[chat.localId] ?? []
        }
        guard !list.isEmpty else { return nil }
        let lead = urgency.dropLast().lazy.compactMap { kind in list.first { $0.kind == kind } }.first
        return Card(id: group.id, name: group.name, chats: list, counts: counts(list), lead: lead)
    }

    public static func build(_ layout: BoardLayout, chats: [Chat]) -> [TopEntry] {
        let kids = children(of: chats)
        let childIds = Set(kids.values.flatMap { $0.map(\.id) })
        let roots = Dictionary(chats.filter { !childIds.contains($0.id) }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        func entry(_ node: Node) -> Entry? {
            switch node {
            case .chat(let id):
                guard var chat = roots[id] else { return nil }
                chat.depth = 0
                return .chat(chat, children: kids[chat.localId] ?? [])
            case .group(let id):
                return layout.groups[id].flatMap { card($0, chats: roots, children: kids) }.map(Entry.group)
            case .section:
                return nil
            }
        }

        return layout.top.compactMap { node in
            if case .section(let id) = node {
                guard let section = layout.sections[id] else { return nil }
                let entries = section.items.compactMap(entry)
                guard !entries.isEmpty else { return nil }
                let all = entries.flatMap { entry -> [Chat] in
                    switch entry {
                    case .chat(let chat, let children): [chat] + children
                    case .group(let card): card.chats
                    }
                }
                return .section(SectionBlock(id: id, name: section.name, collapsed: section.collapsed,
                                             entries: entries, counts: counts(all)))
            }
            return entry(node).map(TopEntry.entry)
        }
    }

    // The project page: the card's chats under Needs you, Ready to close and Working, each in the group's order.
    // A side session stays right under its parent.
    public static func page(_ card: Card) -> [PageSection] {
        var blocks: [[Chat]] = []
        for chat in card.chats {
            if chat.depth > 0, !blocks.isEmpty { blocks[blocks.count - 1].append(chat) } else { blocks.append([chat]) }
        }
        let headers: [(String, Set<Kind>)] = [("Needs you", [.question, .yourMove]), ("Ready to close", [.ready]), ("Working", [.working])]
        return headers.compactMap { title, kinds in
            let chats = blocks.filter { kinds.contains($0[0].kind) }.flatMap { $0 }
            return chats.isEmpty ? nil : PageSection(title: title, chats: chats)
        }
    }
}
