import Foundation

// How the list is ordered and marked. The window's model calls these; they hold no state of their own.
public enum Board {
    // The person's order, with each side session kept right under its parent, indented.
    // Chats the person hasn't placed yet go on top, newest first. A child whose parent is archived or gone
    // stands on its own.
    public static func arrange(_ list: [Chat], order: [String]) -> [Chat] {
        let placed = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let sorted = { (chats: [Chat]) -> [Chat] in
            let fresh = chats.filter { placed[$0.id] == nil }.sorted { $0.activeAt > $1.activeAt }
            let known = chats.filter { placed[$0.id] != nil }.sorted { placed[$0.id]! < placed[$1.id]! }
            return fresh + known
        }
        let present = Set(list.map(\.localId))
        let isChild = { (chat: Chat) in chat.parentLocalId.map { present.contains($0) && $0 != chat.localId } ?? false }
        var result: [Chat] = []
        for parent in sorted(list.filter { !isChild($0) }) {
            result.append(parent)
            for var child in sorted(list.filter { isChild($0) && $0.parentLocalId == parent.localId }) {
                child.depth = 1
                result.append(child)
            }
        }
        return result
    }

    // The order to save once the board has shown chats it never placed, so a chat keeps its spot after that
    // and only a drag moves it. Without this, an unplaced chat jumped to the top each time it got a message.
    // Ids no longer on the board stay in the saved order, so a chat that comes back keeps its spot. Nil when
    // every chat on the board is already placed.
    public static func settledOrder(_ arranged: [Chat], saved: [String]) -> [String]? {
        let known = Set(saved)
        guard arranged.contains(where: { !known.contains($0.id) }) else { return nil }
        let shown = arranged.map(\.id)
        let showing = Set(shown)
        return shown + saved.filter { !showing.contains($0) }
    }

    // Moves a whole group, the chat plus its side sessions, to just before another group (or to the end).
    // A side session never leaves its parent. Nil when nothing moves.
    public static func moveGroup(_ chats: [Chat], _ id: String, before target: String?) -> [Chat]? {
        let groups = chats.reduce(into: [[Chat]]()) { groups, chat in
            if chat.depth == 0 || groups.isEmpty { groups.append([chat]) } else { groups[groups.count - 1].append(chat) }
        }
        guard id != target, let moving = groups.firstIndex(where: { $0.first?.id == id }) else { return nil }
        var reordered = groups
        let group = reordered.remove(at: moving)
        let at = target.flatMap { target in reordered.firstIndex { $0.first?.id == target } } ?? reordered.count
        reordered.insert(group, at: at)
        return reordered.flatMap { $0 }
    }

    // The chat in front of the person. One just clicked here counts at once, for up to 15 seconds,
    // until the app's own record catches up.
    public static func currentId(_ chats: [Chat], clicked: (id: String, at: Date)?, now: Date = Date()) -> String? {
        let recorded = chats.max { $0.focusedAt < $1.focusedAt }?.id
        guard let clicked, now.timeIntervalSince(clicked.at) < 15, clicked.id != recorded else { return recorded }
        return clicked.id
    }

    // Unread: the chat finished a turn after the person last looked at it. The chat in front of them is
    // always read, and a working chat has nothing new to read yet. `seenAt` is when it was clicked here, in ms.
    public static func isUnread(_ chat: Chat, currentId: String?, seenAt: Double?) -> Bool {
        guard chat.kind != .working, chat.id != currentId else { return false }
        return chat.finishedAt > max(chat.viewedAt, seenAt ?? 0)
    }
}
