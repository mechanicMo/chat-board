import Foundation

// A parent chat and the side chats it started, drawn as one group: the parent's row is the header, and under it a
// strip with a fold arrow, the side chat count and their status bar (Mo, 2026-11-24). Folded, the side chats are
// hidden except any that need the person (a question or their move), so folding never hides something to act on.
public enum Family {
    // From this many side chats up, a family starts folded until the person opens it.
    public static let foldFrom = 3

    public struct Block: Equatable, Sendable {
        public let parent: Chat
        public let children: [Chat]    // every side chat, in drawing order
        public let folded: Bool
        public let counts: [Kind: Int] // the side chats' statuses, for the strip's bar

        // The side chats drawn under the strip: all of them when open, only those that need the person when folded.
        public var shown: [Chat] { folded ? children.filter(Family.needsPerson) : children }
    }

    static func needsPerson(_ chat: Chat) -> Bool { chat.kind == .question || chat.kind == .yourMove }

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

    // The rows a family puts on screen, top to bottom.
    public static func rows(_ block: Block) -> [Chat] { [block.parent] + block.shown }
}

extension Moves {
    // Folds a parent's side chats under it, or opens them. The choice is saved, so it overrides the default.
    public static func toggleFamily(_ start: BoardLayout, parent: String, childCount: Int) -> BoardLayout {
        var layout = start
        layout.families[parent] = !Family.isFolded(parent, childCount: childCount, layout: start)
        return layout
    }
}
