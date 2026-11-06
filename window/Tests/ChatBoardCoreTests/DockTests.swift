import CoreGraphics
import Foundation
import Testing
@testable import ChatBoardCore

@Suite struct DockGeometryTests {
    private let geometry = DockGeometry(minPanelWidth: 200)
    // A visible area that doesn't start at zero, like a screen with the Dock on the left.
    private let area = CGRect(x: 70, y: 0, width: 1440, height: 875)

    @Test func panelSitsAtTheLeftEdgeFullHeight() {
        let panel = geometry.panelFrame(width: 380, area: area)
        #expect(panel == CGRect(x: 70, y: 0, width: 380, height: 875))
    }

    @Test func claudeGetsTheRestAndTheTwoFillTheWidth() {
        for width: CGFloat in [200, 333, 500, 720] {
            let panel = geometry.panelFrame(width: width, area: area)
            let claude = geometry.claudeFrame(panelWidth: width, area: area)
            #expect(panel.width + claude.width == area.width)
            #expect(claude.minX == panel.maxX)
            #expect(claude.maxX == area.maxX)
            #expect(claude.minY == area.minY && claude.height == area.height)
        }
    }

    @Test func draggingClaudesEdgeSetsThePanelWidth() {
        let claude = CGRect(x: 70 + 450, y: 0, width: 990, height: 875)
        #expect(geometry.panelWidth(afterClaudeMovedTo: claude, area: area) == 450)
    }

    @Test func panelNeverNarrowerThanItsMinimum() {
        let claude = CGRect(x: 70 + 50, y: 0, width: 1390, height: 875)
        #expect(geometry.panelWidth(afterClaudeMovedTo: claude, area: area) == 200)
        #expect(geometry.clampPanelWidth(10, area: area) == 200)
        #expect(geometry.panelSizeForResize(to: CGSize(width: 5, height: 300), area: area) == CGSize(width: 200, height: 875))
    }

    @Test func claudeIsNeverPushedOffscreen() {
        // Claude dragged far right, or the board stretched wide: the board stops at half the screen.
        let claude = CGRect(x: 70 + 1400, y: 0, width: 40, height: 875)
        let width = geometry.panelWidth(afterClaudeMovedTo: claude, area: area)
        #expect(width == 720)
        let fitted = geometry.claudeFrame(panelWidth: width, area: area)
        #expect(fitted.minX >= area.minX && fitted.maxX <= area.maxX && fitted.width >= area.width / 2)
        #expect(geometry.clampPanelWidth(5000, area: area) == 720)
    }

    @Test func smallDifferencesDoNotMoveTheWindow() {
        let target = geometry.claudeFrame(panelWidth: 300, area: area)
        #expect(!geometry.needsMove(target.offsetBy(dx: 1, dy: 1), to: target))
        #expect(geometry.needsMove(target.offsetBy(dx: 2, dy: 0), to: target))
        #expect(geometry.needsMove(nil, to: target))
        #expect(!geometry.panelNeedsResize(current: 300, wanted: 302))
        #expect(geometry.panelNeedsResize(current: 300, wanted: 303))
    }

    @Test func accessibilityCoordinatesRoundTrip() {
        let frame = CGRect(x: 450, y: 25, width: 990, height: 850)
        let origin = DockGeometry.axOrigin(of: frame, primaryHeight: 900)
        #expect(origin == CGPoint(x: 450, y: 25))
        #expect(DockGeometry.appKitFrame(axOrigin: origin, size: frame.size, primaryHeight: 900) == frame)
    }
}

@Suite struct NoticeTests {
    @MainActor @Test func clearsItselfAfterTheDelay() async throws {
        let notice = Notice(delay: 0.2)
        notice.text = "Archived."
        try await Task.sleep(for: .milliseconds(50))
        #expect(notice.text == "Archived.")
        try await Task.sleep(for: .milliseconds(400))
        #expect(notice.text == nil)
    }

    @MainActor @Test func aNewerNoticeIsNotClearedByTheOldTimer() async throws {
        let notice = Notice(delay: 1.0)
        notice.text = "first"
        try await Task.sleep(for: .milliseconds(500))
        notice.text = "second"
        try await Task.sleep(for: .milliseconds(700))  // 1.2 s: the first timer has fired, the second hasn't
        #expect(notice.text == "second")
        try await Task.sleep(for: .milliseconds(800))  // 2.0 s: the second has fired
        #expect(notice.text == nil)
    }

    @MainActor @Test func defaultsToTenSeconds() {
        #expect(Notice().delay == 10)
    }
}
