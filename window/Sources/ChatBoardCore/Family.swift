import Foundation

// A parent chat and the side chats it started, drawn exactly like a project card (Mo, 2026-11-24: "make it look
// exactly how a group looks"): the parent's title in the header with the fold arrow and count, the status bar, and
// inside it the parent's row then its side chats. Folded, it shows the one chat that needs the person most.
public enum Family {
    // From this many side chats up, a family starts folded until the person opens it.
    public static let foldFrom = 3

    public struct Block: Equatable, Sendable {
        public let parent: Chat
        public let children: [Chat]    // every side chat, in drawing order
        public let folded: Bool
        public let counts: [Kind: Int] // the parent's and side chats' statuses, for the card's bar

        // The card the family is drawn as. Its id starts "family:" so its clicks never reach a project card's.
        public var card: Tree.Card {
            let list = [parent] + children
            let lead = Tree.urgency.dropLast().lazy.compactMap { kind in list.first { $0.kind == kind } }.first
            return Tree.Card(id: "family:" + parent.id, name: parent.title, chats: list, counts: counts, lead: lead)
        }
    }

    public static func isFolded(_ parentId: String, childCount: Int, layout: BoardLayout) -> Bool {
        layout.families[parentId] ?? (childCount >= foldFrom)
    }

    public static func block(_ parent: Chat, children: [Chat], layout: BoardLayout) -> Block {
        Block(parent: parent, children: children,
              folded: !children.isEmpty && isFolded(parent.id, childCount: children.count, layout: layout),
              counts: Tree.counts([parent] + children))
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

    // The chat rows a family puts on screen, top to bottom: none when folded, like a folded project card.
    public static func rows(_ block: Block) -> [Chat] { block.folded ? [] : [block.parent] + block.children }
}

extension Moves {
    // Folds a parent's side chats under it, or opens them. The choice is saved, so it overrides the default.
    public static func toggleFamily(_ start: BoardLayout, parent: String, childCount: Int) -> BoardLayout {
        var layout = start
        layout.families[parent] = !Family.isFolded(parent, childCount: childCount, layout: start)
        return layout
    }
}
