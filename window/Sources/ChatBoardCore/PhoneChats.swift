import Foundation

// Chats started from the phone (Claude's Remote sessions, "Duet") run on this Mac as
// `claude --sdk-url .../cse_<id> --session-id cse_<id>`, so the mod writes their rows, but the app keeps no
// local_*.json record for them: their sidebar entry comes from the server. Without a record the board dropped them
// (Mo, 2026-11-25: 7 phone chats in Claude's sidebar, none on the board).
//
// The board builds a stand-in record for each one from two things on disk:
// - the chat's transcript, whose rename results carry the server's own id and title:
//   {"ccr":{"id":"session_<id>","title":"<title>",...}}
// - the running processes, so a phone chat shows only while its process is alive on this Mac.
public enum PhoneChats {
    // The `session_<id>` of every phone chat running here, from `ps -axo command` output.
    public static func liveSessions(ps: String) -> Set<String> {
        var found: Set<String> = []
        for line in ps.split(separator: "\n") where line.contains("--sdk-url") {
            let parts = line.split(separator: " ")
            guard let flag = parts.firstIndex(of: "--session-id"), flag + 1 < parts.count else { continue }
            let value = parts[flag + 1]
            guard value.hasPrefix("cse_") else { continue }
            found.insert("session_" + value.dropFirst(4))
        }
        return found
    }

    public struct Seen: Equatable, Sendable {
        public var sessionId: String?
        public var title: String?
        public var cwd: String?
        public init(sessionId: String? = nil, title: String? = nil, cwd: String? = nil) {
            self.sessionId = sessionId
            self.title = title
            self.cwd = cwd
        }
    }

    // Reads transcript lines (whole lines only) into `seen`: the latest confirmed rename and the latest cwd.
    // Only a rename the server answered counts, so a refused one never shows a title the sidebar doesn't have.
    public static func read(lines: some Sequence<Substring>, into seen: inout Seen) {
        for line in lines {
            let hasRename = line.contains("\\\"ccr\\\"")
            let hasCwd = line.contains("\"cwd\"")
            guard hasRename || hasCwd,
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            if let cwd = object["cwd"] as? String, !cwd.isEmpty { seen.cwd = cwd }
            guard hasRename else { continue }
            for text in toolResultTexts(object) {
                guard let inner = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                      let ccr = inner["ccr"] as? [String: Any],
                      let id = ccr["id"] as? String, id.hasPrefix("session_"),
                      let title = ccr["title"] as? String, !title.isEmpty else { continue }
                seen.sessionId = id
                seen.title = title
            }
        }
    }

    private static func toolResultTexts(_ object: [String: Any]) -> [String] {
        guard let message = object["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { return [] }
        var texts: [String] = []
        for block in content where block["type"] as? String == "tool_result" {
            if let text = block["content"] as? String { texts.append(text) }
            for part in block["content"] as? [[String: Any]] ?? [] {
                if let text = part["text"] as? String { texts.append(text) }
            }
        }
        return texts
    }

    // A record shaped like the app's own, so `chat(record:row:)` treats a phone chat like any other.
    // Nil while the chat hasn't been named by the server yet or its process isn't running here.
    public static func record(cliSessionId: String, seen: Seen, live: Set<String>, lastActivityAt: Double) -> [String: Any]? {
        guard let sessionId = seen.sessionId, live.contains(sessionId), let title = seen.title else { return nil }
        return [
            "cliSessionId": cliSessionId,
            "sessionId": sessionId,
            "title": title,
            "cwd": seen.cwd ?? "",
            "lastActivityAt": lastActivityAt,
            // Its name lives on the server, so only Claude's own menu can rename it (the mod's rename tool
            // takes local_ ids only).
            "titleSource": "user",
            "isPhone": true,
        ]
    }
}
