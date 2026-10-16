import Foundation

/// Looks up interface strings for the language chosen in the app, independent of the
/// system language and of the spoken/learning languages.
///
/// Tables are standard `<lang>.lproj/Localizable.strings` files. Lookup order:
/// chosen language → English → the key itself (which makes missing strings visible in QA).
public final class Localizer: @unchecked Sendable {
    public static let shared = Localizer()

    private let lock = NSLock()
    private var tables: [String: [String: String]] = [:]
    private var current: UILanguage = .en

    public init() {}

    public var language: UILanguage { lock.withLock { current } }
    public var locale: Locale { Locale(identifier: language.rawValue) }

    public func load(directory: URL) {
        var loaded: [String: [String: String]] = [:]
        for lang in UILanguage.translated {
            let file = directory.appendingPathComponent("\(lang.rawValue).lproj/Localizable.strings")
            if let dict = NSDictionary(contentsOf: file) as? [String: String] { loaded[lang.rawValue] = dict }
        }
        lock.withLock { tables = loaded }
    }

    public func setLanguage(_ language: UILanguage) {
        let resolved = language.resolved()
        lock.withLock { current = resolved }
    }

    public func string(_ key: String) -> String {
        lock.withLock {
            tables[current.rawValue]?[key] ?? tables["en"]?[key] ?? key
        }
    }

    /// Formats with positional arguments (`%1$@`, `%2$d`) so translations can reorder them.
    public func format(_ key: String, _ args: [CVarArg]) -> String {
        String(format: string(key), locale: locale, arguments: args)
    }

    public func table(_ language: UILanguage) -> [String: String] { lock.withLock { tables[language.rawValue] ?? [:] } }
}

/// Shorthand used throughout the UI.
public func tr(_ key: String) -> String { Localizer.shared.string(key) }
public func tr(_ key: String, _ args: CVarArg...) -> String { Localizer.shared.format(key, args) }
