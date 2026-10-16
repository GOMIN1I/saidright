import Foundation

/// Writes spoken numbers as digits, the way people type them: “пятнадцатое марта в четырнадцать
/// часов тридцать минут, кабинет двести четыре” → “15 марта в 14 часов 30 минут, кабинет 204”;
/// “two thousand five hundred users” → “2500 users”.
///
/// Used for recognisers that spell numbers out (Parakeet). Russian, English and German
/// cardinals (German compounds such as “zweitausendfünfhundert”), and Russian day ordinals
/// before a month name. Single small numbers (“один из нас”, “three servers”, “drei Tage”)
/// stay words, as in edited prose.
public enum NumberNormalizer {
    enum Kind { case unit, teen, ten, hundred, scale }
    struct Word { var value: Int; var kind: Kind }

    static let russian: [String: Word] = {
        var map: [String: Word] = [:]
        func add(_ forms: [String], _ value: Int, _ kind: Kind) { for f in forms { map[f] = Word(value: value, kind: kind) } }
        add(["ноль", "нуль", "ноля", "нуля", "нолю", "нулю"], 0, .unit)
        add(["один", "одна", "одно", "одного", "одной", "одному", "одним", "одном", "одну"], 1, .unit)
        add(["два", "две", "двух", "двум", "двумя"], 2, .unit)
        add(["три", "трех", "трем", "тремя"], 3, .unit)
        add(["четыре", "четырех", "четырем", "четырьмя"], 4, .unit)
        add(["пять", "пяти", "пятью"], 5, .unit)
        add(["шесть", "шести", "шестью"], 6, .unit)
        add(["семь", "семи", "семью"], 7, .unit)
        add(["восемь", "восьми", "восемью", "восьмью"], 8, .unit)
        add(["девять", "девяти", "девятью"], 9, .unit)
        let teens = ["десят": 10, "одиннадцат": 11, "двенадцат": 12, "тринадцат": 13, "четырнадцат": 14, "пятнадцат": 15, "шестнадцат": 16, "семнадцат": 17, "восемнадцат": 18, "девятнадцат": 19]
        for (stem, v) in teens { add([stem + "ь", stem + "и", stem + "ью"], v, .teen) }
        add(["двадцать", "двадцати", "двадцатью"], 20, .ten)
        add(["тридцать", "тридцати", "тридцатью"], 30, .ten)
        add(["сорок", "сорока"], 40, .ten)
        add(["пятьдесят", "пятидесяти", "пятьюдесятью"], 50, .ten)
        add(["шестьдесят", "шестидесяти", "шестьюдесятью"], 60, .ten)
        add(["семьдесят", "семидесяти", "семьюдесятью"], 70, .ten)
        add(["восемьдесят", "восьмидесяти", "восемьюдесятью"], 80, .ten)
        add(["девяносто", "девяноста"], 90, .ten)
        add(["сто", "ста"], 100, .hundred)
        add(["двести", "двухсот", "двумстам", "двумястами", "двухстах"], 200, .hundred)
        add(["триста", "трехсот", "тремстам", "тремястами", "трехстах"], 300, .hundred)
        add(["четыреста", "четырехсот", "четыремстам", "четырехстах"], 400, .hundred)
        for (w, v) in ["пят": 500, "шест": 600, "сем": 700, "восем": 800, "девят": 900] {
            let gen = w == "восем" ? "восьмисот" : w + "исот"
            add([w + "ьсот", gen, w + "истам", w + "ьюстами", w + "истах"], v, .hundred)
        }
        add(["тысяча", "тысячи", "тысяч", "тысячу", "тысячам", "тысячей", "тысячах"], 1000, .scale)
        add(["миллион", "миллиона", "миллионов", "миллиону", "миллионам", "миллионах"], 1_000_000, .scale)
        add(["миллиард", "миллиарда", "миллиардов"], 1_000_000_000, .scale)
        return map
    }()

