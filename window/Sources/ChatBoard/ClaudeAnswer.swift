import AppKit
import ChatBoardCore

// Answers a chat's end-of-turn question the way a person does: opens the chat in Claude and presses the box's own
// button. The box is drawn only for the chat that's open, so opening it is part of the click. A reply button sends
// its label as the person's answer and an app button (commit, ...) runs the app's own action, so pressing the real
// button keeps both exactly as Claude does them. When no button with that text shows up, nothing is pressed and the
// board says which buttons it did see.
@MainActor
final class ClaudeAnswer {
    private let title: String
    private let button: AnswerButton
    private let openChat: () -> Void
    private let finish: (String) -> Void
    private var tries = 0

    init(title: String, button: AnswerButton, openChat: @escaping () -> Void, finish: @escaping (String) -> Void) {
        self.title = title
        self.button = button
        self.openChat = openChat
        self.finish = finish
    }

    private var app: AXUIElement? {
        guard let claude = NSRunningApplication.runningApplications(withBundleIdentifier: AppDelegate.claude).first else { return nil }
        let app = AXUIElementCreateApplication(claude.processIdentifier)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return app
    }

    func start() {
        openChat()
        NSRunningApplication.runningApplications(withBundleIdentifier: AppDelegate.claude).first?.activate()
        later(0.6) { self.press() }
    }

    private func later(_ seconds: Double, _ step: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { step() } }
    }

    private func press() {
        guard let app else { return finish("Couldn't answer \(title): Claude isn't running.") }
        let buttons = AX.all(in: app, where: { AX.role($0) == "AXButton" })
        // The box sits at the bottom of the chat, so the last match is the box's, not an older one higher up.
        if let target = buttons.last(where: { buttonMatches(AX.label($0), button) }) {
            return finish(AX.press(target) ? "Answered \(title): \(button.label)." : "Couldn't press \(button.label) in \(title).")
        }
        tries += 1
        guard tries >= 16 else { return later(0.4) { self.press() } }
        var seen: [String] = []
        for label in buttons.map(AX.label) where !label.isEmpty && !seen.contains(label) && !label.hasPrefix("More options") {
            seen.append(label)
        }
        finish("Couldn't find \(button.label) in \(title), so nothing was pressed."
            + (seen.isEmpty ? "" : " Claude shows: \(seen.suffix(12).joined(separator: ", "))."))
    }
}
