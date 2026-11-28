import Foundation

// Cmd+1 to Cmd+9 open the first nine chats on the board, top to bottom as they're drawn, and holding Cmd shows
// each of those chats its number (Mo, 2026-11-28: the same as Claude's own sidebar).
public enum Shortcuts {
    // The number keys' key codes on a Mac keyboard (the row above the letters), 1 to 9.
    static let numberKeys: [Int64: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    // Which number a key press is, or nil when the key isn't 1 to 9.
    public static func number(forKeyCode code: Int64) -> Int? { numberKeys[code] }

    // Each of the first nine chats on screen and its number, keyed by chat id.
    public static func numbers(_ visible: [Chat]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: visible.prefix(9).enumerated().map { ($0.element.id, $0.offset + 1) })
    }

    // The chat a number opens, or nil when fewer chats are on screen.
    public static func chat(_ number: Int, in visible: [Chat]) -> Chat? {
        (1...9).contains(number) && visible.count >= number ? visible[number - 1] : nil
    }
}