    static let english: [String: Word] = {
        var map: [String: Word] = [:]
        let units = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        for (i, w) in units.enumerated() { map[w] = Word(value: i, kind: .unit) }
        let teens = ["ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
        for (i, w) in teens.enumerated() { map[w] = Word(value: 10 + i, kind: .teen) }
        let tens = ["twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
        for (i, w) in tens.enumerated() { map[w] = Word(value: 20 + 10 * i, kind: .ten) }
        map["hundred"] = Word(value: 100, kind: .hundred)
        map["thousand"] = Word(value: 1000, kind: .scale)
        map["million"] = Word(value: 1_000_000, kind: .scale)
        map["billion"] = Word(value: 1_000_000_000, kind: .scale)
        return map
    }()

    /// Russian day ordinals 1–31 in the forms used before a month (“пятнадцатое”, “пятнадцатого”).
    static let russianDayOrdinals: [String: Int] = {
        var map: [String: Int] = [:]
        let stems = ["перв": 1, "втор": 2, "трет": 3, "четверт": 4, "пят": 5, "шест": 6, "седьм": 7, "восьм": 8, "девят": 9, "десят": 10,
                     "одиннадцат": 11, "двенадцат": 12, "тринадцат": 13, "четырнадцат": 14, "пятнадцат": 15, "шестнадцат": 16, "семнадцат": 17,
                     "восемнадцат": 18, "девятнадцат": 19, "двадцат": 20, "тридцат": 30]
        for (stem, v) in stems {
            let endings = stem == "трет" ? ["ье", "ьего", "ьему", "ьем"] : ["ое", "ого", "ому", "ом"]
            for e in endings { map[stem + e] = v }
        }
        return map
    }()

    static let months: Set<String> = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]

    static func key(_ word: String) -> String { word.lowercased().replacingOccurrences(of: "ё", with: "е") }

    static func lookup(_ word: String) -> Word? {
        let k = key(word)
        return russian[k] ?? english[k]
    }

    // MARK: German

    static let germanUnits: [String: Int] = ["null": 0, "eins": 1, "ein": 1, "eine": 1, "zwei": 2, "drei": 3, "vier": 4, "fünf": 5, "sechs": 6, "sieben": 7, "acht": 8, "neun": 9]
    static let germanTeens: [String: Int] = ["zehn": 10, "elf": 11, "zwölf": 12, "dreizehn": 13, "vierzehn": 14, "fünfzehn": 15, "sechzehn": 16, "siebzehn": 17, "achtzehn": 18, "neunzehn": 19]
    static let germanTens: [String: Int] = ["zwanzig": 20, "dreißig": 30, "vierzig": 40, "fünfzig": 50, "sechzig": 60, "siebzig": 70, "achtzig": 80, "neunzig": 90]

    /// Parses one German number word, which writes the whole number as a single compound:
    /// “dreihundertvierundzwanzig” = 324, “zweitausendfünfhundert” = 2500.
    static func germanValue(_ word: String) -> Int? {
        let w = word.lowercased()
        guard w.count >= 3, w.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) else { return nil }
        if let range = w.range(of: "million") {
            let head = String(w[..<range.lowerBound]), tail = String(w[range.upperBound...]).replacingOccurrences(of: "en", with: "", options: .anchored)
            let h = head.isEmpty || head == "eine" ? 1 : germanBelowThousand(head)
            guard let h else { return nil }
            if tail.isEmpty { return h * 1_000_000 }
            guard let t = germanBelowMillion(tail) else { return nil }
            return h * 1_000_000 + t
        }
        return germanBelowMillion(w)
    }

    static func germanBelowMillion(_ w: String) -> Int? {
        if let range = w.range(of: "tausend") {
            let head = String(w[..<range.lowerBound]), tail = String(w[range.upperBound...])
            let h = head.isEmpty || head == "ein" ? 1 : germanBelowThousand(head)
            guard let h else { return nil }
            if tail.isEmpty { return h * 1000 }
            guard let t = germanBelowThousand(tail) else { return nil }
            return h * 1000 + t
        }
        return germanBelowThousand(w)
    }

