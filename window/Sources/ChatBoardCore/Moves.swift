import Foundation

// What the person does to the layout by dragging or through a right-click menu. Anything they place by hand is
// marked so auto-filing leaves it alone afterwards. A move that isn't allowed returns the layout unchanged.
public enum Moves {
    public static func move(_ start: BoardLayout, _ node: Node, to destination: Container, before: Node?) -> BoardLayout {
        var layout = start
        switch (node, destination) {
        case (.section, .top), (.group, .top), (.group, .section), (.chat, _): break
        default: return start
        }
        switch destination {
        case .top: break
        case .section(let id): guard layout.sections[id] != nil else { return start }
        case .group(let id): guard layout.groups[id] != nil else { return start }
        }
        if before == node { return start }
        layout.remove(node)
        layout.insert(node, into: destination, before: before)
        switch node {
        case .chat(let id): layout.manual.insert(id)
        case .group(let id): layout.groups[id]?.isManual = true
        case .section: break
        }
        if case .group(let id) = destination { layout.groups[id]?.isManual = true }
        return layout
    }

    // Dropping one loose chat onto another: both go into a new group where the target was.
    public static func makeGroup(_ start: BoardLayout, dropping: String, onto: String, name: String) -> BoardLayout {
        guard dropping != onto, let place = start.container(of: .chat(onto)) else { return start }
        if case .group = place { return start }
        var layout = start
        let id = "g-" + UUID().uuidString.lowercased()
        layout.insert(.group(id), into: place, before: .chat(onto))
        layout.remove(.chat(onto))
        layout.remove(.chat(dropping))
        layout.groups[id] = ProjectGroup(id: id, name: name, chats: [onto, dropping], isManual: true)
        layout.manual.formUnion([onto, dropping])
        return layout
    }

    public static func rename(_ start: BoardLayout, group: String, to name: String) -> BoardLayout {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, start.groups[group] != nil else { return start }
        var layout = start
        layout.groups[group]!.name = trimmed
        layout.groups[group]!.isManual = true
        return layout
    }

    // Breaks a group up where it stands. Its chats count as placed by hand, so they don't regroup on their own.
    public static func ungroup(_ start: BoardLayout, _ group: String) -> BoardLayout {
        guard let chats = start.groups[group]?.chats, let place = start.container(of: .group(group)) else { return start }
        var layout = start
        for chat in chats { layout.insert(.chat(chat), into: place, before: .group(group)) }
        layout.remove(.group(group))
        layout.groups[group] = nil
        layout.manual.formUnion(chats)
        return layout
    }

    public static func toggleCollapsed(_ start: BoardLayout, section: String) -> BoardLayout {
        guard start.sections[section] != nil else { return start }
        var layout = start
        layout.sections[section]!.collapsed.toggle()
        return layout
    }
}
