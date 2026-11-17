import Foundation

// The app's archive tool is only reachable from inside a chat, so the board leaves a request file
// that an open chat's mod carries out. The token is a fresh one-time code: every mod refuses an archive
// that doesn't carry the code of a waiting request.
public struct ArchiveRequest {
    public let localId: String
    public let title: String
    public let token: String
    public let at: Double

    public init(localId: String, title: String, token: String = UUID().uuidString,
                at: Double = Date().timeIntervalSince1970 * 1000) {
        self.localId = localId
        self.title = title
        self.token = token
        self.at = at
    }

    public var fileName: String { "archive-\(localId).json" }
    public static func resultFileName(_ localId: String) -> String { "archive-\(localId).result.json" }
    // Every file a request can leave behind, removed once it's answered so the code can't be used again.
    public static func fileNames(_ localId: String) -> [String] {
        [".json", ".claimed", ".result.json"].map { "archive-\(localId)\($0)" }
    }

    public var json: [String: Any] {
        ["type": "archive", "localId": localId, "title": title, "token": token, "at": at]
    }

    public func data() -> Data? { try? JSONSerialization.data(withJSONObject: json) }
}

// "Detach to top level" for a side chat. The app only lets the child itself or its parent do this, so the request
// names both, and only those two chats' mods pick it up. Detaching only changes nesting, so no one-time code.
public struct DetachRequest {
    public let localId: String
    public let parentLocalId: String
    public let title: String
    public let at: Double

    public init(localId: String, parentLocalId: String, title: String, at: Double = Date().timeIntervalSince1970 * 1000) {
        self.localId = localId
        self.parentLocalId = parentLocalId
        self.title = title
        self.at = at
    }

    public var fileName: String { "detach-\(localId).json" }
    public static func resultFileName(_ localId: String) -> String { "detach-\(localId).result.json" }
    public static func fileNames(_ localId: String) -> [String] {
        [".json", ".claimed", ".result.json"].map { "detach-\(localId)\($0)" }
    }

    public var json: [String: Any] {
        ["type": "detach", "localId": localId, "parentLocalId": parentLocalId, "title": title, "at": at]
    }

    public func data() -> Data? { try? JSONSerialization.data(withJSONObject: json) }
}

// Renames a chat. The app's rename tool is only reachable from inside a chat, so any open chat's mod carries it out.
// The board checks the name first, so a request never asks for an empty, too long or unchanged title.
public struct RenameRequest {
    public let localId: String
    public let title: String
    public let name: String
    public let at: Double

    // The cleaned-up new name, or nil when there is nothing to rename to.
    public static func cleanName(_ input: String, current: String) -> String? {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 200, name != current else { return nil }
        return name
    }

    public init(localId: String, title: String, name: String, at: Double = Date().timeIntervalSince1970 * 1000) {
        self.localId = localId
        self.title = title
        self.name = name
        self.at = at
    }

    public var fileName: String { "rename-\(localId).json" }
    public static func resultFileName(_ localId: String) -> String { "rename-\(localId).result.json" }
    public static func fileNames(_ localId: String) -> [String] {
        [".json", ".claimed", ".result.json"].map { "rename-\(localId)\($0)" }
    }

    public var json: [String: Any] {
        ["type": "rename", "localId": localId, "title": title, "name": name, "at": at]
    }

    public func data() -> Data? { try? JSONSerialization.data(withJSONObject: json) }
}
