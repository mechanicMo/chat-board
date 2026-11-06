import AppKit
import ChatBoardCore
import SwiftUI

// MARK: Views

private func age(_ ms: Double) -> String {
    guard ms > 0 else { return "" }
    let minutes = Int(max(0, Date().timeIntervalSince1970 * 1000 - ms) / 60000)
    if minutes < 1 { return "now" }
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    return hours < 48 ? "\(hours)h" : "\(hours / 24)d"
}

struct ChatRow: View {
    let chat: Chat
    let isCurrent: Bool
    let isUnread: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isCurrent ? Color.white.opacity(0.9) : chat.kind.color.opacity(isUnread ? 1 : 0.4))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    // Up to two lines, so a narrow window still shows enough of the title to recognize it.
                    Text(chat.title)
                        .font(.system(size: 16, weight: isUnread || isCurrent ? .bold : .regular))
                        .foregroundStyle(isCurrent ? Color.white : Color.primary.opacity(isUnread ? 1 : 0.62))
                        .lineLimit(2)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    if isUnread {
                        Circle().fill(chat.kind.color).frame(width: 8, height: 8)
                    }
                    Text(age(chat.activeAt))
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(isCurrent ? Color.white.opacity(0.85) : .secondary)
                }
                if !chat.line.isEmpty {
                    Text(chat.line)
                        .font(.system(size: 14))
                        .foregroundStyle(isCurrent ? Color.white.opacity(0.85) : Color.primary.opacity(isUnread ? 0.75 : 0.42))
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
        }
        .foregroundStyle(isCurrent ? Color.white : Color.primary)
        .padding(.vertical, 6)
        .padding(.horizontal, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrent ? chat.kind.color : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help(chat.line)
    }
}

// Lays its items left to right and wraps to a new line when the row is full, so the color key fits any width.
struct Flow: Layout {
    var spacing: CGFloat = 10
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += line + lineSpacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += line + lineSpacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

struct RowFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct WindowFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// Watches the notice on its own, so the X and the 10-second auto-clear redraw just this bar.
struct NoticeBar: View {
    @ObservedObject var notice: Notice

    var body: some View {
        if let text = notice.text {
            HStack(alignment: .top, spacing: 6) {
                Text(text)
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    notice.text = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.07)))
        }
    }
}

struct BoardView: View {
    @ObservedObject var board: BoardModel
    @State private var frames: [String: CGRect] = [:]
    @State private var dragging: String?
    @State private var dragOffset: CGFloat = 0
    @State private var dropBefore: String?

    // Each side session belongs to the group of the parent listed above it.
    private var groupOf: [String: String] {
        var map: [String: String] = [:]
        var parent: String?
        for chat in board.chats {
            if chat.depth == 0 { parent = chat.id }
            map[chat.id] = chat.depth == 0 ? chat.id : (parent ?? chat.id)
        }
        return map
    }

    // The group a drop at height y lands before: the first other parent whose middle is below the pointer.
    private func target(at y: CGFloat) -> String? {
        board.chats
            .filter { $0.depth == 0 && $0.id != dragging }
            .first { (frames[$0.id]?.midY ?? .infinity) > y }?
            .id
    }

    private var dropLineY: CGFloat? {
        if let dropBefore, let frame = frames[dropBefore] { return frame.minY - 1 }
        return frames.values.map(\.maxY).max().map { $0 + 1 }
    }

