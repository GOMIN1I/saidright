import Foundation

/// What started a session; decides whether delivery into another app is allowed.
public enum SessionTrigger: String, Codable, Sendable {
    case hotkey, button, importedFile, retry
}

/// The field that was focused when recording started. Delivery is only attempted
/// into this destination; if focus moved, the text is kept and offered for copying.
public struct DestinationInfo: Equatable, Sendable {
    public var processID: Int32
    public var bundleID: String?
    public var appName: String
    /// Opaque token identifying the focused accessibility element (CFHash), if available.
    public var elementToken: Int?
    public var isSecureField: Bool

    public init(processID: Int32, bundleID: String?, appName: String, elementToken: Int?, isSecureField: Bool) {
        self.processID = processID
        self.bundleID = bundleID
        self.appName = appName
        self.elementToken = elementToken
        self.isSecureField = isSecureField
    }
}

public enum SessionPhase: Equatable, Sendable {
    case starting
    case recording
    case transcribing
    case editing
    case delivering
    case finished(DeliveryOutcome)
    case noSpeech
    case failed(String)
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .finished, .noSpeech, .failed, .cancelled: true
        default: false
        }
    }

    public var isBusy: Bool { !isTerminal }
}

public enum DeliveryOutcome: Equatable, Sendable {
    /// Text was found in the destination field after pasting.
    case insertedVerified(app: String)
    /// Paste was sent to the right app and field, but the app does not expose its contents.
    case insertedUnverified(app: String)
    /// Text is on the clipboard (by mode choice or as a fallback); reason explains why.
    case copied(reason: CopyReason)
    /// Mode keeps the text in the app.
    case kept
}

public enum CopyReason: String, Equatable, Sendable {
    case modeSetting
    /// Dictation was started inside Saywell, so there was no field to insert into.
    case startedInApp
    case focusChanged
    case noDestination
    case noPostPermission
    case secureInput
    case pasteNotConfirmed
}

/// Immutable description of a session fixed at start. Later mode edits never affect it.
public struct SessionSnapshot: Sendable {
    public let id: UUID
    public let mode: Mode
    public let trigger: SessionTrigger
    public let destination: DestinationInfo?
    public let startedAt: Date

    public init(id: UUID = UUID(), mode: Mode, trigger: SessionTrigger, destination: DestinationInfo?, startedAt: Date = Date()) {
        self.id = id
        self.mode = mode
        self.trigger = trigger
        self.destination = destination
        self.startedAt = startedAt
    }
}

/// Timing marks for one session, all relative to the same clock.
public struct SessionTiming: Codable, Equatable, Sendable {
    public var recordingStarted: Date?
    public var recordingEnded: Date?
    public var recognitionStarted: Date?
    public var recognitionEnded: Date?
    public var editingEnded: Date?
    public var delivered: Date?
    /// True when the recognizer had to load the model for this request.
    public var coldRecognizer = false

    public init() {}

    /// End of speech → text ready (before delivery). The number people feel.
    public var speechToText: TimeInterval? {
        guard let end = recordingEnded, let ready = editingEnded ?? recognitionEnded else { return nil }
        return ready.timeIntervalSince(end)
    }
    public var recognition: TimeInterval? {
        guard let a = recognitionStarted, let b = recognitionEnded else { return nil }
        return b.timeIntervalSince(a)
    }
    public var speechToDelivery: TimeInterval? {
        guard let end = recordingEnded, let done = delivered else { return nil }
        return done.timeIntervalSince(end)
    }
    public var audioDuration: TimeInterval? {
        guard let a = recordingStarted, let b = recordingEnded else { return nil }
        return b.timeIntervalSince(a)
    }
}

/// Guards the session lifecycle. Every asynchronous step reports back with its session id;
/// results for any session other than the current one are rejected, so a cancelled or
/// superseded request can never overwrite state, reset the UI or insert stale text.
public struct SessionMachine: Sendable {
    public private(set) var current: SessionSnapshot?
    public private(set) var phase: SessionPhase?

    public init() {}

    public var isBusy: Bool { phase?.isBusy ?? false }

    /// Begins a new session. Fails while another session is still active.
    public mutating func begin(_ snapshot: SessionSnapshot) -> Bool {
        if isBusy { return false }
        current = snapshot
        phase = .starting
        return true
    }

    public func isCurrent(_ id: UUID) -> Bool { current?.id == id }

    /// Applies a transition if `id` is current and the transition is legal.
    @discardableResult
    public mutating func advance(_ id: UUID, to next: SessionPhase) -> Bool {
        guard isCurrent(id), let phase, Self.allowed(from: phase, to: next) else { return false }
        self.phase = next
        return true
    }

    /// Cancels the current session. Returns its id so the caller can stop work tied to it.
    @discardableResult
    public mutating func cancel() -> UUID? {
        guard let current, let phase, !phase.isTerminal else { return nil }
        self.phase = .cancelled
        return current.id
    }

    static func allowed(from: SessionPhase, to: SessionPhase) -> Bool {
        if from.isTerminal { return false }
        switch (from, to) {
        case (_, .cancelled), (_, .failed): return true
        case (.starting, .recording), (.starting, .transcribing): return true
        case (.recording, .transcribing), (.recording, .noSpeech): return true
        case (.transcribing, .editing), (.transcribing, .delivering), (.transcribing, .noSpeech), (.transcribing, .finished): return true
        case (.editing, .delivering), (.editing, .finished): return true
        case (.delivering, .finished): return true
        default: return false
        }
    }
}
