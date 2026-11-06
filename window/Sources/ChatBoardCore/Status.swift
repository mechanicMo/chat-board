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
    if let verdict, verdict["isDone"] as? Bool == true { return (.ready, verdict["left"] as? String ?? "") }
    if let verdict { return (.yourMove, "Left: " + (verdict["left"] as? String ?? "")) }
    if let summary = row["summary"] as? [String: Any], number(summary["updatedAt"]) >= since {
        return (summary["status"] as? String == "ready_to_close" ? .ready : .yourMove, summary["next"] as? String ?? "")
    }
    if let recap = end?["recap"] as? String, !recap.isEmpty { return (.yourMove, recap) }
    let replied = number(row["repliedAt"])
    return (.yourMove, replied > 0 ? "Replied at \(clock(replied))." : "")
}
