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

        public init(id: String, name: String, chats: [Chat], counts: [Kind: Int], lead: Chat?) {
            self.id = id
            self.name = name
            self.chats = chats
            self.counts = counts
            self.lead = lead
        }
    }

    public struct SectionBlock: Equatable, Sendable {
        public let id: String
        public let name: String
        public let collapsed: Bool
        public let entries: [Entry]
        public let counts: [Kind: Int]
    }

    // Most urgent first: a question, then the person's move, then ready to close, then working.
    static let urgency: [Kind] = [.question, .yourMove, .ready, .working]

    public static func counts(_ chats: [Chat]) -> [Kind: Int] {
        chats.reduce(into: [:]) { $0[$1.kind, default: 0] += 1 }
    }

    // Side sessions of open parents, keyed by the local id of their top chat (the first one with no open parent).
    // A side session started from a side session sits under the same top chat, right after its own parent, so a
    // grandchild is never filed under a chat that is itself drawn as a child (it used to vanish that way).
    public static func children(of chats: [Chat]) -> [String: [Chat]] {
        let localIds = Set(chats.map(\.localId))
        var direct: [String: [Chat]] = [:]
        for chat in chats {
            guard let parent = chat.parentLocalId, parent != chat.localId, localIds.contains(parent) else { continue }
            direct[parent, default: []].append(chat)
        }
        let isChild = { (chat: Chat) in chat.parentLocalId.map { $0 != chat.localId && localIds.contains($0) } ?? false }
        var map: [String: [Chat]] = [:]
        var seen = Set<String>()
        func collect(_ localId: String, into list: inout [Chat]) {
            for var child in (direct[localId] ?? []).sorted(by: { $0.activeAt > $1.activeAt }) {
                guard seen.insert(child.id).inserted else { continue }
                child.depth = 1
                list.append(child)
                collect(child.localId, into: &list)
            }
        }
        for top in chats where !isChild(top) {
            var list: [Chat] = []
            collect(top.localId, into: &list)
            if !list.isEmpty { map[top.localId] = list }
        }
        return map
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
}
