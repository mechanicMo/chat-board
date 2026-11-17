import AppKit

// Renames a chat the way a person does in Claude: "More options for <title>", then Rename, then type the name.
// Only used for a chat whose name the person typed in Claude's own sidebar: Claude won't let a mod replace that kind
// of name without a card a mod can't show. Every other chat is renamed through a chat's mod (see BoardModel).
// Like ClaudeArchive, it opens the sidebar only when the chat isn't on screen, and closes it again after.
// If the menu has no Rename item, or no text field appears, it presses nothing more and says what it saw.
@MainActor
final class ClaudeRename {
    private let title: String
    private let name: String
    private let openChat: () -> Void
    private let finish: (String) -> Void
    private var openedSidebar = false
    private var openedChat = false
    private var tries = 0

    init(title: String, name: String, openChat: @escaping () -> Void, finish: @escaping (String) -> Void) {
        self.title = title
        self.name = name
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
        NSRunningApplication.runningApplications(withBundleIdentifier: AppDelegate.claude).first?.activate()
        findButton()
    }

    private func later(_ seconds: Double, _ step: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { step() } }
    }

    private func end(_ message: String) {
        if openedSidebar, let app, let toggle = AX.first(in: app, where: { AX.isSidebarToggle($0) }) {
            AX.press(toggle)
        }
        finish(message)
    }

    private func findButton() {
        guard let app else { return end("Couldn't rename \(title): Claude isn't running.") }
        let label = "More options for " + title
        if let button = AX.first(in: app, where: { AX.role($0) == "AXPopUpButton" && AX.title($0) == label }) {
            AX.press(button)
            tries = 0
            return later(0.3) { self.findRename() }
        }
        tries += 1
        if !openedSidebar, let toggle = AX.first(in: app, where: { AX.isSidebarToggle($0) && AX.title($0).lowercased().contains("show") }) {
            openedSidebar = true
            AX.press(toggle)
            return later(0.4) { self.findButton() }
        }
        if !openedChat, tries >= 10 {
            openedChat = true
            openChat()
        }
        guard tries < 20 else { return end("Couldn't rename \(title): Claude doesn't show that chat.") }
        later(0.3) { self.findButton() }
    }

    private func findRename() {
        guard let app else { return end("Couldn't rename \(title): Claude isn't running.") }
        let items = AX.all(in: app, where: { AX.isMenuItem($0) })
        if let rename = items.first(where: { AX.label($0).lowercased().hasPrefix("rename") }) {
            AX.press(rename)
            tries = 0
            return later(0.3) { self.findField() }
        }
        tries += 1
        guard tries >= 7 else { return later(0.3) { self.findRename() } }
        AX.cancelMenus(in: app)
        let seen = items.map(AX.label).filter { !$0.isEmpty }
        end(seen.isEmpty
            ? "Couldn't rename \(title): Claude's menu didn't open."
            : "Couldn't rename \(title): Claude's menu has no Rename. It shows: \(seen.joined(separator: ", ")).")
    }

    // The field Rename opened: the focused text field, or one holding the old name.
    private func findField() {
        guard let app else { return end("Couldn't rename \(title): Claude isn't running.") }
        let isText = { (element: AXUIElement) in ["AXTextField", "AXTextArea"].contains(AX.role(element)) }
        var field: AXUIElement?
        if let focused = AX.value(app, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() {
            let element = focused as! AXUIElement
            if isText(element) { field = element }
        }
        if field == nil {
            field = AX.first(in: app, where: { isText($0) && AX.text($0, kAXValueAttribute) == title })
        }
        guard let field else {
            tries += 1
            guard tries >= 10 else { return later(0.3) { self.findField() } }
            Keys.press(53)
            return end("Couldn't rename \(title): Claude's rename field didn't appear.")
        }
        AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        // Typed as keystrokes, not set as a value: Claude's page only notices text that arrives as typing.
        Keys.press(0, flags: .maskCommand)   // Cmd+A
        Keys.type(name)
        later(0.15) {
            Keys.press(36)                    // Return
            self.later(0.4) { self.end("Renamed \(self.title) to \(self.name).") }
        }
    }
}

// Keystrokes posted to whatever app is in front (Claude, which the rename brought forward).
@MainActor
enum Keys {
    static func press(_ key: CGKeyCode, flags: CGEventFlags = []) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    static func type(_ text: String) {
        let units = Array(text.utf16)
        var start = 0
        while start < units.count {
            let chunk = Array(units[start..<min(start + 16, units.count)])
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
                event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event?.post(tap: .cghidEventTap)
            }
            start += 16
        }
    }
}
