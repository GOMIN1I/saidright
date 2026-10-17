import Foundation

/// How much the text editor may change a transcript. Each level has its own
/// instructions (see `EditorPrompt`) and its own integrity checks.
public enum CleanupLevel: String, Codable, CaseIterable, Sendable {
    /// No editor call at all. The recognizer may still normalise speech.
    case off
    /// Punctuation, capitalisation, accidental repetition and selected fillers.
    case light
    /// Light plus minimal grammar and unambiguous word choice; meaning unchanged.
    case correct
    /// Free reorganisation in a chosen tone; still no new facts.
    case rewrite

    public var usesEditor: Bool { self != .off }
}

public enum LearningLevel: String, Codable, CaseIterable, Sendable {
    case off
    /// One most useful point after dictation, shown in the app.
    case hint
    /// Full list of corrections after dictation, shown in the app.
    case detailed
    /// Nothing automatic; analysis runs only when asked.
    case onDemand

    public var runsAutomatically: Bool { self == .hint || self == .detailed }
}

public enum OutputAction: String, Codable, CaseIterable, Sendable {
    /// Insert into the field that was focused when recording started.
    case insert
    /// Put the text on the clipboard only.
    case copy
    /// Keep the text in the app (practice, drafts).
    case keep
}

public enum Tone: String, Codable, CaseIterable, Sendable {
    case keep, friendly, neutral, formal, concise
}

public enum RecognizerChoice: String, Codable, CaseIterable, Sendable {
    /// Local Whisper large-v3-turbo through MLX (Apple Silicon).
    case whisper
    /// Apple's on-device dictation model (macOS 26+), one language per mode.
    case appleDictation
    /// NVIDIA Parakeet TDT 0.6B v3 through MLX: much faster, 25 European languages, best with
    /// one language per recording (see ModelCatalog.parakeetFit).
    case parakeet
    /// Parakeet when installed and the mode has exactly one language it supports; otherwise
    /// Whisper. Mixed-language modes therefore always use Whisper.
    case auto

    /// The engine `auto` resolves to, given what is installed.
    public func resolved(spokenLanguages: [String], parakeetInstalled: Bool) -> RecognizerChoice {
        guard self == .auto else { return self }
        return parakeetInstalled && ModelCatalog.parakeetFit(spokenLanguages: spokenLanguages) == .good ? .parakeet : .whisper
    }
}

/// Detailed editor switches. They only apply when the level uses the editor.
public struct CleanupRules: Codable, Equatable, Sendable {
    public var removeFillers = true
    public var removeRepetitions = true
    public var keepProfanity = true
    public var keepSlang = true
    /// Turn spoken commands such as "new paragraph" or "bullet point" into formatting.
    public var spokenFormatting = false
    public var allowParagraphs = true
    /// Let the editor shape clearly structured dictation (tasks, steps, several items, separate
    /// topics) as Markdown: checklists, lists, short headings, tables. Prose stays prose.
    public var smartStructure = true

    public init() {}

    // Each field is optional so rules saved by older versions keep decoding (a failed decode
    // would replace the person's modes with the starter set).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CleanupRules()
        removeFillers = try c.decodeIfPresent(Bool.self, forKey: .removeFillers) ?? d.removeFillers
        removeRepetitions = try c.decodeIfPresent(Bool.self, forKey: .removeRepetitions) ?? d.removeRepetitions
        keepProfanity = try c.decodeIfPresent(Bool.self, forKey: .keepProfanity) ?? d.keepProfanity
        keepSlang = try c.decodeIfPresent(Bool.self, forKey: .keepSlang) ?? d.keepSlang
        spokenFormatting = try c.decodeIfPresent(Bool.self, forKey: .spokenFormatting) ?? d.spokenFormatting
        allowParagraphs = try c.decodeIfPresent(Bool.self, forKey: .allowParagraphs) ?? d.allowParagraphs
        smartStructure = try c.decodeIfPresent(Bool.self, forKey: .smartStructure) ?? d.smartStructure
    }
}

public struct Mode: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// SF Symbol name. Modes are also distinguished by name and position, never by colour alone.
    public var symbol: String
    /// Catalog ids. Empty means "detect any language". One entry fixes the language.
    /// Several entries restrict language detection to that set and keep code switching.
    public var spokenLanguages: [String]
    public var recognizer: RecognizerChoice
    public var cleanup: CleanupLevel
    public var rules: CleanupRules
    public var tone: Tone
    public var learning: LearningLevel
    /// Language being learned. Feedback only concerns passages in this language.
    public var learningLanguage: String
    /// nil = same as the interface language.
    public var explanationLanguage: String?
    public var output: OutputAction
    /// Advanced: extra rules appended to the built-in instructions (never replacing them).
    public var extraInstructions: String
    /// Which starter preset this mode came from, for "reset to preset".
    public var presetID: String?

    public init(id: UUID = UUID(), name: String, symbol: String, spokenLanguages: [String], recognizer: RecognizerChoice = .auto, cleanup: CleanupLevel, rules: CleanupRules = .init(), tone: Tone = .keep, learning: LearningLevel, learningLanguage: String = "en", explanationLanguage: String? = nil, output: OutputAction, extraInstructions: String = "", presetID: String? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.spokenLanguages = spokenLanguages
        self.recognizer = recognizer
        self.cleanup = cleanup
        self.rules = rules
        self.tone = tone
        self.learning = learning
        self.learningLanguage = learningLanguage
        self.explanationLanguage = explanationLanguage
        self.output = output
        self.extraInstructions = extraInstructions
        self.presetID = presetID
    }

    /// True when processing this mode can contact a text provider without an explicit user action.
    public var needsProviderAutomatically: Bool { cleanup.usesEditor || learning.runsAutomatically }
}

