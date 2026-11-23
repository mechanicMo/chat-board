import Foundation

// Three states, by whose move it is: the chat's, the person's, or nobody's because it's finished.
// Raw values match the kind names the mod uses, so both sides read the same fixture.
public enum Kind: String, CaseIterable, Sendable {
    case question, yourMove = "your_move", ready, working

    public var label: String {
        switch self {
        case .question: "Question for you"
        case .yourMove: "Your move"
        case .ready: "Ready to close"
        case .working: "Working"
        }
    }
}

func number(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? 0 }

func clock(_ ms: Double) -> String {
    let format = DateFormatter()
    format.dateFormat = "h:mm a"
    return format.string(from: Date(timeIntervalSince1970: ms / 1000))
}

// Tools that open a card for the person (rename, archive, a question, a plan) finish in a moment otherwise.
public let cardTools: [String: String] = [
    "mcp__ccd_session_mgmt__set_session_title": "rename this chat",
    "mcp__ccd_session_mgmt__archive_session": "archive a chat",
    "mcp__ccd_session__start_session": "start a new session",
    "AskUserQuestion": "answer a question",
    "ExitPlanMode": "approve the plan",
    "mcp__computer-use__request_access": "computer access",
    "mcp__computer-use__request_full_control": "computer access",
]

// Tools that can run for minutes on their own, so a long wait on one says nothing about the person.
let slowPrefixes = ["Bash", "Agent", "Task", "Workflow", "WebFetch", "WebSearch", "advisor", "Monitor",
                    "mcp__computer-use__", "mcp__claude-in-chrome__", "mcp__Claude_Browser__", "mcp__blender__",
                    "mcp__Claude_Code_iOS_Simulator__", "mcp__plugin_"]

// The words shown after "Waiting for your OK: ". A known card's own words, else an MCP tool's name
// without its server, else the tool name as it is.
public func toolLabel(_ tool: String) -> String {
    if let known = cardTools[tool] { return known }
    if tool.hasPrefix("mcp__") {
        let parts = tool.components(separatedBy: "__")
        if parts.count >= 3 {
            let name = parts[2...].joined(separator: "__")
            if !name.isEmpty { return name.replacingOccurrences(of: "_", with: " ") }
        }
    }
    return tool
}

// The chat is stuck on a card waiting for the person when a call the permission check put to them is pending,
// or a card tool has been pending over 3 seconds, or any other quick tool over 20 seconds.
public func waitingOn(_ pending: [String: Any]?, now: Double) -> String? {
    guard let pending, let tool = pending["tool"] as? String else { return nil }
    let age = now - number(pending["at"])
    let name = toolLabel(tool)
    if pending["asked"] as? Bool == true { return name }
    if cardTools[tool] != nil { return age > 3000 ? name : nil }
    if slowPrefixes.contains(where: { tool.hasPrefix($0) }) { return nil }
    return age > 20000 ? name : nil
}

// How long work left running keeps a chat grey. Mirrors the mod's BACKGROUND_STALE_MS: its end starts a new turn
// that rewrites the list, so a list this old means that turn never came (a lost notification, a quit app).
public let backgroundStaleMs: Double = 3 * 60 * 60000

// What the chat left running when its last turn ended, as one line. Mirrors the mod's `runningInBackground`.
// The chat's own label counts even with an empty engine list: a session it started never appears in that list.
public func runningInBackground(_ row: [String: Any], now: Double) -> String? {
    let since = number(row["userAt"])
    var named: String? = nil
    if let verdict = row["verdict"] as? [String: Any], number(verdict["at"]) >= since,
       now - number(verdict["at"]) <= backgroundStaleMs,
       let label = verdict["background"] as? String, !label.isEmpty { named = label }
    guard let running = row["background"] as? [String: Any],
          let items = running["items"] as? [[String: Any]], let first = items.first else { return named }
    let at = number(running["at"])
    guard at >= since, now - at <= backgroundStaleMs else { return named }
    if let named { return named }
    let more = items.count - 1
    return (first["label"] as? String ?? "") + (more > 0 ? " (+\(more) more)" : "")
}

// What a chat says, from the freshest thing it reported since the person last wrote. Mirrors the mod's `describe`.
public func describe(_ row: [String: Any]?, now: Double = Date().timeIntervalSince1970 * 1000) -> (Kind, String) {
    guard let row else { return (.yourMove, "") }
    if let waiting = waitingOn(row["pending"] as? [String: Any], now: now) { return (.question, "Waiting for your OK: " + waiting) }
    if row["phase"] as? String == "working" { return (.working, "Working on your message") }
    let since = number(row["userAt"])
    let end = (row["turnEnd"] as? [String: Any]).flatMap { number($0["at"]) >= since ? $0 : nil }
    let verdict = (row["verdict"] as? [String: Any]).flatMap { number($0["at"]) >= since ? $0 : nil }
    // A question beats everything: the chat can't finish until it's answered.
    if let ask = end?["ask"] as? String, !ask.isEmpty { return (.question, ask) }
    if let written = row["textQuestion"] as? [String: Any], number(written["at"]) >= since, let text = written["text"] as? String {
        return (.question, text)
    }
    // Work left running wakes the chat when it ends, so the chat still has the move, even if it called itself done.
    if let background = runningInBackground(row, now: now) { return (.working, "Running in the background: " + background) }
    if let verdict, verdict["isDone"] as? Bool == true { return (.ready, verdict["left"] as? String ?? "") }
    if let verdict { return (.yourMove, "Left: " + (verdict["left"] as? String ?? "")) }
    if let summary = row["summary"] as? [String: Any], number(summary["updatedAt"]) >= since {
        return (summary["status"] as? String == "ready_to_close" ? .ready : .yourMove, summary["next"] as? String ?? "")
    }
    if let recap = end?["recap"] as? String, !recap.isEmpty { return (.yourMove, recap) }
    let replied = number(row["repliedAt"])
    return (.yourMove, replied > 0 ? "Replied at \(clock(replied))." : "")
}

