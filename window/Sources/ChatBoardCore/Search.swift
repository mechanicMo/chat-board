import Foundation

// Board search: which chats match what the person typed.
public enum Search {
    // Lowercase, accents dropped, and anything that isn't a letter or digit treated as a space,
    // so "client" finds "[client] bakery site - ..." and "cafe" finds "Café".
    static func words(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    // The chats whose title or status line holds every word typed, in board order. Each word can be the start
    // of a longer one, so "bak" finds "bakery". A blank query keeps the board as it is. Matches are shown flat:
    // a side session that matches without its parent would otherwise be drawn under the wrong chat.
    public static func filter(_ chats: [Chat], query: String) -> [Chat] {
        let wanted = words(query)
        guard !wanted.isEmpty else { return chats }
        return chats.compactMap { chat in
            let have = words(chat.title + " " + chat.line)
            guard wanted.allSatisfy({ word in have.contains { $0.hasPrefix(word) } }) else { return nil }
            var flat = chat
            flat.depth = 0
            return flat
        }
    }
}
