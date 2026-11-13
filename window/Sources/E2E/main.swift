// End-to-end tests for Chat Board. This app starts the board on made-up demo chats beside a stand-in for Claude
// (Sources/StandIn), then presses real keys and clicks the real mouse, and checks what happened:
// where keystrokes landed (the stand-in's log), what the board shows (its CHAT_BOARD_STATE file), which links it
// opened (CHAT_BOARD_OPEN_LOG), and where both windows sit on screen.
//
// It takes over the keyboard and mouse while it runs, so it runs on a machine nobody is using. Every posted event
// first checks that the stand-in or the board is in front, and the run stops if anything else is, so keystrokes
// can never land in some other app. Run it through scripts/e2e.sh, which builds the three apps.
//
//   E2E_DIR=<folder> with demo/, board.app, standin.app inside; results go to <folder>/results.txt, then DONE.

import AppKit
import ApplicationServices

// MARK: Setup

let env = ProcessInfo.processInfo.environment
let dir = env["E2E_DIR"] ?? FileManager.default.currentDirectoryPath
let demoDir = dir + "/demo"
let shareDir = demoDir + "/share"
let statePath = dir + "/board-state.json"
let openLog = dir + "/opened.txt"
let standInLog = dir + "/standin.log"
let boardApp = URL(fileURLWithPath: dir + "/Chat Board Test.app")
let standInApp = URL(fileURLWithPath: dir + "/Stand-in Claude.app")
let boardId = "com.mo.chat-board.test"
let standInId = "com.mo.chat-board.standin"
// E2E_ONLY=search,focus runs just those groups; unset or empty runs everything.
let only = env["E2E_ONLY"].flatMap { $0.isEmpty ? nil : Set($0.split(separator: ",").map(String.init)) }

var report: [String] = []
func say(_ line: String) {
    report.append(line)
    print(line)
    try? (report.joined(separator: "\n") + "\n").write(toFile: dir + "/results.txt", atomically: true, encoding: .utf8)
}

struct Failure: Error { let message: String }
// Stops the whole run: the machine isn't in a state where any later test could mean anything.
struct Abort: Error { let message: String }

func check(_ condition: Bool, _ message: @autoclosure () -> String) throws {
    if !condition { throw Failure(message: message()) }
}

// Waits while letting this app's run loop turn, so NSWorkspace's idea of the front app stays current.
func pause(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

// Polls until the condition holds, up to `timeout` seconds.
@discardableResult
func waitFor(_ timeout: Double = 3, _ condition: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if condition() { return true }
        pause(0.1)
    }
    return condition()
}

// MARK: Reading the apps

func json(_ path: String) -> [String: Any]? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

struct Row { let id: String; let localId: String; let title: String; let depth: Int; let frame: CGRect }

struct BoardState {
    let raw: [String: Any]
    var visible: Bool { raw["visible"] as? Bool ?? false }
    var isSearching: Bool { raw["isSearching"] as? Bool ?? false }
    var query: String { raw["query"] as? String ?? "" }
    var selected: Int { raw["selected"] as? Int ?? -1 }
    var notice: String { raw["notice"] as? String ?? "" }
    var panel: CGRect { rect(raw["panel"]) }
    var rows: [Row] {
        ((raw["rows"] as? [[String: Any]]) ?? []).map {
            Row(id: $0["id"] as? String ?? "", localId: $0["localId"] as? String ?? "", title: $0["title"] as? String ?? "",
                depth: $0["depth"] as? Int ?? 0, frame: rect($0["frame"]))
        }
    }
    func control(_ name: String) -> CGRect? {
        (raw["controls"] as? [String: Any])?[name].map(rect)
    }
}

func rect(_ value: Any?) -> CGRect {
    guard let list = value as? [NSNumber], list.count == 4 else { return .null }
    return CGRect(x: list[0].doubleValue, y: list[1].doubleValue, width: list[2].doubleValue, height: list[3].doubleValue)
}

// The board's state as of a fresh write (it writes every 0.2 s).
func board() -> BoardState {
    let asked = Date().timeIntervalSince1970 * 1000
    _ = waitFor(2) { ((json(statePath)?["at"] as? NSNumber)?.doubleValue ?? 0) > asked }
    return BoardState(raw: json(statePath) ?? [:])
}

