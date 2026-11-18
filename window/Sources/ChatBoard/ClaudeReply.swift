import AppKit
import ChatBoardCore

// Sends an orange chat's go-ahead the way a person does: opens the chat in Claude, types the reply into its message
// box and presses Return. It sends a message as the person, so every step checks state before the next one, and
// any check that fails stops with nothing sent:
// - the chat still offers this exact go-ahead (nothing written to it since the board drew the button)
// - Claude has that chat in front (its record carries the newest lastFocusedAt), not the one that was open before
// - the message box is empty, so a draft the person was writing is never touched
// - Claude is the app in front right before every keystroke, since keystrokes go to whichever app is in front
// - the box holds exactly the reply after typing; if not, nothing more is pressed (no clearing: a wrong guess about
//   focus would delete the person's own text) and the notice says what may be left in the box
// It only reports "Sent" once the chat's own row shows a new message from the person.
@MainActor
final class ClaudeReply {
    private let title: String
    private let reply: String
    private let openChat: () -> Void
    private let isStillOffered: () -> Bool
    private let isOpen: () -> Bool
    private let wasSent: (Double) -> Bool
    private let finish: (String) -> Void
    private var tries = 0
    private var sentAt: Double = 0

    init(title: String, reply: String, openChat: @escaping () -> Void, isStillOffered: @escaping () -> Bool,
         isOpen: @escaping () -> Bool, wasSent: @escaping (Double) -> Bool, finish: @escaping (String) -> Void) {
        self.title = title
        self.reply = reply
        self.openChat = openChat
        self.isStillOffered = isStillOffered
        self.isOpen = isOpen
        self.wasSent = wasSent
        self.finish = finish
    }

    private var app: AXUIElement? {
        guard let claude = NSRunningApplication.runningApplications(withBundleIdentifier: AppDelegate.claude).first else { return nil }
        let app = AXUIElementCreateApplication(claude.processIdentifier)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return app
    }

    func start() {
        guard isStillOffered() else { return finish("\(title) changed since the board drew that button, so nothing was sent.") }
        openChat()
        NSRunningApplication.runningApplications(withBundleIdentifier: AppDelegate.claude).first?.activate()
        later(0.4) { self.waitForChat() }
    }

    private var claudeInFront: Bool { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == AppDelegate.claude }

    private func later(_ seconds: Double, _ step: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { step() } }
    }

    private func waitForChat() {
        if isOpen() {
            tries = 0
            return later(0.3) { self.type() }
        }
        tries += 1
        guard tries < 20 else { return finish("Claude didn't open \(title), so nothing was sent.") }
        later(0.3) { self.waitForChat() }
    }

    // Claude's message box: a text area titled "Prompt" (seen in Claude's window, 2026-11-17).
    private func promptBox(_ app: AXUIElement) -> AXUIElement? {
        AX.first(in: app, where: { AX.role($0) == "AXTextArea" && (AX.title($0) == "Prompt" || AX.label($0) == "Prompt") })
    }

    private func type() {
        guard let app else { return finish("Couldn't send to \(title): Claude isn't running.") }
        guard let box = promptBox(app) else {
            tries += 1
            guard tries >= 10 else { return later(0.3) { self.type() } }
            return finish("Couldn't find the message box in \(title), so nothing was sent.")
        }
        // Checked again here: the person may have answered in Claude while the chat was opening.
        guard isStillOffered(), isOpen() else { return finish("\(title) changed while it opened, so nothing was sent.") }
        let before = AX.text(box, kAXValueAttribute).trimmingCharacters(in: .whitespacesAndNewlines)
        guard before.isEmpty else { return finish("\(title) has a draft in its message box, so nothing was sent.") }
        AXUIElementSetAttributeValue(box, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard claudeInFront else { return finish("Another app came to the front, so nothing was typed or sent to \(title).") }
        // Typed as keystrokes, not set as a value: Claude's page only notices text that arrives as typing.
        Keys.type(reply)
        later(0.25) { self.check(box) }
    }

    private func check(_ box: AXUIElement) {
        let typed = AX.text(box, kAXValueAttribute).trimmingCharacters(in: .whitespacesAndNewlines)
        guard claudeInFront else {
            return finish("Another app came to the front while typing, so nothing was sent to \(title). Check that app and \(title)'s box for \"\(reply)\".")
        }
        guard typed == reply, isOpen() else {
            return finish("The reply didn't type cleanly into \(title), so nothing was sent. Its message box may still hold part of \"\(reply)\".")
        }
        sentAt = Date().timeIntervalSince1970 * 1000
        Keys.press(36)                                // Return
        tries = 0
        later(1) { self.confirm() }
    }

    // The chat's row records the person's message when its turn starts; the board polls it every few seconds.
    private func confirm() {
        if wasSent(sentAt) { return finish("Sent \"\(reply)\" to \(title).") }
        tries += 1
        guard tries >= 12 else { return later(1) { self.confirm() } }
        finish("Pressed send in \(title), but the chat hasn't started on it yet. Check it in Claude.")
    }
}
