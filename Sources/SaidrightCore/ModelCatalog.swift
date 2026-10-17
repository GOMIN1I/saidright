import Foundation

/// Speech recognition models Saidright can actually run. Every entry here is installable and
/// usable in this build; candidates that need more work live in docs/MODELS_AND_LICENSES.md.
public struct SpeechModel: Identifiable, Equatable, Sendable {
    public enum Engine: String, Sendable { case whisperMLX, parakeetMLX, appleOnDevice }

    public var id: String
    public var engine: Engine
    /// Hugging Face repository and pinned revision (Whisper only).
    public var repo: String?
    public var revision: String?
    /// Folder under Saidright/Models.
    public var folder: String?
    /// Download size from the repository metadata at the pinned revision.
    public var downloadBytes: Int64
    /// Rough working memory while loaded. An estimate, labelled as such in the UI.
    public var memoryEstimateBytes: Int64
    /// 1 (lowest) … 3 (highest); relative to the other entries, not a benchmark.
    public var quality: Int
    public var speed: Int
    /// Mixed-language dictation (e.g. Russian with English terms) in one recording.
    public var handlesMixedLanguages: Bool
    /// Verified on this project's synthetic RU/EN/DE/ZH set.
    public var testedHere: Bool
    /// Catalog language ids the model supports; nil = Whisper's broad set.
    public var languages: [String]? = nil
}

/// How well Parakeet suits a mode's spoken languages.
public enum ModelFit: Equatable, Sendable {
    /// One supported language: the best case.
    case good
    /// Several supported languages: fine when a recording stays in one of them; a switch
    /// inside one recording can be dropped or transliterated (measured, see docs).
    case switchesRisky
    /// A language it does not support, or detection left open.
    case unsupported([String])
}

public enum ModelCatalog {
    public static let whisperTurbo = SpeechModel(
        id: "whisper-large-v3-turbo", engine: .whisperMLX,
        repo: "mlx-community/whisper-large-v3-turbo", revision: "a4aaeec0636e6fef84abdcbe3544cb2bf7e9f6fb", folder: "whisper-large-v3-turbo",
        downloadBytes: 1_614_000_000, memoryEstimateBytes: 2_200_000_000, quality: 3, speed: 2, handlesMixedLanguages: true, testedHere: true)

    public static let whisperSmall = SpeechModel(
        id: "whisper-small", engine: .whisperMLX,
        repo: "mlx-community/whisper-small-mlx", revision: "45f3915923c7a79a5a5b5a7d909d39aeb0e5630e", folder: "whisper-small",
        downloadBytes: 481_000_000, memoryEstimateBytes: 900_000_000, quality: 1, speed: 3, handlesMixedLanguages: true, testedHere: false)

    /// NVIDIA Parakeet TDT 0.6B v3 (CC-BY-4.0), MLX conversion. Languages from the official model card.
    public static let parakeet = SpeechModel(
        id: "parakeet-tdt-0.6b-v3", engine: .parakeetMLX,
        repo: "mlx-community/parakeet-tdt-0.6b-v3", revision: "ed2b7e8c15f9aaa0b5772e2efb986255eaef7e15", folder: "parakeet-tdt-0.6b-v3",
        downloadBytes: 2_508_000_000, memoryEstimateBytes: 1_200_000_000, quality: 3, speed: 3, handlesMixedLanguages: false, testedHere: true,
        languages: ["bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it", "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk"])

    public static let appleSpeech = SpeechModel(
        id: "apple-on-device", engine: .appleOnDevice, repo: nil, revision: nil, folder: nil,
        downloadBytes: 0, memoryEstimateBytes: 0, quality: 2, speed: 3, handlesMixedLanguages: false, testedHere: true)

    public static let all = [whisperTurbo, parakeet, whisperSmall, appleSpeech]
    public static var whisper: [SpeechModel] { all.filter { $0.engine == .whisperMLX } }

    public static func model(_ id: String) -> SpeechModel? { all.first { $0.id == id } }

    public static func parakeetFit(spokenLanguages: [String]) -> ModelFit {
        let supported = Set(parakeet.languages ?? [])
        let missing = spokenLanguages.filter { !supported.contains($0) }
        if spokenLanguages.isEmpty { return .unsupported([]) }
        if !missing.isEmpty { return .unsupported(missing) }
        return spokenLanguages.count == 1 ? .good : .switchesRisky
    }

    /// The Whisper model to suggest for a Mac and the languages a person speaks.
    /// Mixed or non-English dictation needs the large model; the small one is offered for
    /// English-only use on Macs with little memory, where it loads faster and leaves room.
    public static func recommendedWhisper(spokenLanguages: [String], physicalMemory: UInt64) -> SpeechModel {
        let englishOnly = spokenLanguages == ["en"]
        let lowMemory = physicalMemory < 12 * 1_073_741_824
        return englishOnly && lowMemory ? whisperSmall : whisperTurbo
    }
}
