import Foundation

// The person's settings, from ~/.claude/chat-hud/config.json. The mod reads the same file.
//   {"privateFolders": ["~/some/folder"]}
// Chats started in one of those folders, or anywhere inside one, never appear on the board.
public enum Config {
    public enum Folders: Equatable, Sendable {
        case list([String])
        // The file exists but can't be read. The board then shows no chats rather than risk showing a private one.
        case unreadable
    }

    // `~` and `~/...` are expanded against `home`; a trailing slash is ignored.
    public static func privateFolders(from data: Data?, home: String) -> Folders {
        guard let data else { return .list([]) }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .unreadable }
        guard let value = object["privateFolders"] else { return .list([]) }
        guard let folders = value as? [String] else { return .unreadable }
        return .list(folders.compactMap { expand($0, home: home) })
    }

    public static func privateFolders(atPath path: String, home: String) -> Folders {
        privateFolders(from: FileManager.default.contents(atPath: path), home: home)
    }

    static func expand(_ folder: String, home: String) -> String? {
        var path = folder.trimmingCharacters(in: .whitespaces)
        if path == "~" { path = home } else if path.hasPrefix("~/") { path = home + path.dropFirst(1) }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        // An empty entry or "/" would hide every chat; neither is a folder someone means.
        return path.isEmpty || path == "/" ? nil : path
    }
}
