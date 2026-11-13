import Foundation

// BoardLayout: where everything sits on the board: sections (one per title tag), project groups, and loose chats, each in the
// person's order. Saved as ~/.claude/chat-hud/layout.json and written only by the app. Ids of chats that are closed
// or archived stay put, so a chat that comes back returns to its spot. Side sessions are never listed; they are drawn
// under their parent wherever it sits.
public enum Node: Hashable, Codable, Sendable {
    case section(String), group(String), chat(String)
}

public enum Container: Hashable, Sendable {
    case top, section(String), group(String)
}

public struct TagSection: Codable, Equatable, Sendable {
    public var id: String       // the tag's key, e.g. "work"
    public var name: String     // the tag as first written, e.g. "Work"
    public var items: [Node]    // groups and loose chats
    public var collapsed: Bool

    public init(id: String, name: String, items: [Node] = [], collapsed: Bool = false) {
        self.id = id
        self.name = name
        self.items = items
        self.collapsed = collapsed
    }
}

public struct ProjectGroup: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var chats: [String]
    // Made, renamed or added to by hand. Auto groups dissolve below two chats; manual ones stay until empty.
    public var isManual: Bool

    public init(id: String, name: String, chats: [String] = [], isManual: Bool = false) {
        self.id = id
        self.name = name
        self.chats = chats
        self.isManual = isManual
    }
}

public struct BoardLayout: Codable, Equatable, Sendable {
    public var top: [Node]
    public var sections: [String: TagSection]
    public var groups: [String: ProjectGroup]
    // Chats the person moved by hand. Auto-filing never moves these again.
    public var manual: Set<String>
    // The title each chat was last auto-filed under, so a rename can re-file it.
    public var filedAs: [String: String]

    public init(top: [Node] = [], sections: [String: TagSection] = [:], groups: [String: ProjectGroup] = [:],
                manual: Set<String> = [], filedAs: [String: String] = [:]) {
        self.top = top
        self.sections = sections
        self.groups = groups
        self.manual = manual
        self.filedAs = filedAs
    }

    public func items(in container: Container) -> [Node] {
        switch container {
        case .top: top
        case .section(let id): sections[id]?.items ?? []
        case .group(let id): groups[id]?.chats.map { .chat($0) } ?? []
        }
    }

    public func container(of node: Node) -> Container? {
        if top.contains(node) { return .top }
        for (id, section) in sections where section.items.contains(node) { return .section(id) }
        if case .chat(let chat) = node {
            for (id, group) in groups where group.chats.contains(chat) { return .group(id) }
        }
        return nil
    }

    // Every chat id the layout has placed, wherever it is.
    public var placedChats: Set<String> {
        var ids = Set<String>()
        for node in top + sections.values.flatMap(\.items) { if case .chat(let id) = node { ids.insert(id) } }
        for group in groups.values { ids.formUnion(group.chats) }
        return ids
    }

    // Takes a node out of wherever it is. Removing a section or group drops only the reference, not its contents.
    public mutating func remove(_ node: Node) {
        top.removeAll { $0 == node }
        for id in sections.keys { sections[id]!.items.removeAll { $0 == node } }
        if case .chat(let chat) = node {
            for id in groups.keys { groups[id]!.chats.removeAll { $0 == chat } }
        }
    }

    // Puts a node into a container before `before`, or at `index` (default the end) when `before` isn't there.
    public mutating func insert(_ node: Node, into container: Container, before: Node? = nil, at index: Int? = nil) {
        func position(_ list: [Node]) -> Int {
            if let before, let found = list.firstIndex(of: before) { return found }
            return min(index ?? list.count, list.count)
        }
        switch container {
        case .top:
            top.insert(node, at: position(top))
        case .section(let id):
            guard sections[id] != nil else { return }
            sections[id]!.items.insert(node, at: position(sections[id]!.items))
        case .group(let id):
            guard groups[id] != nil, case .chat(let chat) = node else { return }
            let list = groups[id]!.chats.map { Node.chat($0) }
            groups[id]!.chats.insert(chat, at: position(list))
        }
    }
}
