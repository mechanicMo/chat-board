// Stand-in Claude: a tiny window the end-to-end tests run Chat Board beside, so the tests never touch real chats.
// It has the parts of Claude that Chat Board reaches for: a window to dock beside, a message box, a microphone
// button and an Edit > Find menu item on Cmd+F. Everything that happens to it goes to STANDIN_LOG, one JSON
// object per line, and the tests read that file to see where keystrokes and clicks landed.
//   STANDIN_LOG=<file>   where to write (required)
//   STANDIN_NO_MIC=1     leave the microphone button out, to test that Cmd+D then passes through
//   STANDIN_CHATS=<json> chat titles (a JSON array) that get a "More options for <title>" button with an Archive
//                        item, the way Claude's sidebar rows do; pressing Archive logs "archive" with the title

import AppKit

let logPath = ProcessInfo.processInfo.environment["STANDIN_LOG"] ?? "/dev/null"

func log(_ event: String, _ value: String = "") {
    let object: [String: Any] = ["at": Date().timeIntervalSince1970 * 1000, "event": event, "value": value]
    guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
    data.append(0x0A)
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: data)
    }
}

final class StandIn: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Quit Stand-in", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        // Cmd+F with no other modifier: the same shortcut Chat Board looks for in Claude's menus.
        edit.addItem(withTitle: "Find…", action: #selector(find), keyEquivalent: "f").target = self
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        menu.addItem(editItem)
        NSApp.mainMenu = menu

        window = NSWindow(contentRect: NSRect(x: 500, y: 200, width: 800, height: 600),
                          styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        window.title = "Stand-in Claude"
        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 20, y: 60, width: 760, height: 520)
        scroll.autoresizingMask = [.width, .height]
        let box = scroll.documentView as! NSTextView
        box.setAccessibilityLabel("Message box")
        content.addSubview(scroll)
        if ProcessInfo.processInfo.environment["STANDIN_NO_MIC"] == nil {
            let mic = NSButton(title: "Mic", target: self, action: #selector(microphone))
            mic.frame = NSRect(x: 20, y: 15, width: 90, height: 32)
            // Chat Board matches a button whose label mentions dictation, like Claude's.
            mic.setAccessibilityLabel("Start dictation")
            content.addSubview(mic)
        }
        let chats = ProcessInfo.processInfo.environment["STANDIN_CHATS"]
            .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String] } ?? []
        for (index, title) in chats.enumerated() {
            let button = OptionsButton(chat: title, menuHost: content)
            button.frame = NSRect(x: 130 + index * 40, y: 15, width: 32, height: 32)
            content.addSubview(button)
        }
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(box)
        NSApp.activate()

        // Every key that reaches this app, so the tests can tell a shortcut that passed through from one the
        // board took, and see typed text land.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            var name = event.charactersIgnoringModifiers ?? ""
            if event.keyCode == 53 { name = "escape" }
            if flags.contains(.command) { name = "cmd+" + name }
            log("key", name)
            return event
        }
        log("ready", ProcessInfo.processInfo.environment["STANDIN_NO_MIC"] == nil ? "mic" : "no-mic")
    }

    @objc func find() { log("find") }
    @objc func microphone() { log("mic") }
}

// Claude's per-chat "More options" button. Claude's menu is part of its page, not a native menu, so this one is a
// plain view too: pressing the button shows an Archive item beside it, and pressing that logs the archive.
final class OptionsButton: NSButton {
    let chat: String
    weak var menuHost: NSView?
    var item: MenuItemButton?

    init(chat: String, menuHost: NSView) {
        self.chat = chat
        self.menuHost = menuHost
        super.init(frame: .zero)
        title = "…"
        target = self
        action = #selector(showMenu)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func accessibilityRole() -> NSAccessibility.Role? { .popUpButton }
    override func accessibilityTitle() -> String? { "More options for " + chat }

    @objc func showMenu() {
        guard item == nil, let menuHost else { return }
        let archive = MenuItemButton(title: "Archive", target: nil, action: nil)
        archive.target = self
        archive.action = #selector(pickArchive)
        archive.frame = NSRect(x: frame.minX, y: frame.maxY + 4, width: 90, height: 28)
        menuHost.addSubview(archive)
        item = archive
        log("menu", chat)
    }

    @objc func pickArchive() {
        item?.removeFromSuperview()
        item = nil
        log("archive", chat)
    }
}

final class MenuItemButton: NSButton {
    override func accessibilityRole() -> NSAccessibility.Role? { .menuItem }
}

let app = NSApplication.shared
let delegate = StandIn()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