struct Logged { let event: String; let value: String }

func standInEvents() -> [Logged] {
    guard let text = try? String(contentsOfFile: standInLog, encoding: .utf8) else { return [] }
    return text.split(separator: "\n").compactMap { line in
        guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { return nil }
        return Logged(event: object["event"] as? String ?? "", value: object["value"] as? String ?? "")
    }
}

// What the stand-in logged after a mark taken with `standInMark()`.
func standInMark() -> Int { standInEvents().count }
func standInSince(_ mark: Int) -> [Logged] { Array(standInEvents().dropFirst(mark)) }
func typedSince(_ mark: Int) -> String {
    standInSince(mark).filter { $0.event == "key" && !$0.value.hasPrefix("cmd+") && $0.value.count == 1 }.map(\.value).joined()
}

func openedLinks() -> [String] {
    ((try? String(contentsOfFile: openLog, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
}

// The board's saved layout (layout.json), flattened to chat ids in board order, with where each chat sits.
// Nodes are encoded like {"chat": {"_0": "<id>"}}.
func savedLayout() -> (order: [String], containers: [String: String]) {
    guard let data = FileManager.default.contents(atPath: shareDir + "/layout.json"),
          let layout = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return ([], [:]) }
    let sections = layout["sections"] as? [String: [String: Any]] ?? [:]
    let groups = layout["groups"] as? [String: [String: Any]] ?? [:]
    var order: [String] = [], containers: [String: String] = [:]
    func walk(_ nodes: [[String: Any]], in container: String) {
        for node in nodes {
            if let chat = (node["chat"] as? [String: Any])?["_0"] as? String {
                order.append(chat); containers[chat] = container
            } else if let id = (node["group"] as? [String: Any])?["_0"] as? String {
                for chat in groups[id]?["chats"] as? [String] ?? [] { order.append(chat); containers[chat] = "group:" + id }
            } else if let id = (node["section"] as? [String: Any])?["_0"] as? String {
                walk(sections[id]?["items"] as? [[String: Any]] ?? [], in: "section:" + id)
            }
        }
    }
    walk(layout["top"] as? [[String: Any]] ?? [], in: "top")
    return (order, containers)
}

func savedOrder() -> [String] { savedLayout().order }

// MARK: Apps and windows

func running(_ id: String) -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: id).first
}

func frontId() -> String? { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }

func launch(_ url: URL, environment: [String: String]) throws {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.environment = environment
    configuration.activates = true
    configuration.createsNewApplicationInstance = true
    var failure: Error?
    var done = false
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
        failure = error
        done = true
    }
    _ = waitFor(15) { done }
    if let failure { throw Abort(message: "could not open \(url.lastPathComponent): \(failure.localizedDescription)") }
}

func quit(_ id: String) {
    for app in NSRunningApplication.runningApplications(withBundleIdentifier: id) { app.terminate() }
    if !waitFor(5, { running(id) == nil }) {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: id) { app.forceTerminate() }
        _ = waitFor(3) { running(id) == nil }
    }
}

func startStandIn(mic: Bool = true) throws {
    quit(standInId)
    var environment = ["STANDIN_LOG": standInLog]
    if !mic { environment["STANDIN_NO_MIC"] = "1" }
    let mark = standInMark()
    try launch(standInApp, environment: environment)
    guard waitFor(10, { standInSince(mark).contains { $0.event == "ready" } }) else {
        throw Abort(message: "the stand-in never said it was ready")
    }
    try focusStandIn()
}

func startBoard() throws {
    quit(boardId)
    try launch(boardApp, environment: [
        "CHAT_BOARD_DEMO": demoDir, "CHAT_BOARD_TARGET": standInId,
        "CHAT_BOARD_STATE": statePath, "CHAT_BOARD_OPEN_LOG": openLog,
    ])
    guard waitFor(10, { running(boardId) != nil && board().visible }) else {
        throw Abort(message: "the board never showed beside the stand-in")
    }
    _ = waitFor(5) { board().rows.allSatisfy { !$0.frame.isNull } && !board().rows.isEmpty }
    // A freshly started app only lists its menus to accessibility after its tree has been read once. Without this
    // the first right-click menu after a restart was on screen but unreadable (measured: 1 menu window, no items).
    if let app = appElement(boardId) { _ = attribute(app, kAXChildrenAttribute) }
}

