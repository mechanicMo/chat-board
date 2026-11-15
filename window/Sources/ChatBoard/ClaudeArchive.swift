import AppKit

// Archives a chat the way a person does: Claude's "More options for <title>" button, then Archive in its menu.
// The app refuses an archive a plugin asks for in a chat in auto mode, so the board can't go through a chat;
// it goes through Claude's own window instead. Every chat row in the sidebar has that button, and so does the
// open chat's header, so the sidebar is opened only when the chat isn't on screen, and closed again after.
// If the menu has no Archive item nothing is pressed: the menu is closed and the board says what it saw.
@MainActor
final class ClaudeArchive {
    private let title: String
    private let openChat: () -> Void
    private let finish: (String) -> Void
    private var openedSidebar = false
    private var openedChat = false
    private var tries = 0

    init(title: String, openChat: @escaping () -> Void, finish: @escaping (String) -> Void) {
        self.title = title
        self.openChat = openChat
        self.finish = finish
    }

    private var app: AXUIElement? {
        guard let claude = NSRunningApplication.runningApplications(withBundleIdentifier: AppDelegate.claude).first else { return nil }
        let app = AXUIElementCreateApplication(claude.processIdentifier)
        // Claude is an Electron app: its page only shows up to accessibility once asked.
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

    // The chat's own "More options" button: in the sidebar, or in the header once the chat is open.
    private func findButton() {
        guard let app else { return end("Couldn't archive \(title): Claude isn't running.") }
        let name = "More options for " + title
        if let button = AX.first(in: app, where: { AX.role($0) == "AXPopUpButton" && AX.title($0) == name }) {
            AX.press(button)
            tries = 0
            return later(0.3) { self.findArchive() }
        }
        tries += 1
        if !openedSidebar, let toggle = AX.first(in: app, where: { AX.isSidebarToggle($0) && AX.title($0).lowercased().contains("show") }) {
            openedSidebar = true
            AX.press(toggle)
            return later(0.4) { self.findButton() }
        }
        // The sidebar's rows can take a moment to appear. Only after about 3 seconds without the row is the chat
        // opened, so its header's button can be used instead (that switches the chat, so it is the last resort).
        if !openedChat, tries >= 10 {
            openedChat = true
            openChat()
        }
        guard tries < 20 else { return end("Couldn't archive \(title): Claude doesn't show that chat.") }
        later(0.3) { self.findButton() }
    }

    // Archive in the menu that just opened. Waits a moment for the menu to appear.
    private func findArchive() {
        guard let app else { return end("Couldn't archive \(title): Claude isn't running.") }
        let items = AX.all(in: app, where: { AX.isMenuItem($0) })
        if let archive = items.first(where: { AX.label($0).lowercased().hasPrefix("archive") }) {
            AX.press(archive)
            return later(0.5) { self.confirm() }
        }
        tries += 1
        guard tries >= 7 else { return later(0.3) { self.findArchive() } }
        AX.cancelMenus(in: app)
        let seen = items.map(AX.label).filter { !$0.isEmpty }
        end(seen.isEmpty
            ? "Couldn't archive \(title): Claude's menu didn't open."
            : "Couldn't archive \(title): Claude's menu has no Archive. It shows: \(seen.joined(separator: ", ")).")
    }

    // Some versions ask "Archive this session?" first: press its Archive button when there is one.
    private func confirm() {
        if let app, let button = AX.first(in: app, where: {
            AX.role($0) == "AXButton" && AX.label($0).lowercased() == "archive" && !AX.title($0).hasPrefix("More options")
        }) {
            AX.press(button)
        }
        end("Archived \(title).")
    }
}

// Small helpers over the accessibility tree of Claude's windows.
@MainActor
enum AX {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        return result
    }

    static func text(_ element: AXUIElement, _ attribute: String) -> String { (value(element, attribute) as? String) ?? "" }
    static func role(_ element: AXUIElement) -> String { text(element, kAXRoleAttribute) }
    static func title(_ element: AXUIElement) -> String { text(element, kAXTitleAttribute) }
    static func label(_ element: AXUIElement) -> String {
        let title = title(element)
        return title.isEmpty ? text(element, kAXDescriptionAttribute) : title
    }

    static func isMenuItem(_ element: AXUIElement) -> Bool {
        role(element) == "AXMenuItem" || text(element, "AXRoleDescription").lowercased() == "menu item"
    }

    // The button that shows and hides the sidebar: Cmd+B, titled "Show sidebar" or "Hide sidebar".
    static func isSidebarToggle(_ element: AXUIElement) -> Bool {
        role(element) == "AXButton" && (text(element, "AXKeyShortcutsValue").lowercased() == "meta+b" || title(element).lowercased().hasSuffix(" sidebar"))
    }

    @discardableResult
    static func press(_ element: AXUIElement) -> Bool { AXUIElementPerformAction(element, kAXPressAction as CFString) == .success }

    // Claude's windows only: the menu bar is left out, so its own Archive items are never matched.
    private static func roots(_ app: AXUIElement) -> [AXUIElement] { (value(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] }

    static func first(in app: AXUIElement, where match: (AXUIElement) -> Bool) -> AXUIElement? {
        func search(_ element: AXUIElement, _ depth: Int) -> AXUIElement? {
            if match(element) { return element }
            guard depth < 80 else { return nil }
            for child in (value(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
                if let found = search(child, depth + 1) { return found }
            }
            return nil
        }
        for root in roots(app) { if let found = search(root, 0) { return found } }
        return nil
    }

    static func all(in app: AXUIElement, where match: (AXUIElement) -> Bool) -> [AXUIElement] {
        var found: [AXUIElement] = []
        func search(_ element: AXUIElement, _ depth: Int) {
            if match(element) { found.append(element) }
            guard depth < 80 else { return }
            for child in (value(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { search(child, depth + 1) }
        }
        for root in roots(app) { search(root, 0) }
        return found
    }

    // Closes any open menu without choosing from it.
    static func cancelMenus(in app: AXUIElement) {
        for menu in all(in: app, where: { role($0) == "AXMenu" || text($0, "AXRoleDescription").lowercased() == "menu" }) {
            AXUIElementPerformAction(menu, kAXCancelAction as CFString)
        }
        let escape = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)
        escape?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
    }
}