    private func drag(_ group: String) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("list"))
            .onChanged { value in
                dragging = group
                dragOffset = value.translation.height
                dropBefore = target(at: value.location.y)
            }
            .onEnded { value in
                board.moveGroup(group, before: target(at: value.location.y))
                dragging = nil
                dragOffset = 0
                dropBefore = nil
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Counts sit beside the title when there's room, under it when the window is narrow.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Chats").font(.system(size: 20, weight: .bold))
                    Spacer(minLength: 8)
                    counts
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chats").font(.system(size: 20, weight: .bold))
                    counts
                }
            }
            Flow(spacing: 12) {
                ForEach(Kind.allCases, id: \.self) { kind in
                    HStack(spacing: 3) {
                        Circle().fill(kind.color).frame(width: 10, height: 10)
                        Text(kind.label).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            NoticeBar(notice: board.notice)
            // A plain stack rather than a List: a List drops the first click in a window that isn't focused,
            // and the panel is never focused (Claude stays in front). Click and drag are handled here instead.
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(board.chats) { chat in
                        let group = groupOf[chat.id] ?? chat.id
                        let isMoving = dragging == group
                        ChatRow(chat: chat, isCurrent: chat.id == board.currentId, isUnread: board.isUnread(chat))
                            .padding(.leading, chat.depth > 0 ? 18 : 0)
                            .background(GeometryReader { geometry in
                                Color.clear
                                    .preference(key: RowFrames.self, value: [chat.id: geometry.frame(in: .named("list"))])
                                    .preference(key: WindowFrames.self, value: [chat.id: geometry.frame(in: .global)])
                            })
                            .offset(y: isMoving ? dragOffset : 0)
                            .opacity(isMoving ? 0.8 : 1)
                            .zIndex(isMoving ? 1 : 0)
                            .contentShape(Rectangle())
                            .gesture(drag(group))
                            .contextMenu {
                                Button("Open") { board.open(chat) }
                                Button("Archive") { board.archive(chat) }
                            }
                    }
                }
                .padding(.vertical, 2)
                .overlay(alignment: .topLeading) {
                    if dragging != nil, let y = dropLineY {
                        Capsule().fill(Color.accentColor).frame(height: 3).offset(y: y - 1.5)
                    }
                }
            }
            .coordinateSpace(name: "list")
            .onPreferenceChange(RowFrames.self) { frames = $0 }
            .onPreferenceChange(WindowFrames.self) { board.rowsInWindow = $0 }
        }
        .padding(10)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
    }

    private var counts: some View {
        Text("\(board.chats.filter { $0.kind == .question }.count) questions · \(board.chats.filter { $0.kind == .yourMove }.count) your move · \(board.chats.filter { $0.kind == .ready }.count) ready")
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

// MARK: App

// The panel never becomes the active window, so without this the first click on it only focuses it.
final class FirstClickHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// The board never keeps the keyboard: clicks and drags work without it, and typing stays in Claude.
final class ClickThroughPanel: NSPanel {
    override var canBecomeKey: Bool { false }

    // A window that isn't focused loses SwiftUI's first click, but every click still passes through here.
    // A press and release within a few points is a click; anything longer is a drag, left to the list.
    var onClick: ((CGPoint) -> Void)?
    private var pressedAt: CGPoint?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { pressedAt = event.locationInWindow }
        if event.type == .leftMouseUp, let start = pressedAt {
            let end = event.locationInWindow
            if hypot(end.x - start.x, end.y - start.y) < 4 {
                // AppKit counts from the window's bottom; SwiftUI's window space counts from the top.
                onClick?(CGPoint(x: end.x, y: frame.height - end.y))
            }
            pressedAt = nil
            super.sendEvent(event)
            // Whatever the click or drag did, the keyboard belongs to Claude afterwards.
            NSRunningApplication.runningApplications(withBundleIdentifier: AppDelegate.claude).first?.activate()
            return
        }
        super.sendEvent(event)
    }

}

