import CoreGraphics
import Foundation

// Where a drag lands. The board reports every draggable thing it draws as a slot: its node, the container it sits in,
// and its frame in window space. A section's slot covers its whole panel. From the pointer's position this decides
// whether the dragged thing joins a card, makes a new group with a loose chat, or goes in between two things.
public struct DropSlot: Equatable, Sendable {
    public let node: Node
    public let container: Container
    public let frame: CGRect

    public init(node: Node, container: Container, frame: CGRect) {
        self.node = node
        self.container = container
        self.frame = frame
    }
}

public enum DropTarget: Equatable, Sendable {
    case into(String)                          // join this group
    case combine(String)                       // make a new group with this loose chat
    case place(Container, before: Node?)       // go in this container, before this node (nil: at the end)
}

public enum Drop {
    // The smallest slot under the point: a row inside a section wins over the section's panel.
    public static func pick(at point: CGPoint, slots: [DropSlot]) -> Node? {
        slots.filter { $0.frame.contains(point) }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?
            .node
    }

    public static func target(for node: Node, at point: CGPoint, slots: [DropSlot]) -> DropTarget? {
        if pick(at: point, slots: slots) == node { return nil }
        let others = slots.filter { $0.node != node }
        let mine = slots.first { $0.node == node }

        // The thing after `slot` in its own container, top to bottom.
        func next(after slot: DropSlot) -> Node? {
            others.filter { $0.container == slot.container && $0.frame.minY > slot.frame.minY }
                .min { $0.frame.minY < $1.frame.minY }?.node
        }
        // In a container, before the first thing whose middle is below the pointer.
        func place(in container: Container) -> DropTarget {
            let below = others.filter { $0.container == container && $0.frame.midY > point.y }
                .min { $0.frame.minY < $1.frame.minY }
            return .place(container, before: below?.node)
        }

        if case .section = node { return place(in: .top) }

        guard let under = others.filter({ $0.frame.contains(point) })
                .min(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            // Outside everything: the top level, or on a project page the group being shown.
            if case .group? = mine?.container { return place(in: mine!.container) }
            return place(in: .top)
        }
        if case .section(let id) = under.node { return place(in: .section(id)) }

        let ratio = (point.y - under.frame.minY) / max(under.frame.height, 1)
        let isChat = { if case .chat = node { return true } else { return false } }()
        let inGroup = { if case .group = under.container { return true } else { return false } }()

        if isChat, !inGroup {
            if case .group(let id) = under.node, (0.25...0.75).contains(ratio) { return .into(id) }
            if case .chat(let id) = under.node, (0.3...0.7).contains(ratio) { return .combine(id) }
        }
        // Otherwise it goes beside what's under the pointer: before it from the top part, after it from the rest.
        // The top part is half the row when nothing can be joined, else the band above the join zone.
        let edge: Double
        if !isChat || inGroup { edge = 0.5 } else if case .group = under.node { edge = 0.25 } else { edge = 0.3 }
        if ratio <= edge { return .place(under.container, before: under.node) }
        return .place(under.container, before: next(after: under))
    }

    // Carries a target out on the layout, through the same rules as the menus.
    public static func apply(_ layout: BoardLayout, _ node: Node, _ target: DropTarget, name: (String) -> String) -> BoardLayout {
        switch target {
        case .into(let group):
            return Moves.move(layout, node, to: .group(group), before: nil)
        case .combine(let other):
            guard case .chat(let id) = node else { return layout }
            return Moves.makeGroup(layout, dropping: id, onto: other, name: name(other))
        case .place(let container, let before):
            return Moves.move(layout, node, to: container, before: before)
        }
    }
}
