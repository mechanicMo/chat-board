import Foundation

// A parent chat and the side chats it started, in a card that looks like a project card but is led by the parent
// itself (Mo, 2026-11-24): the parent's row is always fully shown, with a fold arrow beside it, and its side chats
// show under it, smaller and set in, or fold away to a status bar of them.
public enum Family {
    // From this many side chats up, a family starts folded until the person opens it.
    public static let foldFrom = 3

    public struct Block: Equatable, Sendable {
        public let parent: Chat
        public let children: [Chat]    // every side chat, in drawing order
        public let folded: Bool
        public let counts: [Kind: Int] // the side chats' statuses, for the bar a folded family shows
    }

    public static func isFolded(_ parentId: String, childCount: Int, layout: BoardLayout) -> Bool {
        layout.families[parentId] ?? (childCount >= foldFrom)
    }

    public static func block(_ parent: Chat, children: [Chat], layout: BoardLayout) -> Block {
        Block(parent: parent, children: children,
              folded: !children.isEmpty && isFolded(parent.id, childCount: children.count, layout: layout),
              counts: Tree.counts(children))
    }

    // A card's chats come flat, each side chat right after its top chat at depth 1. This splits them back into
    // families, one per top chat; a top chat with no side chats is a family of one.
    public static func split(_ list: [Chat], layout: BoardLayout) -> [Block] {
        var blocks: [(Chat, [Chat])] = []
        for chat in list {
            if chat.depth > 0, !blocks.isEmpty { blocks[blocks.count - 1].1.append(chat) }
            else { blocks.append((chat, [])) }
        }
        return blocks.map { block($0.0, children: $0.1, layout: layout) }
    }

    // The chat rows a family puts on screen, top to bottom: the parent always, its side chats unless folded.
    public static func rows(_ block: Block) -> [Chat] { block.folded ? [block.parent] : [block.parent] + block.children }
}

extension Moves {
    // Folds a parent's side chats under it, or opens them. The choice is saved, so it overrides the default.
    public static func toggleFamily(_ start: BoardLayout, parent: String, childCount: Int) -> BoardLayout {
        var layout = start
        layout.families[parent] = !Family.isFolded(parent, childCount: childCount, layout: start)
        return layout
    }
}