func appElement(_ id: String) -> AXUIElement? {
    running(id).map { AXUIElementCreateApplication($0.processIdentifier) }
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}

// Brings the stand-in to the front through Accessibility, the same way a click on its window would.
func focusStandIn() throws {
    guard let app = appElement(standInId) else { throw Abort(message: "the stand-in isn't running") }
    AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    if let window = attribute(app, kAXMainWindowAttribute) {
        AXUIElementPerformAction(window as! AXUIElement, kAXRaiseAction as CFString)
    }
    guard waitFor(3, { frontId() == standInId }) else {
        throw Abort(message: "the stand-in couldn't be brought to the front (front: \(frontId() ?? "none"))")
    }
}

// The stand-in's window in screen coordinates (top-left origin).
func standInWindow() -> CGRect {
    guard let app = appElement(standInId), let window = attribute(app, kAXMainWindowAttribute) ?? attribute(app, kAXFocusedWindowAttribute)
    else { return .null }
    let element = window as! AXUIElement
    guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute) else { return .null }
    var point = CGPoint.zero, extent = CGSize.zero
    AXValueGetValue(position as! AXValue, .cgPoint, &point)
    AXValueGetValue(size as! AXValue, .cgSize, &extent)
    return CGRect(origin: point, size: extent)
}

// The screen's usable area (no menu bar or Dock) in top-left coordinates.
func usableArea() -> CGRect {
    guard let screen = NSScreen.screens.first else { return .null }
    let visible = screen.visibleFrame
    return CGRect(x: visible.minX, y: screen.frame.height - visible.maxY, width: visible.width, height: visible.height)
}

// MARK: Posting input, guarded

var allowedFront: Set<String> = [standInId, boardId]

func guardFront() throws {
    let front = frontId() ?? "none"
    guard allowedFront.contains(front) else {
        throw Abort(message: "\(front) came to the front mid-run, so the run stopped before typing into it")
    }
}

let source = CGEventSource(stateID: .hidSystemState)

let keyCodes: [Character: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
    "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45,
    "m": 46, " ": 49,
]
enum Key: CGKeyCode { case returnKey = 36, escape = 53, down = 125, up = 126 }

func post(_ code: CGKeyCode, command: Bool = false) throws {
    try guardFront()
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        event?.flags = command ? .maskCommand : []
        event?.post(tap: .cghidEventTap)
        pause(0.03)
    }
    pause(0.15)
}

func press(_ key: Key) throws { try post(key.rawValue) }
func command(_ letter: Character) throws { try post(keyCodes[letter]!, command: true) }
func type(_ text: String) throws {
    for letter in text { try post(keyCodes[letter]!) }
    pause(0.2)
}

func mouse(_ type: CGEventType, _ point: CGPoint, button: CGMouseButton = .left) {
    CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)?.post(tap: .cghidEventTap)
}

func click(_ point: CGPoint) throws {
    try guardFront()
    mouse(.mouseMoved, point)
    pause(0.05)
    mouse(.leftMouseDown, point)
    pause(0.05)
    mouse(.leftMouseUp, point)
    pause(0.4)
}

func rightClick(_ point: CGPoint) throws {
    try guardFront()
    mouse(.mouseMoved, point)
    pause(0.05)
    mouse(.rightMouseDown, point, button: .right)
    pause(0.05)
    mouse(.rightMouseUp, point, button: .right)
    pause(0.5)
}