public enum ModePresets {
    public static let originalID = "original"
    public static let messageID = "message"
    public static let promptID = "prompt"
    public static let practiceID = "practice"

    /// Starter modes. Names are stored as plain strings once created so people can rename them;
    /// the app passes localized names in.
    public static func starter(names: [String: String], spoken: [String]) -> [Mode] {
        var light = CleanupRules()
        light.removeFillers = true
        var practiceRules = CleanupRules()
        practiceRules.removeFillers = false
        return [
            Mode(name: names[messageID] ?? "Message", symbol: "bubble.left", spokenLanguages: spoken, cleanup: .light, rules: light, learning: .off, output: .insert, presetID: messageID),
            Mode(name: names[promptID] ?? "Prompt", symbol: "text.cursor", spokenLanguages: spoken, cleanup: .correct, learning: .hint, output: .insert, presetID: promptID),
            Mode(name: names[originalID] ?? "Original", symbol: "waveform", spokenLanguages: spoken, cleanup: .off, learning: .off, output: .insert, presetID: originalID),
            Mode(name: names[practiceID] ?? "Practice", symbol: "graduationcap", spokenLanguages: ["en"], cleanup: .off, rules: practiceRules, learning: .detailed, output: .keep, presetID: practiceID),
        ]
    }

    /// Restores behaviour from the preset while keeping identity, name and languages.
    public static func reset(_ mode: Mode) -> Mode {
        guard let preset = mode.presetID, let template = starter(names: [:], spoken: mode.spokenLanguages).first(where: { $0.presetID == preset }) else { return mode }
        var copy = template
        copy.id = mode.id
        copy.name = mode.name
        copy.symbol = mode.symbol
        copy.spokenLanguages = mode.spokenLanguages
        copy.learningLanguage = mode.learningLanguage
        return copy
    }
}

/// Persisted collection of modes with a schema version for migrations.
public struct ModeLibrary: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var schemaVersion: Int
    public var modes: [Mode]
    public var activeModeID: UUID?

    public init(modes: [Mode], activeModeID: UUID? = nil) {
        self.schemaVersion = Self.currentVersion
        self.modes = modes
        self.activeModeID = activeModeID ?? modes.first?.id
    }

    public var active: Mode? { modes.first { $0.id == activeModeID } ?? modes.first }

    public mutating func setActive(_ id: UUID) { if modes.contains(where: { $0.id == id }) { activeModeID = id } }

    /// Cycles to the next mode, used by the quick-switch shortcut.
    public mutating func activateNext() {
        guard !modes.isEmpty else { return }
        let index = modes.firstIndex { $0.id == activeModeID } ?? -1
        activeModeID = modes[(index + 1) % modes.count].id
    }

    @discardableResult
    public mutating func duplicate(_ id: UUID, suffix: String) -> Mode? {
        guard let index = modes.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = modes[index]
        copy.id = UUID()
        copy.name = uniqueName(copy.name + " " + suffix)
        modes.insert(copy, at: index + 1)
        return copy
    }

    /// The last mode cannot be deleted: dictation always needs an active mode.
    @discardableResult
    public mutating func delete(_ id: UUID) -> Bool {
        guard modes.count > 1, let index = modes.firstIndex(where: { $0.id == id }) else { return false }
        modes.remove(at: index)
        if activeModeID == id { activeModeID = modes[min(index, modes.count - 1)].id }
        return true
    }

    public mutating func update(_ mode: Mode) {
        guard let index = modes.firstIndex(where: { $0.id == mode.id }) else { return }
        var value = mode
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.name.isEmpty { value.name = modes[index].name }
        modes[index] = value
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { modes[$0] }
        var remaining = modes.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: max(0, min(insertAt, remaining.count)))
        modes = remaining
    }

    public func uniqueName(_ base: String) -> String {
        var name = base
        var n = 2
        while modes.contains(where: { $0.name == name }) { name = "\(base) \(n)"; n += 1 }
        return name
    }

    // MARK: Export / import

    /// Export format for sharing modes. Modes contain no credentials or transcripts by construction;
    /// this wrapper exists so a future field cannot leak silently.
    public struct Export: Codable, Sendable {
        public var format = "saidright.modes"
        public var version = 1
        public var modes: [Mode]
    }

    public func export(_ ids: [UUID]) throws -> Data {
        let chosen = modes.filter { ids.contains($0.id) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Export(modes: chosen))
    }

    /// Imports modes with fresh identifiers so an import can never overwrite existing modes.
    @discardableResult
    public mutating func importModes(from data: Data) throws -> [Mode] {
        let payload = try JSONDecoder().decode(Export.self, from: data)
        // "saywell.modes": files exported before the app was renamed.
        guard payload.format == "saidright.modes" || payload.format == "saywell.modes" else { throw CoreError.invalidFormat }
        var added: [Mode] = []
        for var mode in payload.modes.prefix(32) {
            mode.id = UUID()
            mode.name = uniqueName(String(mode.name.prefix(60)))
            mode.extraInstructions = String(mode.extraInstructions.prefix(4000))
            modes.append(mode)
            added.append(mode)
        }
        return added
    }
}

public enum CoreError: Error, Equatable {
    case invalidFormat
    case unsupportedVersion(Int)
}
