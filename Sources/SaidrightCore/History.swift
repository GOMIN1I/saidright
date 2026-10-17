import Foundation

public struct DictationRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var modeName: String
    public var modeSymbol: String
    /// Recogniser output exactly as returned.
    public var raw: String
    /// Editor output when an edit was accepted.
    public var edited: String?
    /// Learning language when feedback exists.
    public var detectedLanguage: String?
    /// File name inside the recordings folder; nil when audio is not retained.
    public var audioFile: String?
    public var timing: SessionTiming
    /// Short machine-readable delivery summary ("insertedVerified", "copied:focusChanged"…).
    public var delivery: String
    /// The person checked (and possibly corrected) the transcript before analysis.
    public var transcriptConfirmed: Bool
    public var feedback: Feedback?
    public var editNote: String?

    public init(id: UUID, date: Date = Date(), modeName: String, modeSymbol: String, raw: String, edited: String?, detectedLanguage: String?, audioFile: String?, timing: SessionTiming, delivery: String, transcriptConfirmed: Bool = false, feedback: Feedback? = nil, editNote: String? = nil) {
        self.id = id
        self.date = date
        self.modeName = modeName
        self.modeSymbol = modeSymbol
        self.raw = raw
        self.edited = edited
        self.detectedLanguage = detectedLanguage
        self.audioFile = audioFile
        self.timing = timing
        self.delivery = delivery
        self.transcriptConfirmed = transcriptConfirmed
        self.feedback = feedback
        self.editNote = editNote
    }

    public var output: String { edited ?? raw }
}

/// What the person keeps. Audio and text are controlled independently.
public struct RetentionPolicy: Codable, Equatable, Sendable {
    public var keepText = true
    /// nil = until deleted by the person.
    public var textDays: Int? = nil
    public var keepAudio = true
    public var audioDays = 7
    public var maxRecords = 1000

    public init() {}
}

public enum VocabularyUse: String, Codable, CaseIterable, Sendable {
    /// Passed to Whisper as a context prompt. Biases recognition; not a guarantee.
    case recognitionHint
    /// Editor must keep this exact spelling.
    case protectSpelling
    /// Saved as a useful expression to review.
    case learning
}

public struct VocabularyEntry: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var term: String
    public var note: String
    public var uses: Set<VocabularyUse>

    public init(term: String, note: String = "", uses: Set<VocabularyUse>) {
        self.term = term
        self.note = note
        self.uses = uses
    }
}

public struct HistoryStore: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var schemaVersion = currentVersion
    public var records: [DictationRecord] = []
    public var cards: [ReviewCard] = []
    public var vocabulary: [VocabularyEntry] = []
    /// Set once the legacy Govori library has been imported, so it is never imported twice.
    public var importedLegacyAt: Date?

    public init() {}

    public mutating func upsert(_ record: DictationRecord) {
        if let i = records.firstIndex(where: { $0.id == record.id }) { records[i] = record } else { records.insert(record, at: 0) }
    }

    /// Applies retention and returns audio file names that must be deleted.
    public mutating func applyRetention(_ policy: RetentionPolicy, now: Date = Date()) -> [String] {
        var deleteAudio: [String] = []
        var kept: [DictationRecord] = []
        for var record in records.sorted(by: { $0.date > $1.date }) {
            let age = now.timeIntervalSince(record.date) / 86_400
            if let file = record.audioFile, !policy.keepAudio || age > Double(policy.audioDays) {
                deleteAudio.append(file)
                record.audioFile = nil
            }
            let textExpired = !policy.keepText || (policy.textDays.map { age > Double($0) } ?? false) || kept.count >= policy.maxRecords
            if textExpired {
                if let file = record.audioFile { deleteAudio.append(file) }
                continue
            }
            kept.append(record)
        }
        records = kept
        return deleteAudio
    }

    /// Topics from confirmed, undisputed learner errors with how often they occurred,
    /// and how many confirmed analyses they came from (the denominator).
    public func confirmedTopics() -> (topics: [(topic: String, count: Int)], analysedSessions: Int) {
        var counts: [String: Int] = [:]
        var sessions = 0
        for record in records where record.transcriptConfirmed {
            guard let feedback = record.feedback else { continue }
            sessions += 1
            for item in feedback.items where item.isConfirmedError(transcriptConfirmed: true) {
                let key = item.topic.isEmpty ? item.kind.rawValue : item.topic.lowercased()
                counts[key, default: 0] += 1
            }
        }
        return (counts.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }, sessions)
    }

    public var recognitionHints: [String] {
        vocabulary.filter { $0.uses.contains(.recognitionHint) }.map(\.term)
    }
}

