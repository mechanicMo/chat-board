import Foundation

public struct Chat: Identifiable, Equatable, Sendable {
    public let id: String          // the CLI session id, which the mod and the shared order use
    public let localId: String     // the id the app's links use
    public let title: String
    public let kind: Kind
    public let line: String
    public let activeAt: Double
    public let focusedAt: Double
    public let parentLocalId: String?  // set for a side session the app started from another chat
    public let finishedAt: Double      // when the chat last finished a turn
    public let viewedAt: Double        // when the person last had the chat in front of them
    public var depth = 0               // 1 when drawn under its parent
    public let folder: String          // the last part of the folder the chat runs in, for matching it to a project

    public init(id: String, localId: String, title: String, kind: Kind, line: String, activeAt: Double,
                focusedAt: Double, parentLocalId: String? = nil, finishedAt: Double = 0, viewedAt: Double = 0,
                depth: Int = 0, folder: String = "") {
        self.id = id
        self.localId = localId
        self.title = title
        self.kind = kind
        self.line = line
        self.activeAt = activeAt
        self.focusedAt = focusedAt
        self.parentLocalId = parentLocalId
        self.finishedAt = finishedAt
        self.viewedAt = viewedAt
        self.depth = depth
        self.folder = folder
    }
}

// True when `cwd` is one of the private folders or inside one. A folder that only shares a prefix
// (a "notes-old" next to "notes") does not count.
public func isPrivate(cwd: String, privateFolders: [String]) -> Bool {
    privateFolders.contains { folder in cwd == folder || cwd.hasPrefix(folder + "/") }
}

// Builds the board's entry for one of the app's chat records and the mod's row for it,
// or nil when the chat should not be listed.
public func chat(record: [String: Any], row: [String: Any]?, privateFolders: [String],
                 now: Double = Date().timeIntervalSince1970 * 1000) -> Chat? {
    guard record["isArchived"] as? Bool != true,
          let id = record["cliSessionId"] as? String,
          let localId = record["sessionId"] as? String else { return nil }
    // Runs of a scheduled routine live in the app's Routines section, not in the chat list.
    if record["scheduledTaskId"] is String { return nil }
    if isPrivate(cwd: record["cwd"] as? String ?? "", privateFolders: privateFolders) { return nil }
    // The person switched the mod off in this chat.
    if row?["isOff"] as? Bool == true { return nil }
    let (kind, line) = describe(row, now: now)
    return Chat(
        id: id,
        localId: localId,
        title: (record["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled chat",
        kind: kind,
        line: line,
        activeAt: max(number(record["lastActivityAt"]), number(row?["userAt"]), number(row?["repliedAt"])),
        focusedAt: number(record["lastFocusedAt"]),
        parentLocalId: (record["spawnedFrom"] as? [String: Any])?["sessionId"] as? String,
        finishedAt: max(number(row?["repliedAt"]), number(record["lastTurnEdgeAt"])),
        viewedAt: number(record["lastFocusedAt"]),
        folder: ((record["cwd"] as? String) ?? "").split(separator: "/").last.map(String.init) ?? ""
    )
}
