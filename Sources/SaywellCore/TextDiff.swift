import Foundation

/// Word-level comparison between an original and an edited text, used to show exactly
/// what the editor or tutor changed. Scripts without spaces (Chinese, Japanese) are
/// compared per character.
public enum TextDiff {
    public enum Segment: Equatable, Sendable {
        case same(String)
        case removed(String)
        case added(String)
    }

    public static func compare(_ a: String, _ b: String) -> [Segment] {
        let x = tokens(a), y = tokens(b)
        // Guard against quadratic blow-up on very long texts.
        if x.count * y.count > 4_000_000 { return [.removed(a), .added(b)] }
        var lcs = Array(repeating: Array(repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in stride(from: x.count - 1, through: 0, by: -1) {
            for j in stride(from: y.count - 1, through: 0, by: -1) {
                lcs[i][j] = x[i] == y[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var out: [Segment] = []
        func push(_ s: Segment) {
            switch (out.last, s) {
            case let (.same(p)?, .same(q)): out[out.count - 1] = .same(p + q)
            case let (.removed(p)?, .removed(q)): out[out.count - 1] = .removed(p + q)
            case let (.added(p)?, .added(q)): out[out.count - 1] = .added(p + q)
            default: out.append(s)
            }
        }
        var i = 0, j = 0
        while i < x.count && j < y.count {
            if x[i] == y[j] { push(.same(x[i])); i += 1; j += 1 }
            else if lcs[i + 1][j] >= lcs[i][j + 1] { push(.removed(x[i])); i += 1 }
            else { push(.added(y[j])); j += 1 }
        }
        while i < x.count { push(.removed(x[i])); i += 1 }
        while j < y.count { push(.added(y[j])); j += 1 }
        return out
    }

    public static func hasChanges(_ a: String, _ b: String) -> Bool {
        compare(a, b).contains { if case .same = $0 { return false } else { return true } }
    }

    /// Splits into words, whitespace runs and punctuation so punctuation edits are visible.
    static func tokens(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var currentIsSpace = false
        for ch in text {
            if isIdeographic(ch) || (ch.isPunctuation && ch != "'" && ch != "’" && ch != "-") {
                if !current.isEmpty { result.append(current); current = "" }
                result.append(String(ch))
                continue
            }
            let space = ch.isWhitespace
            if !current.isEmpty && space != currentIsSpace { result.append(current); current = "" }
            current.append(ch)
            currentIsSpace = space
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    static func isIdeographic(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xAC00...0xD7AF: return true
        default: return false
        }
    }
}