// Keeps the board pinned to the screen's left edge at full height and Claude's window filling the rest,
// so the two always add up to the screen's width. Resizing either one resizes the other.
// Moving Claude's window needs the Accessibility permission; without it only the board docks.
@MainActor
final class ClaudeDock: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private var observer: AXObserver?
    private var watchedWindow: AXUIElement?
    private var watchedPid: pid_t = 0
    private var isAdjusting = false
    private let geometry = DockGeometry(minPanelWidth: 200)

    init(panel: NSPanel) {
        self.panel = panel
        super.init()
        panel.delegate = self
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        if !AXIsProcessTrusted() {
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        }
    }

    private var area: NSRect { (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero }

    // Pins the board to the left edge and fits Claude beside it.
    func dock() {
        setPanel(width: geometry.clampPanelWidth(panel.frame.width, area: area))
        attach()
        fitClaude()
    }

    private func setPanel(width: CGFloat) {
        let frame = geometry.panelFrame(width: width, area: area)
        if panel.frame != frame {
            isAdjusting = true
            panel.setFrame(frame, display: true)
            isAdjusting = false
        }
    }

    // The board only grows or shrinks from its right edge, and always stays full height.
    func windowWillResize(_ sender: NSWindow, to size: NSSize) -> NSSize {
        geometry.panelSizeForResize(to: size, area: area)
    }

    func windowDidResize(_ notification: Notification) {
        guard !isAdjusting else { return }
        setPanel(width: panel.frame.width)
        fitClaude()
    }

    // MARK: Claude's window, through the Accessibility API

    private var claudeApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: AppDelegate.claude).first
    }

    private func claudeWindow() -> AXUIElement? {
        guard AXIsProcessTrusted(), let pid = claudeApp?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            if AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success, let value {
                return (value as! AXUIElement)
            }
        }
        return nil
    }

    // The main screen's height, for turning Accessibility coordinates into AppKit ones.
    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private func frame(of window: AXUIElement) -> NSRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return DockGeometry.appKitFrame(axOrigin: point, size: extent, primaryHeight: primaryHeight)
    }

    private func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value) == .success && (value as? Bool) == true
    }

    func fitClaude() {
        guard panel.isVisible, let window = claudeWindow(), !isFullScreen(window) else { return }
        let target = geometry.claudeFrame(panelWidth: panel.frame.width, area: area)
        guard geometry.needsMove(frame(of: window), to: target) else { return }
        isAdjusting = true
        var point = DockGeometry.axOrigin(of: target, primaryHeight: primaryHeight)
        var size = CGSize(width: target.width, height: target.height)
        if let position = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) }
        if let extent = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, extent) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.isAdjusting = false }
    }

    // When you resize Claude, the board takes whatever width is left, then Claude is squared up beside it.
    fileprivate func claudeChanged() {
        guard !isAdjusting, panel.isVisible, let window = claudeWindow(), !isFullScreen(window), let now = frame(of: window) else {
            attach()
            return
        }
        let width = geometry.panelWidth(afterClaudeMovedTo: now, area: area)
        if geometry.panelNeedsResize(current: panel.frame.width, wanted: width) { setPanel(width: width) }
        fitClaude()
        attach()
    }

    // What docking can see, written where it can be read back when docking misbehaves.
    func writeStatus() {
        let window = claudeWindow()
        let status: [String: Any] = [
            "at": Date().timeIntervalSince1970 * 1000,
            "accessibilityAllowed": AXIsProcessTrusted(),
            "claudeRunning": claudeApp != nil,
            "claudeWindowFound": window != nil,
            "claudeFrame": window.flatMap { frame(of: $0) }.map { "\(Int($0.minX)),\(Int($0.width))" } ?? "",
            "boardFrame": "\(Int(panel.frame.minX)),\(Int(panel.frame.width))",
            "watching": watchedWindow != nil,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: status) {
            FileManager.default.createFile(atPath: shareDir + "/dock-status.json", contents: data)
        }
    }

    // Watches Claude's current window for moves and resizes, and the app for switching windows.
    func attach() {
        guard AXIsProcessTrusted(), let pid = claudeApp?.processIdentifier else { return }
        if pid != watchedPid {
            if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
            observer = nil
            watchedWindow = nil
            var created: AXObserver?
            let callback: AXObserverCallback = { _, _, _, refcon in
                guard let refcon else { return }
                let dock = Unmanaged<ClaudeDock>.fromOpaque(refcon).takeUnretainedValue()
                MainActor.assumeIsolated { dock.claudeChanged() }
            }
            guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
            observer = created
            watchedPid = pid
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
            let app = AXUIElementCreateApplication(pid)
            let me = Unmanaged.passUnretained(self).toOpaque()
            AXObserverAddNotification(created, app, kAXMainWindowChangedNotification as CFString, me)
            AXObserverAddNotification(created, app, kAXFocusedWindowChangedNotification as CFString, me)
        }
        guard let observer, let window = claudeWindow() else { return }
        if let watchedWindow, CFEqual(watchedWindow, window) { return }
        let me = Unmanaged.passUnretained(self).toOpaque()
        if let watchedWindow {
            AXObserverRemoveNotification(observer, watchedWindow, kAXResizedNotification as CFString)
            AXObserverRemoveNotification(observer, watchedWindow, kAXMovedNotification as CFString)
        }
        AXObserverAddNotification(observer, window, kAXResizedNotification as CFString, me)
        AXObserverAddNotification(observer, window, kAXMovedNotification as CFString, me)
        watchedWindow = window
    }
}