// One button from a chat's end-of-turn box, as Chat Board draws it. `action` is set for the app's own buttons
// (commit, create_pr, ...), whose text Claude draws itself; a reply button sends its label as the person's answer.
// `reply` is set for an orange chat's go-ahead: there is no button in Claude to press, so the board types `reply`
// into the chat's message box instead. `since` is when the chat reported it, so a click on a button the chat has
// since replaced does nothing.
public struct AnswerButton: Equatable, Sendable {
    public let label: String
    public let action: String?
    public let reply: String?
    public let since: Double
    public init(label: String, action: String? = nil, reply: String? = nil, since: Double = 0) {
        self.label = label
        self.action = action
        self.reply = reply
        self.since = since
    }
}

// The words the board shows for the app's own buttons. Claude's own text for them isn't known ahead of time,
// so pressing one looks for these words and presses nothing when it can't find them.
public let appActionLabels: [String: String] = [
    "commit": "Commit", "create_pr": "Create PR", "merge": "Merge", "fix_ci": "Fix CI",
    "address_comments": "Address comments", "resolve_conflicts": "Resolve conflicts", "verify": "Verify",
    "archive": "Archive", "new_session": "New session",
]

// The buttons to draw beside a chat's question: only when the line shown is the end-of-turn box's own question
// (not a waiting card or a question written in a reply), and only when the box has one or two buttons and nothing else.
// Mo, 2026-11-17: "If the question only has like one or two buttons, then have that. If it does not ... it should just
// stay the way it is."
public func answerButtons(_ row: [String: Any]?, now: Double = Date().timeIntervalSince1970 * 1000) -> [AnswerButton] {
    guard let row, waitingOn(row["pending"] as? [String: Any], now: now) == nil,
          row["phase"] as? String != "working",
          let end = row["turnEnd"] as? [String: Any], number(end["at"]) >= number(row["userAt"]),
          let ask = end["ask"] as? String, !ask.isEmpty,
          let actions = end["actions"] as? [[String: Any]], (1...2).contains(actions.count) else { return [] }
    let buttons: [AnswerButton] = actions.compactMap { item in
        let label = (item["label"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        if let action = item["action"] as? String, !action.isEmpty {
            return AnswerButton(label: appActionLabels[action] ?? action.replacingOccurrences(of: "_", with: " ").capitalized, action: action)
        }
        return label.isEmpty ? nil : AnswerButton(label: label)
    }
    return buttons.count == actions.count ? buttons : []
}

// Whether a button in Claude's window is the one to press. A reply button's text is exactly its label. An app
// button's text is Claude's own, so it only has to start with the board's word for it ("Commit" matches "Commit changes").
public func buttonMatches(_ text: String, _ button: AnswerButton) -> Bool {
    let shown = text.trimmingCharacters(in: .whitespaces).lowercased()
    let wanted = button.label.lowercased()
    guard !shown.isEmpty, !shown.hasPrefix("more options") else { return false }
    return button.action == nil ? shown == wanted : shown.hasPrefix(wanted)
}

// The one button drawn on an orange chat whose only open item is the person's OK for one step the chat itself will do.
// The chat names that step in chat_status's `go_ahead` (the board never guesses it from the sentence). Shown only when
// the orange line comes from that same report: nothing waiting on a card, no question, not working, not done.
// Mo, 2026-11-17: "A lot of orange chats have just like a go ahead that you're waiting for ... add that kind of
// flexible button for orange chats."
public func goAheadButtons(_ row: [String: Any]?, now: Double = Date().timeIntervalSince1970 * 1000) -> [AnswerButton] {
    guard let row, describe(row, now: now).0 == .yourMove,
          let verdict = row["verdict"] as? [String: Any], number(verdict["at"]) >= number(row["userAt"]),
          verdict["isDone"] as? Bool != true else { return [] }
    let step = (verdict["goAhead"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !step.isEmpty else { return [] }
    return [AnswerButton(label: "Go ahead: " + step, reply: "Go ahead: " + step, since: number(verdict["at"]))]
}

// The buttons a chat's row carries: its end-of-turn question's, else an orange chat's go-ahead.
public func rowButtons(_ row: [String: Any]?, now: Double = Date().timeIntervalSince1970 * 1000) -> [AnswerButton] {
    let asked = answerButtons(row, now: now)
    return asked.isEmpty ? goAheadButtons(row, now: now) : asked
}

// Whether `localId` is the chat open in Claude: Claude stamps lastFocusedAt on a chat's record when it is brought to
// the front, so the open one carries the newest stamp. Read from the records on disk at the moment of asking.
public func isFrontChat(_ localId: String, records: [[String: Any]]) -> Bool {
    guard let front = records.max(by: { number($0["lastFocusedAt"]) < number($1["lastFocusedAt"]) }) else { return false }
    return front["sessionId"] as? String == localId
}

// Whether the chat still offers this exact button: same go-ahead, from the same report, nothing written since.
public func stillOffered(_ button: AnswerButton, row: [String: Any]?, now: Double = Date().timeIntervalSince1970 * 1000) -> Bool {
    rowButtons(row, now: now).contains(button)
}