func drag(from start: CGPoint, to end: CGPoint) throws {
    try guardFront()
    mouse(.mouseMoved, start)
    pause(0.05)
    mouse(.leftMouseDown, start)
    pause(0.1)
    for step in 1...12 {
        let t = Double(step) / 12
        mouse(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
        pause(0.03)
    }
    pause(0.1)
    mouse(.leftMouseUp, end)
    pause(0.6)
}

func center(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

// A spot on the board with no row or control under it.
func blankSpot() -> CGPoint {
    let panel = board().panel
    return CGPoint(x: panel.midX, y: panel.maxY - 25)
}

// Types a short word and checks it reached the stand-in's message box and nothing reached the board.
func assertTypingGoesToStandIn(_ context: String) throws {
    let word = ["kiwi", "lemon", "mango", "plum"].randomElement()!
    let mark = standInMark()
    let queryBefore = board().query
    try type(word)
    _ = waitFor(2) { typedSince(mark).contains(word) }
    try check(typedSince(mark).contains(word), "\(context): typed \"\(word)\" but the stand-in got \"\(typedSince(mark))\"")
    try check(board().query == queryBefore, "\(context): the board's search box took the typing (\"\(board().query)\")")
}

// MARK: Tests

struct Test { let group: String; let name: String; let body: () throws -> Void }
var tests: [Test] = []
func test(_ group: String, _ name: String, _ body: @escaping () throws -> Void) { tests.append(Test(group: group, name: name, body: body)) }

// Puts both apps back to a known state between tests: search closed, stand-in in front, board showing.
func reset() throws {
    allowedFront = [standInId, boardId]
    if running(standInId) == nil { try startStandIn() }
    if running(boardId) == nil { try startBoard() }
    try focusStandIn()
    if board().isSearching { try press(.escape) }
    _ = waitFor(2) { !board().isSearching && board().visible }
    try focusStandIn()
}

// Docking and resizing

test("docking", "the board sits at the left edge and the stand-in fills the rest") {
    let area = usableArea()
    _ = waitFor(3) { abs(board().panel.width + standInWindow().width - area.width) <= 2 }
    let panel = board().panel, other = standInWindow()
    try check(abs(panel.minX - area.minX) <= 1, "board left edge \(panel.minX), screen starts at \(area.minX)")
    try check(abs(panel.height - area.height) <= 2, "board height \(panel.height), screen \(area.height)")
    try check(abs(other.minX - panel.maxX) <= 2, "stand-in starts at \(other.minX), board ends at \(panel.maxX)")
    try check(abs(panel.width + other.width - area.width) <= 2, "widths \(panel.width) + \(other.width) != \(area.width)")
    try check(abs(other.height - area.height) <= 2, "stand-in height \(other.height), screen \(area.height)")
}

test("docking", "dragging the board wider makes the stand-in narrower") {
    let area = usableArea()
    let before = board().panel
    let y = before.midY
    try drag(from: CGPoint(x: before.maxX - 1, y: y), to: CGPoint(x: before.maxX + 119, y: y))
    _ = waitFor(3) { abs(board().panel.width + standInWindow().width - area.width) <= 2 && board().panel.width > before.width + 60 }
    let after = board().panel, other = standInWindow()
    try check(after.width > before.width + 60, "board width went \(before.width) -> \(after.width) after a 120 pt drag")
    try check(abs(after.width + other.width - area.width) <= 2, "widths \(after.width) + \(other.width) != \(area.width)")
    try check(abs(other.minX - after.maxX) <= 2, "stand-in starts at \(other.minX), board ends at \(after.maxX)")
}

test("docking", "dragging the stand-in's left edge makes the board narrower") {
    let area = usableArea()
    let before = board().panel
    let other = standInWindow()
    try drag(from: CGPoint(x: other.minX + 1, y: other.midY), to: CGPoint(x: other.minX - 99, y: other.midY))
    _ = waitFor(3) { abs(board().panel.width + standInWindow().width - area.width) <= 2 && board().panel.width < before.width - 50 }
    let after = board().panel, now = standInWindow()
    try check(after.width < before.width - 50, "board width went \(before.width) -> \(after.width) after the stand-in grew 100 pt")
    try check(abs(after.width + now.width - area.width) <= 2, "widths \(after.width) + \(now.width) != \(area.width)")
}

test("docking", "the board hides when another app is in front and comes back with the stand-in") {
    allowedFront.insert("com.apple.finder")
    // Opening a folder brings Finder forward with a window, which works even when Finder had none open.
    NSWorkspace.shared.open(URL(fileURLWithPath: demoDir))
    try check(waitFor(3) { frontId() == "com.apple.finder" }, "Finder never came to the front")
    try check(waitFor(3) { !board().visible }, "the board stayed up over Finder")
    try focusStandIn()
    try check(waitFor(3) { board().visible }, "the board didn't come back with the stand-in")
}

// Clicking and where the keyboard goes

test("focus", "clicking a chat opens it and the keyboard stays with the stand-in") {
    let row = board().rows[min(2, board().rows.count - 1)]
    let opened = openedLinks().count
    try click(center(row.frame))
    try check(waitFor(2) { openedLinks().count > opened }, "no link was opened for \(row.title)")
    try check(openedLinks().last?.hasSuffix(row.localId) == true, "opened \(openedLinks().last ?? "") for \(row.localId)")
    try assertTypingGoesToStandIn("after clicking a chat")
}

test("focus", "clicking an empty spot on the board leaves the keyboard with the stand-in") {
    try click(blankSpot())
    try assertTypingGoesToStandIn("after clicking an empty spot")
}

// The bug Mo found on 2026-11-06: after a search, a click on the board kept the keyboard.
test("focus", "after a search, a click on an empty spot gives the keyboard back") {
    try command("f")
    try check(waitFor(2) { board().isSearching }, "Cmd+F didn't open the search")
    try press(.escape)
    try check(waitFor(2) { !board().isSearching }, "Escape didn't close the search")
    try click(blankSpot())
    try assertTypingGoesToStandIn("after a search and a click on the board")
}

test("focus", "a click inside the open search box keeps the keyboard on the board") {
    try command("f")
    try check(waitFor(2) { board().isSearching }, "Cmd+F didn't open the search")
    guard let field = board().control("searchField") else { throw Failure(message: "the board didn't report its search box") }
    let mark = standInMark()
    try click(center(field))
    try check(board().isSearching, "clicking the search box closed the search")
    try type("bak")
    try check(waitFor(2) { board().query == "bak" }, "the search box has \"\(board().query)\" after typing bak")
    try check(typedSince(mark).isEmpty, "the stand-in also got \"\(typedSince(mark))\"")
}

// Search

test("search", "Cmd+F opens the board's search, not the stand-in's Find") {
    let mark = standInMark()
    try command("f")
    try check(waitFor(2) { board().isSearching }, "the search didn't open")
    try check(!standInSince(mark).contains { $0.event == "find" || $0.value == "cmd+f" }, "the stand-in saw Cmd+F too")
}

test("search", "typing filters to the matching chats only") {
    let all = board().rows
    let expected = all.filter { $0.title.lowercased().contains("client") }.map(\.id)
    try check(expected.count >= 2 && expected.count < all.count, "demo data should have some, not all, client chats")
    try command("f")
    try type("client")
    try check(waitFor(2) { board().query == "client" }, "the search box has \"\(board().query)\"")
    let shown = board().rows
    try check(Set(shown.map(\.id)) == Set(expected), "showing \(shown.map(\.title)), expected \(expected.count) client chats")
    try check(shown.allSatisfy { $0.depth == 0 }, "matches should be drawn flat")
}

test("search", "down arrow and Return open the second match, then the keyboard goes back") {
    try command("f")
    try type("client")
    _ = waitFor(2) { board().query == "client" }
    let shown = board().rows
    try check(shown.count >= 2, "need two matches, got \(shown.count)")
    try check(board().selected == 0, "the first match should start selected, got \(board().selected)")
    try press(.down)
    try check(waitFor(2) { board().selected == 1 }, "down arrow left the selection at \(board().selected)")
    let opened = openedLinks().count
    try press(.returnKey)
    try check(waitFor(2) { openedLinks().count > opened }, "Return opened nothing")
    try check(openedLinks().last?.hasSuffix(shown[1].localId) == true, "opened \(openedLinks().last ?? "") instead of \(shown[1].localId)")
    try check(waitFor(2) { !board().isSearching }, "the search stayed open after opening a chat")
    try assertTypingGoesToStandIn("after opening a chat from the search")
}

test("search", "Escape closes the search and gives the keyboard back") {
    try command("f")
    try type("dog")
    _ = waitFor(2) { board().query == "dog" }
    try press(.escape)
    try check(waitFor(2) { !board().isSearching }, "Escape left the search open")
    try check(board().rows.count > 2, "the full list didn't come back")
    try assertTypingGoesToStandIn("after Escape")
}

test("search", "Cmd+F a second time opens the stand-in's own Find") {
    try command("f")
    try check(waitFor(2) { board().isSearching }, "the first Cmd+F didn't open the search")
    let mark = standInMark()
    try command("f")
    try check(waitFor(3) { standInSince(mark).contains { $0.event == "find" } }, "the stand-in's Find never opened")
    try check(!board().isSearching, "the board's search stayed open")
}

test("search", "a search that matches nothing shows no chats") {
    try command("f")
    try type("zzqq")
    try check(waitFor(2) { board().query == "zzqq" }, "the search box has \"\(board().query)\"")
    try check(board().rows.isEmpty, "showing \(board().rows.map(\.title)) for zzqq")
}

test("search", "the magnifier opens the search and typing goes into it") {
    guard let button = board().control("searchButton") else { throw Failure(message: "the board didn't report its search button") }
    let mark = standInMark()
    try click(center(button))
    try check(waitFor(2) { board().isSearching }, "clicking the magnifier didn't open the search")
    try type("yoga")
    try check(waitFor(2) { board().query == "yoga" }, "the search box has \"\(board().query)\" after typing yoga")
    try check(typedSince(mark).isEmpty, "the stand-in also got \"\(typedSince(mark))\"")
}

test("search", "rows can't be dragged into a new order while searching") {
    let order = savedOrder()
    try command("f")
    try check(waitFor(2) { board().isSearching }, "the search didn't open")
    let rows = board().rows.filter { $0.depth == 0 }
    try check(rows.count >= 3, "need three chats on screen")
    try drag(from: center(rows[0].frame), to: CGPoint(x: rows[2].frame.midX, y: rows[2].frame.maxY + 3))
    try check(savedOrder() == order, "the saved order changed during a search")
}

test("search", "with the board hidden from its menu, Cmd+F goes to the stand-in") {
    try toggleBoardFromMenu()
    try check(waitFor(3) { !board().visible }, "the menu's Show or hide didn't hide the board")
    defer { try? toggleBoardFromMenu(); _ = waitFor(3) { board().visible } }
    try focusStandIn()
    let mark = standInMark()
    try command("f")
    try check(waitFor(2) { standInSince(mark).contains { $0.event == "find" } }, "the stand-in's Find didn't open")
    try check(!board().isSearching, "the hidden board opened its search")
    try focusStandIn()
    try check(!board().visible, "the board came back on its own after being hidden from the menu")
}

// Presses the board's menu bar item, then its "Show or hide Chat Board" entry.
func toggleBoardFromMenu() throws {
    guard let app = appElement(boardId), let extras = attribute(app, "AXExtrasMenuBar"),
          let items = attribute(extras as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement], let item = items.first
    else { throw Failure(message: "the board's menu bar item wasn't found") }
    AXUIElementPerformAction(item, kAXPressAction as CFString)
    pause(0.4)
    func find(_ element: AXUIElement, _ depth: Int) -> AXUIElement? {
        if depth > 4 { return nil }
        if (attribute(element, kAXTitleAttribute) as? String) == "Show or hide Chat Board" { return element }
        for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            if let found = find(child, depth + 1) { return found }
        }
        return nil
    }
    guard let entry = find(item, 0) else {
        AXUIElementPerformAction(item, kAXCancelAction as CFString)
        throw Failure(message: "the menu's Show or hide entry wasn't found")
    }
    AXUIElementPerformAction(entry, kAXPressAction as CFString)
    pause(0.4)
}

// Cmd+D

test("dictation", "Cmd+D presses the stand-in's microphone instead of passing through") {
    let mark = standInMark()
    try command("d")
    try check(waitFor(2) { standInSince(mark).contains { $0.event == "mic" } }, "the microphone wasn't pressed")
    try check(!standInSince(mark).contains { $0.value == "cmd+d" }, "Cmd+D also reached the stand-in")
}

test("dictation", "with no microphone button, Cmd+D passes through to the stand-in") {
    try startStandIn(mic: false)
    defer { try? startStandIn(mic: true) }
    _ = waitFor(3) { board().visible }
    let mark = standInMark()
    try command("d")
    try check(waitFor(2) { standInSince(mark).contains { $0.value == "cmd+d" } }, "Cmd+D never reached the stand-in")
    try check(!standInSince(mark).contains { $0.event == "mic" }, "a microphone that isn't there was pressed")
}

// Ordering

test("order", "dragging a chat down moves it, and the order survives a restart") {
    // Dragging reorders within one section, so pick three loose chats that share one.
    let containers = savedLayout().containers
    let parents = board().rows.filter { $0.depth == 0 }
    let shared = Dictionary(grouping: parents) { containers[$0.id] ?? "" }.values.first { $0.count >= 3 }
    guard let shared else { throw Failure(message: "need three loose chats in one section") }
    let moving = shared[0], below = shared[2]
    try drag(from: center(moving.frame), to: CGPoint(x: below.frame.midX, y: below.frame.maxY + 4))
    let order = savedOrder()
    guard let moved = order.firstIndex(of: moving.id), let anchor = order.firstIndex(of: below.id) else {
        throw Failure(message: "the saved order is missing the dragged chats")
    }
    try check(moved > anchor, "\(moving.title) should now be after \(below.title)")
    let shownBefore = board().rows.map(\.id)
    try startBoard()
    try focusStandIn()
    try check(waitFor(3) { board().rows.map(\.id) == shownBefore }, "the order changed after restarting the board")
}

// Archive and notices

test("archive", "Archive from the right-click menu leaves a request and shows the answer") {
    let row = board().rows.first { $0.depth == 0 }!
    try rightClick(center(row.frame))
    try pressMenuItem("Archive")
    let request = "\(shareDir)/requests/archive-\(row.localId).json"
    try check(waitFor(2) { FileManager.default.fileExists(atPath: request) }, "no request file was written")
    try check((json(request)?["token"] as? String)?.isEmpty == false, "the request has no one-time code")
    try check(board().notice.hasPrefix("Archiving"), "the notice says \"\(board().notice)\"")
    let answer = "Archived \(row.title) (test)."
    try JSONSerialization.data(withJSONObject: ["text": answer])
        .write(to: URL(fileURLWithPath: "\(shareDir)/requests/archive-\(row.localId).result.json"))
    try check(waitFor(5) { board().notice == answer }, "the notice says \"\(board().notice)\" instead of the answer")
    try check(!FileManager.default.fileExists(atPath: request), "the answered request was left behind")
}

test("archive", "an archive nobody picks up says so after 20 seconds") {
    let row = board().rows.filter { $0.depth == 0 }[1]
    try rightClick(center(row.frame))
    try pressMenuItem("Archive")
    try check(waitFor(26) { board().notice.hasPrefix("No open chat picked up") }, "after 26 s the notice says \"\(board().notice)\"")
}

// How many menu windows the board has on screen, read from the window server rather than accessibility, so a
// menu that is up but not yet readable can be told apart from no menu at all.
func boardMenuWindows() -> Int {
    guard let pid = running(boardId)?.processIdentifier,
          let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return -1 }
    return windows.filter {
        ($0[kCGWindowOwnerPID as String] as? Int32) == pid && (($0[kCGWindowLayer as String] as? Int) ?? 0) >= Int(CGWindowLevelForKey(.popUpMenuWindow))
    }.count
}

