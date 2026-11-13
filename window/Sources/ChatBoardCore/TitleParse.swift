import Foundation

// What a chat title says about where it belongs. Titles follow `[tag] project - task`; the tag becomes a section on
// the board and the project a group. The project keeps the title's spelling for display; `key` is for matching.
public struct ParsedTitle: Equatable, Sendable {
    public let tag: String?
    public let project: String?
    public let task: String

    public init(tag: String?, project: String?, task: String) {
        self.tag = tag
        self.project = project
        self.task = task
    }
}

public enum TitleParse {
    // `[tag] project - task`, where the separator is the first run of dashes with spaces around it.
    private static let tagged = try! NSRegularExpression(pattern: #"^\s*\[([^\]]+)\]\s*(.*)$"#)
    private static let separator = try! NSRegularExpression(pattern: #"\s+-+\s+"#)
    // `Project: task`, for titles written before the format. Up to three words before the colon, so an ordinary
    // sentence that happens to hold a colon isn't read as a project.
    private static let colon = try! NSRegularExpression(pattern: #"^\s*([^\s:\[\]]+(?:\s+[^\s:\[\]]+){0,2})\s*:\s+(.+)$"#)

    public static func parse(_ title: String) -> ParsedTitle {
        let whole = NSRange(title.startIndex..., in: title)
        if let match = tagged.firstMatch(in: title, range: whole),
           let tagRange = Range(match.range(at: 1), in: title), let restRange = Range(match.range(at: 2), in: title) {
            let tag = title[tagRange].trimmingCharacters(in: .whitespaces)
            let rest = String(title[restRange])
            if let split = separator.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
               let range = Range(split.range, in: rest) {
                let project = rest[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let task = rest[range.upperBound...].trimmingCharacters(in: .whitespaces)
                return ParsedTitle(tag: tag.isEmpty ? nil : tag, project: project.isEmpty ? nil : project, task: task)
            }
            return ParsedTitle(tag: tag.isEmpty ? nil : tag, project: nil, task: rest.trimmingCharacters(in: .whitespaces))
        }
        if let match = colon.firstMatch(in: title, range: whole),
           let projectRange = Range(match.range(at: 1), in: title), let taskRange = Range(match.range(at: 2), in: title) {
            return ParsedTitle(tag: nil, project: String(title[projectRange]), task: String(title[taskRange]))
        }
        return ParsedTitle(tag: nil, project: nil, task: title)
    }

    // Lowercase with runs of whitespace collapsed, so "Orchard  Games" and "orchard games" match.
    public static func key(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