    static func germanBelowThousand(_ w: String) -> Int? {
        if let range = w.range(of: "hundert") {
            let head = String(w[..<range.lowerBound]), tail = String(w[range.upperBound...])
            let h = head.isEmpty || head == "ein" ? 1 : germanUnits[head]
            guard let h, h > 0 else { return nil }
            if tail.isEmpty { return h * 100 }
            guard let t = germanBelowHundred(tail) else { return nil }
            return h * 100 + t
        }
        return germanBelowHundred(w)
    }

    static func germanBelowHundred(_ w: String) -> Int? {
        if let v = germanUnits[w] ?? germanTeens[w] ?? germanTens[w] { return v }
        // “vierundzwanzig” = 4 + 20
        if let range = w.range(of: "und") {
            let unit = String(w[..<range.lowerBound]), ten = String(w[range.upperBound...])
            let u = unit == "ein" ? 1 : germanUnits[unit]
            if let u, u > 0, let t = germanTens[ten] { return u + t }
        }
        return nil
    }

    /// Parses consecutive number words; stops before a word that cannot continue the number
    /// (“два три” are two numbers). Returns value and how many tokens were used.
    static func parse(_ words: [String]) -> (value: Int, used: Int)? {
        var total = 0, current = 0, used = 0
        var last: Kind?
        var lastScale = Int.max
        var sawNumber = false
        var i = 0
        while i < words.count {
            let w = key(words[i])
            if w == "and", sawNumber, last == .hundred, i + 1 < words.count, let next = lookup(words[i + 1]), next.kind != .scale, next.kind != .hundred {
                i += 1
                continue
            }
            guard let word = lookup(w) else { break }
            switch word.kind {
            case .unit:
                if let last, last == .unit || last == .teen { return finish(total, current, used, sawNumber) }
                current += word.value
            case .teen:
                if let last, last != .hundred && last != .scale { return finish(total, current, used, sawNumber) }
                current += word.value
            case .ten:
                if let last, last != .hundred && last != .scale { return finish(total, current, used, sawNumber) }
                current += word.value
            case .hundred:
                if english[w] != nil {
                    // “two hundred”: multiplies the units before it; “a hundred” stays words.
                    if last != .unit { return finish(total, current, used, sawNumber) }
                    current = max(current, 1) * 100
                } else {
                    if last != nil && last != .scale { return finish(total, current, used, sawNumber) }
                    current += word.value
                }
            case .scale:
                if word.value >= lastScale { return finish(total, current, used, sawNumber) }
                total += max(current, 1) * word.value
                current = 0
                lastScale = word.value
            }
            last = word.kind
            sawNumber = true
            i += 1
            used = i
        }
        return finish(total, current, used, sawNumber)
    }

    private static func finish(_ total: Int, _ current: Int, _ used: Int, _ saw: Bool) -> (value: Int, used: Int)? {
        saw && used > 0 ? (total + current, used) : nil
    }

    /// Splits text into word and non-word pieces, so spacing and punctuation survive.
    static func tokenize(_ text: String) -> [(String, Bool)] {
        var out: [(String, Bool)] = []
        var current = ""
        var isWord = false
        for ch in text {
            let w = ch.isLetter || (ch == "-" && isWord && !current.isEmpty)
            if current.isEmpty { isWord = w } else if w != isWord {
                out.append((current, isWord)); current = ""; isWord = w
            }
            current.append(ch)
        }
        if !current.isEmpty { out.append((current, isWord)) }
        // English compounds: “twenty-five” → two words joined by a hyphen.
        return out.flatMap { piece -> [(String, Bool)] in
            guard piece.1, piece.0.contains("-") else { return [piece] }
            let parts = piece.0.split(separator: "-").map(String.init)
            guard parts.count == 2, lookup(parts[0])?.kind == .ten, lookup(parts[1])?.kind == .unit else { return [piece] }
            return [(parts[0], true), (" ", false), (parts[1], true)]
        }
    }