/// Safe file names for recordings: "<UUID>.wav" only. Anything else is never deleted.
public enum RecordingFiles {
    public static func isOwnRecording(_ name: String) -> Bool {
        guard name.hasSuffix(".wav"), !name.contains("/"), !name.contains("..") else { return false }
        return UUID(uuidString: String(name.dropLast(4))) != nil
    }
}

// MARK: - Legacy Govori import

/// Reads the Govori 0.2 `library.json` without modifying it.
public enum LegacyImport {
    struct Correction: Decodable { var before: String; var after: String; var category: String; var explanation: String; var uncertain: Bool }
    struct Lesson: Decodable { var corrected: String; var corrections: [Correction]; var naturalAlternative: String; var tip: String; var exercise: String; var answer: String }
    struct Session: Decodable { var id: UUID; var date: Date; var mode: String; var raw: String; var corrected: String; var lesson: Lesson?; var audioPath: String?; var duration: Double; var recognitionTime: Double; var verified: Bool }
    struct Card: Decodable { var id: UUID; var question: String; var answer: String; var explanation: String; var due: Date; var interval: Int }
    struct Library: Decodable { var sessions: [Session]; var cards: [Card] }

    public struct Result: Sendable {
        public var records: [DictationRecord]
        public var cards: [ReviewCard]
        /// Absolute legacy audio paths to copy, keyed by the new file name.
        public var audioToCopy: [String: String]
    }

    public static func parse(_ data: Data, practiceName: String, dictationName: String) throws -> Result {
        let library = try JSONDecoder().decode(Library.self, from: data)
        var records: [DictationRecord] = []
        var audio: [String: String] = [:]
        for s in library.sessions {
            var timing = SessionTiming()
            timing.recordingStarted = s.date
            timing.recordingEnded = s.date.addingTimeInterval(s.duration)
            timing.recognitionStarted = timing.recordingEnded
            timing.recognitionEnded = timing.recordingEnded?.addingTimeInterval(s.recognitionTime)
            var feedback: Feedback?
            if let lesson = s.lesson {
                let items = lesson.corrections.map { c in
                    FeedbackItem(original: c.before, suggestion: c.after, kind: .grammar, explanation: c.explanation, rule: "", example: "", uncertain: c.uncertain, topic: c.category)
                }
                let practice = lesson.exercise.isEmpty ? nil : PracticeItem(kind: .gap, prompt: lesson.exercise, answer: lesson.answer)
                feedback = Feedback(corrected: lesson.corrected, items: items, alternative: lesson.naturalAlternative, practice: practice, learningLanguage: "en", explanationLanguage: "ru")
            }
            var file: String?
            if let path = s.audioPath {
                let name = UUID().uuidString + ".wav"
                audio[name] = path
                file = name
            }
            let practice = s.mode == "practice"
            records.append(DictationRecord(id: s.id, date: s.date, modeName: practice ? practiceName : dictationName, modeSymbol: practice ? "graduationcap" : "waveform", raw: s.raw, edited: s.corrected.isEmpty || s.lesson != nil ? nil : s.corrected, detectedLanguage: nil, audioFile: file, timing: timing, delivery: "imported", transcriptConfirmed: s.verified, feedback: feedback))
        }
        let cards = library.cards.map { c -> ReviewCard in
            var card = ReviewCard(language: "en", prompt: c.question, answer: c.answer, explanation: c.explanation, source: "", topic: "")
            card.id = c.id
            card.due = c.due
            card.intervalDays = Double(c.interval)
            return card
        }
        return Result(records: records, cards: cards, audioToCopy: audio)
    }
}
