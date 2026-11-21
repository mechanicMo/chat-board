import Combine
import Foundation

// A message floating over the bottom of the board. It closes itself after `delay` seconds, unless a newer one replaced it.
@MainActor
public final class Notice: ObservableObject {
    @Published public var text: String? {
        didSet {
            guard let shown = text else { return }
            if let logPath { Notice.append(shown, to: logPath) }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                if self?.text == shown { self?.text = nil }
            }
        }
    }

    public let delay: TimeInterval
    // Where every message is also written, with its time, so one that closed before anyone read it can still be found.
    public let logPath: String?

    public init(delay: TimeInterval = 5, logPath: String? = nil) {
        self.delay = delay
        self.logPath = logPath
    }

    // Appends one timestamped line. Past 1 MB the log starts over, keeping the last one as `<path>.1`.
    public nonisolated static func append(_ text: String, to path: String, at date: Date = Date()) {
        let manager = FileManager.default
        if let size = (try? manager.attributesOfItem(atPath: path))?[.size] as? Int, size > 1_000_000 {
            try? manager.removeItem(atPath: path + ".1")
            try? manager.moveItem(atPath: path, toPath: path + ".1")
        }
        let stamp = ISO8601DateFormatter.string(from: date, timeZone: .current, formatOptions: [.withInternetDateTime])
        let line = Data((stamp + "  " + text.replacingOccurrences(of: "\n", with: " ") + "\n").utf8)
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            manager.createFile(atPath: path, contents: line)
        }
    }
}