    public static func digits(_ text: String) -> String {
        let tokens = tokenize(text)
        var out = ""
        var i = 0
        while i < tokens.count {
            let (piece, isWord) = tokens[i]
            guard isWord else { out += piece; i += 1; continue }
            // Russian date: [twenty] + day ordinal + month → “21 марта”.
            if let date = russianDate(tokens, at: i) {
                out += date.text
                i = date.next
                continue
            }
            // German writes a number as one compound word; convert it when it is 10 or more
            // (“zweitausendfünfhundert Nutzer” → “2500 Nutzer”, “drei Tage” stays).
            if lookup(piece) == nil, let value = germanValue(piece), value >= 10, germanUnits[piece.lowercased()] == nil {
                out += String(value)
                i += 1
                continue
            }
            // Collect the run of number words (with the single spaces/“and” between them).
            var words: [String] = []
            var indices: [Int] = []
            var j = i
            while j < tokens.count {
                let (p, w) = tokens[j]
                if w {
                    guard lookup(p) != nil || (key(p) == "and" && !words.isEmpty) else { break }
                    words.append(p); indices.append(j); j += 1
                } else if p == " " || p == "\u{00A0}" { j += 1 } else { break }
            }
            if let parsed = parse(words), parsed.used > 0, !(parsed.used == 1 && lookup(words[0])?.kind == .scale) {
                // A bare “тысяча”/“million” is usually figurative (“тысячу раз”) and stays a word.
                let multiword = parsed.used > 1
                let lastIndex = indices[parsed.used - 1]
                // “две тысячи двадцать шестом году”: the number ends in an ordinal word, which
                // this normaliser does not write as digits; leave the whole phrase as spoken.
                let endsInOrdinal = nextWord(tokens, after: lastIndex).map(isRussianOrdinal) ?? false
                if (parsed.value >= 10 || multiword) && !endsInOrdinal {
                    out += String(parsed.value)
                    i = lastIndex + 1
                    continue
                }
            }
            out += piece
            i += 1
        }
        return out
    }

    static func nextWord(_ tokens: [(String, Bool)], after k: Int) -> String? {
        var j = k + 1
        while j < tokens.count, !tokens[j].1 { if tokens[j].0 != " " { return nil }; j += 1 }
        return j < tokens.count ? tokens[j].0 : nil
    }

    static let ordinalStems = ["перв", "втор", "трет", "четверт", "пят", "шест", "седьм", "восьм", "девят", "десят", "надцат", "двадцат", "тридцат", "сороков", "десят", "сот", "тысячн", "миллионн"]
    static let ordinalEndings = ["ый", "ой", "ий", "ая", "ое", "ого", "ому", "ым", "ом", "ую", "ые", "ых", "ыми", "ье", "ья", "ьего", "ьему", "ьем", "ьей", "ьи", "ьих"]

    static func isRussianOrdinal(_ word: String) -> Bool {
        let w = key(word)
        guard russian[w] == nil, let ending = ordinalEndings.first(where: { w.hasSuffix($0) }) else { return false }
        let stem = String(w.dropLast(ending.count))
        return ordinalStems.contains { stem.hasSuffix($0) }
    }

    private static func russianDate(_ tokens: [(String, Bool)], at i: Int) -> (text: String, next: Int)? {
        func word(_ k: Int) -> String? { k < tokens.count && tokens[k].1 ? key(tokens[k].0) : nil }
        func nextWordIndex(_ k: Int) -> Int? {
            var j = k + 1
            while j < tokens.count, !tokens[j].1 { if tokens[j].0 != " " { return nil }; j += 1 }
            return j < tokens.count ? j : nil
        }
        guard let first = word(i) else { return nil }
        var day = 0
        var ordinalIndex = i
        if let tens = russian[first], tens.kind == .ten, tens.value <= 30, let n = nextWordIndex(i), let w = word(n), let unit = russianDayOrdinals[w], unit < 10 {
            day = tens.value + unit
            ordinalIndex = n
        } else if let d = russianDayOrdinals[first] {
            day = d
        } else {
            return nil
        }
        guard day >= 1, day <= 31, let m = nextWordIndex(ordinalIndex), let month = word(m), months.contains(month) else { return nil }
        // Keep the original spelling and spacing of everything after the ordinal.
        var text = String(day)
        for k in (ordinalIndex + 1)...m { text += tokens[k].0 }
        return (text, m + 1)
    }
}