// Cmd+D makes Claude's microphone toggle instead of hold-to-talk: while Claude or the board is in front,
// Chat Board brings Claude forward and clicks its microphone button (an accessibility press, the same as a
// mouse click), and holds back the original keystroke. No audio is touched. If the button isn't there,
// for example while Claude is replying and shows Stop instead, the keystroke passes through unchanged.
@MainActor
final class DictationToggle {
    private var tap: CFMachPort?
    private static let dKey: Int64 = 0x02

    init() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let toggle = Unmanaged<DictationToggle>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                MainActor.assumeIsolated { toggle.reenable() }
                return Unmanaged.passUnretained(event)
            }
            let flags = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
            guard type == .keyDown, flags == .maskCommand,
                  event.getIntegerValueField(.keyboardEventKeycode) == DictationToggle.dKey,
                  event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return Unmanaged.passUnretained(event) }
            let handled = MainActor.assumeIsolated { toggle.clickMicrophone() }
            return handled ? nil : Unmanaged.passUnretained(event)
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: callback,
                                userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap {
            CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    // Brings Claude forward and clicks the microphone button in its front window. False when it isn't there.
    func clickMicrophone() -> Bool {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard front == AppDelegate.claude || front == Bundle.main.bundleIdentifier,
              let claude = NSRunningApplication.runningApplications(withBundleIdentifier: AppDelegate.claude).first
        else { return false }
        let app = AXUIElementCreateApplication(claude.processIdentifier)
        // Claude is an Electron app: its page only shows up to accessibility once asked.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, let button = microphone(in: window as! AXUIElement, depth: 0) else { return false }
        claude.activate()
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    private func microphone(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 60 else { return nil }
        func text(_ attribute: String) -> String {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            return (value as? String) ?? ""
        }
        if text(kAXRoleAttribute) == kAXButtonRole as String {
            let shortcut = text("AXKeyShortcutsValue").lowercased()
            let label = (text(kAXDescriptionAttribute) + " " + text(kAXTitleAttribute)).lowercased()
            if shortcut == "meta+d" || label.contains("dictat") || label.contains("voice input") || label.contains("microphone") {
                return element
            }
        }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let list = children as? [AXUIElement] else { return nil }
        for child in list.reversed() {  // the prompt box sits at the bottom of the window
            if let found = microphone(in: child, depth: depth + 1) { return found }
        }
        return nil
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private var dock: ClaudeDock!
    private var dictation: DictationToggle!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let board = BoardModel()
        panel = ClickThroughPanel(
            contentRect: NSRect(x: 40, y: 120, width: 400, height: 760),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Chats"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = FirstClickHostingView(rootView: AnyView(BoardView(board: board).background(.regularMaterial)))
        (panel as? ClickThroughPanel)?.onClick = { [weak board] point in board?.click(at: point) }
        board.isPointerHeld = { [weak panel] in
            guard let panel, panel.isVisible else { return false }
            return NSEvent.pressedMouseButtons & 1 != 0 && panel.frame.contains(NSEvent.mouseLocation)
        }
        panel.contentMinSize = NSSize(width: 200, height: 240)
        panel.setFrameAutosaveName("ChatBoardPanel")
        dock = ClaudeDock(panel: panel)
        // Until the Accessibility permission is granted, keep checking so docking starts the moment it is.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.panel.isVisible == true { self?.dock.attach(); self?.dock.fitClaude() }
                self?.dock.writeStatus()
            }
        }
        followClaude(NSWorkspace.shared.frontmostApplication)
        // Launching can briefly put another app in front; look again once that settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.followClaude(NSWorkspace.shared.frontmostApplication)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.followClaude(app) }
        }

        dictation = DictationToggle()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "list.bullet.rectangle", accessibilityDescription: "Chat Board")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show or hide Chat Board", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(withTitle: "Chat Board shows only while Claude is in front", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Chat Board", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.first?.target = self
        statusItem.menu = menu
    }

    // Shown only while Claude is the app in front, so it never sits over other apps.
    // The panel never takes focus itself, so clicking it keeps Claude in front.
    nonisolated static let claude = "com.anthropic.claudefordesktop"
    private var isHiddenByPerson = false

    func followClaude(_ app: NSRunningApplication?) {
        if app?.bundleIdentifier == Self.claude, !isHiddenByPerson {
            panel.orderFrontRegardless()
            dock.dock()
        } else if app?.bundleIdentifier != Bundle.main.bundleIdentifier {
            panel.orderOut(nil)
        }
    }

    @objc func toggle() {
        isHiddenByPerson = panel.isVisible
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless(); dock.dock() }
    }
}

