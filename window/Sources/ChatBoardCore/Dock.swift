import CoreGraphics

// Where the board and Claude's window go. The board sits at the left edge of the screen's visible area at
// full height, and Claude fills the rest, so the two always add up to the visible width.
// All rects are in AppKit's coordinates (origin bottom-left of the main screen).
public struct DockGeometry: Sendable {
    public var minPanelWidth: CGFloat = 200
    // Closer than this and a window counts as already in place, so tiny rounding never starts a resize loop.
    public var tolerance: CGFloat = 2

    public init(minPanelWidth: CGFloat = 200) { self.minPanelWidth = minPanelWidth }

    // Never narrower than the minimum, never wider than half the screen, so Claude keeps at least half.
    public func clampPanelWidth(_ width: CGFloat, area: CGRect) -> CGFloat {
        min(max(width, minPanelWidth), area.width / 2)
    }

    public func panelFrame(width: CGFloat, area: CGRect) -> CGRect {
        CGRect(x: area.minX, y: area.minY, width: width, height: area.height)
    }

    // The board only grows or shrinks from its right edge and always stays full height.
    public func panelSizeForResize(to size: CGSize, area: CGRect) -> CGSize {
        CGSize(width: clampPanelWidth(size.width, area: area), height: area.height)
    }

    public func claudeFrame(panelWidth: CGFloat, area: CGRect) -> CGRect {
        CGRect(x: area.minX + panelWidth, y: area.minY, width: area.width - panelWidth, height: area.height)
    }

    // When the person drags Claude's left edge, the board takes whatever width is left of it.
    public func panelWidth(afterClaudeMovedTo claude: CGRect, area: CGRect) -> CGFloat {
        clampPanelWidth(claude.minX - area.minX, area: area)
    }

    public func needsMove(_ current: CGRect?, to target: CGRect) -> Bool {
        guard let current else { return true }
        return abs(current.minX - target.minX) >= tolerance || abs(current.width - target.width) >= tolerance
            || abs(current.minY - target.minY) >= tolerance || abs(current.height - target.height) >= tolerance
    }

    public func panelNeedsResize(current: CGFloat, wanted: CGFloat) -> Bool { abs(wanted - current) > tolerance }

    // The Accessibility API measures from the top-left of the main screen; AppKit from the bottom-left.
    public static func appKitFrame(axOrigin: CGPoint, size: CGSize, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: axOrigin.x, y: primaryHeight - axOrigin.y - size.height, width: size.width, height: size.height)
    }

    public static func axOrigin(of frame: CGRect, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: frame.minX, y: primaryHeight - frame.maxY)
    }
}