// Presses an item of the context menu the board has open.
func pressMenuItem(_ title: String) throws {
    guard let app = appElement(boardId) else { throw Failure(message: "the board isn't running") }
    func find(_ element: AXUIElement, _ depth: Int) -> AXUIElement? {
        if depth > 6 { return nil }
        if (attribute(element, kAXRoleAttribute) as? String) == (kAXMenuItemRole as String),
           (attribute(element, kAXTitleAttribute) as? String) == title { return element }
        for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            if let found = find(child, depth + 1) { return found }
        }
        return nil
    }
    var item: AXUIElement?
    _ = waitFor(2) { item = find(app, 0); return item != nil }
    guard let item else {
        throw Failure(message: "the right-click menu has no \(title) item (\(boardMenuWindows()) menu windows of the board on screen)")
    }
    AXUIElementPerformAction(item, kAXPressAction as CFString)
    pause(0.5)
}

test("config", "an unreadable config.json hides every chat and says so, and fixing it brings them back") {
    let path = shareDir + "/config.json"
    try "{ not json".write(toFile: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: path) }
    try check(waitFor(5) { board().rows.isEmpty }, "chats still showing with a broken config")
    try check(board().notice.contains("config.json can't be read"), "the notice says \"\(board().notice)\"")
    try FileManager.default.removeItem(atPath: path)
    try check(waitFor(5) { !board().rows.isEmpty }, "chats didn't come back once the config was fixed")
}