// Debugging aid for the Cmd+D shortcut: prints every button in Claude's front window with its accessibility
// labels, so the microphone button can be found again if an app update renames it.
func listClaudeButtons() {
    guard AXIsProcessTrusted(),
          let claude = NSRunningApplication.runningApplications(withBundleIdentifier: AppDelegate.claude).first else {
        print("not allowed or Claude not running")
        return
    }
    func text(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (value as? String) ?? ""
    }
    var seen = 0
    var roles: [String: Int] = [:]
    func walk(_ element: AXUIElement, depth: Int) {
        guard depth < 60, seen < 4000 else { return }
        seen += 1
        roles[text(element, kAXRoleAttribute), default: 0] += 1
        if text(element, kAXRoleAttribute) == kAXButtonRole as String {
            var names: CFArray?
            AXUIElementCopyAttributeNames(element, &names)
            var parts: [String] = []
            for name in (names as? [String]) ?? [] {
                var value: CFTypeRef?
                AXUIElementCopyAttributeValue(element, name as CFString, &value)
                if let string = value as? String, !string.isEmpty { parts.append("\(name)=\(string.prefix(40))") }
                if let list = value as? [String], !list.isEmpty { parts.append("\(name)=\(list.joined(separator: ",").prefix(60))") }
            }
            print("button:", parts.joined(separator: " | "))
        }
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let list = children as? [AXUIElement] {
            for child in list { walk(child, depth: depth + 1) }
        }
    }
    let app = AXUIElementCreateApplication(claude.processIdentifier)
    // Electron apps only build their page's accessibility tree once asked to.
    AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    Thread.sleep(forTimeInterval: 1)
    var window: CFTypeRef?
    AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window)
    if let window { walk(window as! AXUIElement, depth: 0) } else { print("no window") }
    var windows: CFTypeRef?
    AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
    print("windows:", (windows as? [AXUIElement])?.count ?? 0, "| elements walked:", seen, "| roles:", roles.sorted { $0.value > $1.value }.prefix(12).map { "\($0.key)=\($0.value)" }.joined(separator: " "))
}

@MainActor
private func snapshot(to path: String, width: Double, height: Double) {
    let board = BoardModel()
    let view = NSHostingView(rootView: BoardView(board: board).background(Color(nsColor: .windowBackgroundColor)))
    view.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = view
    view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

@main
struct ChatBoardApp {
    static func main() {
        let app = NSApplication.shared
        // `ChatBoard --find-buttons` lists Claude's buttons, to find the ones Chat Board presses.
        if CommandLine.arguments.contains("--find-buttons") {
            listClaudeButtons()
            return
        }
        // `ChatBoard --snapshot out.png` draws the board once to an image and exits, so it can be checked by eye.
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(flag + 1) {
            let width = arguments.firstIndex(of: "--width").flatMap { arguments.indices.contains($0 + 1) ? Double(arguments[$0 + 1]) : nil } ?? 400
            let height = arguments.firstIndex(of: "--height").flatMap { arguments.indices.contains($0 + 1) ? Double(arguments[$0 + 1]) : nil } ?? 760
            MainActor.assumeIsolated { snapshot(to: arguments[flag + 1], width: width, height: height) }
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
