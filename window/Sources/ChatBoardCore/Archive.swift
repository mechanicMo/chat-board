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