// MARK: Run

func preflight() throws {
    // Asking with the prompt option also puts this app in the Accessibility list, ready to be switched on.
    let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    guard AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary) else {
        throw Abort(message: "this runner doesn't have Accessibility (System Settings > Privacy & Security > Accessibility)")
    }
    let session = (CGSessionCopyCurrentDictionary() as? [String: Any]) ?? [:]
    if (session["CGSSessionScreenIsLocked"] as? Bool) == true || (session["CGSSessionScreenIsLocked"] as? Int) == 1 {
        throw Abort(message: "the screen is locked, so no key or click can reach an app")
    }
    for path in [boardApp.path, standInApp.path, demoDir + "/records"] where !FileManager.default.fileExists(atPath: path) {
        throw Abort(message: "missing \(path)")
    }
    try startStandIn()
    let started = Date().timeIntervalSince1970 * 1000
    try startBoard()
    // The board rewrites this every 2 s, so wait for a copy written after it started.
    let status = { json(shareDir + "/dock-status.json") ?? [:] }
    _ = waitFor(6) { ((status()["at"] as? NSNumber)?.doubleValue ?? 0) > started }
    guard (status()["accessibilityAllowed"] as? Bool) == true else {
        throw Abort(message: "the test board doesn't have Accessibility, so docking and the shortcuts can't work")
    }
    // A key posted by this runner has to land: if it doesn't, every test after would fail for the same reason.
    try focusStandIn()
    let mark = standInMark()
    try type("zq")
    guard waitFor(2, { typedSince(mark).contains("zq") }) else {
        throw Abort(message: "a typed test word never reached the stand-in (got \"\(typedSince(mark))\"), so posted keys are dropped")
    }
}

func main() -> Int32 {
    try? FileManager.default.removeItem(atPath: dir + "/DONE")
    for path in [standInLog, openLog, statePath, dir + "/results.txt"] { try? FileManager.default.removeItem(atPath: path) }
    say("Chat Board end-to-end run, \(Date())")
    var passed = 0, failed = 0, skipped = 0
    do {
        try preflight()
        say("preflight: ok")
        for test in tests {
            if let only, !only.contains(test.group) { skipped += 1; continue }
            do {
                try reset()
                try test.body()
                passed += 1
                say("PASS  [\(test.group)] \(test.name)")
            } catch let failure as Failure {
                failed += 1
                say("FAIL  [\(test.group)] \(test.name): \(failure.message)")
            }
        }
    } catch let abort as Abort {
        say("STOPPED: \(abort.message)")
        failed += 1
    } catch {
        say("STOPPED: \(error)")
        failed += 1
    }
    quit(boardId)
    quit(standInId)
    say("\(passed) passed, \(failed) failed, \(skipped) skipped")
    FileManager.default.createFile(atPath: dir + "/DONE", contents: Data((failed == 0 && passed > 0 ? "pass" : "fail").utf8))
    return failed == 0 && passed > 0 ? 0 : 1
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
exit(main())
