import Foundation

/// A language the product knows about. UI localization, speech recognition,
/// text editing, explanations and speech synthesis are separate capabilities;
/// a language can be strong in one and absent in another.
public struct LanguageInfo: Identifiable, Hashable, Sendable {
    /// BCP-47 style code used throughout the app ("en", "ru", "zh-Hans").
    public let id: String
    /// Name in the language itself, so people recognise it regardless of UI language.
    public let nativeName: String
    /// ISO 639-1 code Whisper uses for this language, if Whisper supports it.
    public let whisperCode: String?
    /// Locale identifier for Apple speech services (dictation and TTS).
    public let appleLocale: String
    public let isRightToLeft: Bool
    /// How much this project has verified recognition for the language.
    public let recognitionStatus: CoverageStatus
    /// Whether explanations and corrections have been checked by this project.
    public let learningStatus: CoverageStatus

    public init(id: String, nativeName: String, whisperCode: String?, appleLocale: String, isRightToLeft: Bool = false, recognitionStatus: CoverageStatus, learningStatus: CoverageStatus) {
        self.id = id
        self.nativeName = nativeName
        self.whisperCode = whisperCode
        self.appleLocale = appleLocale
        self.isRightToLeft = isRightToLeft
        self.recognitionStatus = recognitionStatus
        self.learningStatus = learningStatus
    }
}

public enum CoverageStatus: String, Codable, Sendable, Comparable {
    /// Exercised by this project's fixtures and manual checks.
    case tested
    /// Supported by the underlying engine/model, not verified here.
    case modelSupported
    /// Expected to work through the same pipeline but known to be weak or unchecked.
    case experimental
    case unsupported

    private var rank: Int { switch self { case .tested: 3; case .modelSupported: 2; case .experimental: 1; case .unsupported: 0 } }
    public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

public enum LanguageCatalog {
    /// Spoken/learning languages offered in pickers. Ordered by expected use, not alphabetically.
    public static let all: [LanguageInfo] = [
        .init(id: "ru", nativeName: "Русский", whisperCode: "ru", appleLocale: "ru_RU", recognitionStatus: .tested, learningStatus: .tested),
        .init(id: "en", nativeName: "English", whisperCode: "en", appleLocale: "en_US", recognitionStatus: .tested, learningStatus: .tested),
        .init(id: "de", nativeName: "Deutsch", whisperCode: "de", appleLocale: "de_DE", recognitionStatus: .modelSupported, learningStatus: .experimental),
        .init(id: "zh-Hans", nativeName: "简体中文", whisperCode: "zh", appleLocale: "zh_CN", recognitionStatus: .modelSupported, learningStatus: .experimental),
        .init(id: "es", nativeName: "Español", whisperCode: "es", appleLocale: "es_ES", recognitionStatus: .modelSupported, learningStatus: .experimental),
        .init(id: "fr", nativeName: "Français", whisperCode: "fr", appleLocale: "fr_FR", recognitionStatus: .modelSupported, learningStatus: .experimental),
        .init(id: "it", nativeName: "Italiano", whisperCode: "it", appleLocale: "it_IT", recognitionStatus: .modelSupported, learningStatus: .experimental),
        .init(id: "pt", nativeName: "Português", whisperCode: "pt", appleLocale: "pt_BR", recognitionStatus: .modelSupported, learningStatus: .experimental),
        .init(id: "uk", nativeName: "Українська", whisperCode: "uk", appleLocale: "uk_UA", recognitionStatus: .modelSupported, learningStatus: .experimental),
        .init(id: "pl", nativeName: "Polski", whisperCode: "pl", appleLocale: "pl_PL", recognitionStatus: .modelSupported, learningStatus: .experimental),
        .init(id: "tr", nativeName: "Türkçe", whisperCode: "tr", appleLocale: "tr_TR", recognitionStatus: .modelSupported, learningStatus: .experimental),
        .init(id: "ja", nativeName: "日本語", whisperCode: "ja", appleLocale: "ja_JP", recognitionStatus: .modelSupported, learningStatus: .experimental),
        .init(id: "ko", nativeName: "한국어", whisperCode: "ko", appleLocale: "ko_KR", recognitionStatus: .modelSupported, learningStatus: .experimental),
        .init(id: "ar", nativeName: "العربية", whisperCode: "ar", appleLocale: "ar_SA", isRightToLeft: true, recognitionStatus: .experimental, learningStatus: .experimental),
        .init(id: "he", nativeName: "עברית", whisperCode: "he", appleLocale: "he_IL", isRightToLeft: true, recognitionStatus: .experimental, learningStatus: .experimental),
        .init(id: "hi", nativeName: "हिन्दी", whisperCode: "hi", appleLocale: "hi_IN", recognitionStatus: .experimental, learningStatus: .experimental),
    ]

    public static func info(_ id: String) -> LanguageInfo? { all.first { $0.id == id } }

    /// Maps a Whisper language code back to the catalog id ("zh" → "zh-Hans").
    public static func fromWhisper(_ code: String) -> LanguageInfo? { all.first { $0.whisperCode == code } }

    /// English name used inside model instructions; models follow these more reliably than native names.
    public static func englishName(_ id: String) -> String {
        Locale(identifier: "en").localizedString(forIdentifier: id) ?? id
    }
}

/// Languages the interface itself is translated into. Only languages with a complete
/// string table belong here; the selector must never offer half-translated UIs.
public enum UILanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case system
    case en
    case ru
    case de
    case zhHans = "zh-Hans"

    public var id: String { rawValue }

    /// Shown in the selector in its own language, never as a flag.
    public var nativeName: String {
        switch self {
        case .system: "System"
        case .en: "English"
        case .ru: "Русский"
        case .de: "Deutsch"
        case .zhHans: "简体中文"
        }
    }

    public static var translated: [UILanguage] { allCases.filter { $0 != .system } }

    /// Resolves `.system` against the user's preferred languages, falling back to English.
    public func resolved(preferred: [String] = Locale.preferredLanguages) -> UILanguage {
        guard self == .system else { return self }
        for tag in preferred {
            let lower = tag.lowercased()
            if lower.hasPrefix("zh-hans") || lower == "zh" || lower.hasPrefix("zh-cn") || lower.hasPrefix("zh-sg") { return .zhHans }
            if lower.hasPrefix("zh") { continue } // Traditional Chinese is not translated yet.
            if let match = UILanguage.translated.first(where: { lower.hasPrefix($0.rawValue.lowercased()) }) { return match }
        }
        return .en
    }
}
