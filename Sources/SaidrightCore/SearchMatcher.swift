import Foundation

/// Scores how well a query matches a searchable item made of weighted text fields.
/// Matching is case, diacritic and width insensitive, treats "ё" like "е", and requires every
/// query word to appear as a word prefix somewhere in the item. Used by settings search.
public enum SearchMatcher {
    public struct Field: Sendable {
        public var text: String
        /// Higher weight ranks the item higher when a word matches here (title > synonyms > detail).
        public var weight: Int
        public init(_ text: String, weight: Int) { self.text = text; self.weight = weight }
    }

    public static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "ё", with: "е")
    }

    /// Splits into words; Han characters count as their own words so Chinese queries work
    /// without spaces.
    static func words(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for ch in normalize(text) {
            if ch.unicodeScalars.contains(where: { (0x3400...0x9FFF).contains($0.value) }) {
                if !current.isEmpty { result.append(current); current = "" }
                result.append(String(ch))
            } else if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else if !current.isEmpty {
                result.append(current); current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// nil when some query word is not found. Otherwise a positive score; higher is better.
    public static func score(query: String, fields: [Field]) -> Int? {
        let queryWords = words(query)
        guard !queryWords.isEmpty else { return nil }
        let fieldWords = fields.map { (words($0.text), $0.weight) }
        var total = 0
        for q in queryWords {
            var best = 0
            for (ws, weight) in fieldWords {
                for (i, w) in ws.enumerated() where w.hasPrefix(q) {
                    // Exact word > prefix; an early word (e.g. the first word of a title) ranks a little higher.
                    let quality = (w == q ? 3 : 2) * weight + max(0, 3 - i)
                    best = max(best, quality)
                }
            }
            guard best > 0 else { return nil }
            total += best
        }
        return total
    }
}
