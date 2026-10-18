import AppKit
import Observation
import SaidrightCore

/// What the main window shows about the latest dictation.
struct SessionResult: Equatable {
    var recordID: UUID
    var modeName: String
    var raw: String
    var edited: String?
    var output: String
    var outcome: DeliveryOutcome?
    var editFailure: EditFailure?
    var editIssues: [IntegrityReport.Issue]
    var destination: DestinationInfo?
    var languages: [String]
    var timing: SessionTiming
    var feedback: Feedback?
    var feedbackState: FeedbackState
    var learningLevel: LearningLevel
    var learningLanguage: String
    var audioFile: String?
    var transcriptConfirmed = false

    enum FeedbackState: Equatable { case none, running, ready, failed(String), skippedNoProvider }
}

enum RecognizerState: Equatable {
    case notInstalled
    case installing(stage: String, fraction: Double?)
    case loading
    case ready
    case failed(String)
}

/// A dismissible message with an optional action.
struct Notice: Equatable, Identifiable {
    enum Action: Equatable { case openPermissions, openRecognizer, openProvider, retryEdit, none }
    var id = UUID()
    var text: String
    var action: Action = .none
    var isError = true
}

@MainActor @Observable final class AppModel {
    // MARK: Stored state
    var settings: AppSettings { didSet { if settings != oldValue { settingsChanged(from: oldValue) } } }
    var modes: ModeLibrary { didSet { if modes != oldValue { JSONFile.save(modes, to: "modes.json"); if modes.modes.map(\.recognizer) != oldValue.modes.map(\.recognizer) { warmUpParakeetIfUsed() } } } }
    private(set) var history: HistoryStore

    // MARK: Live state
    private(set) var phase: SessionPhase? { didSet { hotkeys.sessionActive = phase?.isBusy ?? false } }
    private(set) var recordingStarted: Date?
    private(set) var result: SessionResult?
    private(set) var recognizer: RecognizerState = .notInstalled
    private(set) var hotkeyStatus = HotkeyService.Status()
    var notice: Notice?
    private(set) var inputDevices: [InputDevice] = []
    /// Shown while a "press your key" test runs in settings/onboarding.
    var keyTestPassed = false
    var hasCredential = false

    // MARK: Services
    let permissions = Permissions()
    let capsule = CapsuleModel()
    let speech = SpeechService()
    private let hotkeys = HotkeyService()
    private let recorder = AudioRecorder()
    private let whisper = WhisperEngine()
    /// A second resident worker for modes that use Parakeet; started only when such a mode is used.
    private let parakeet = WhisperEngine()
    private let delivery = TextDelivery()
    private var capsuleController: CapsuleController?
    private var machine = SessionMachine()
    private var sessionTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var timing = SessionTiming()
    private var maxDurationTimer: Timer?
    private var aheadTimer: Timer?
    private var aheadRunning = false
    /// Seconds of the current recording already recognised ahead (for the session log).
    private var aheadSeconds = 0.0
    private var capsuleDelay: Task<Void, Never>?
    static let maxRecordingSeconds: TimeInterval = 600
    private var unexpectedExits: [Date] = []
    /// For dictations started from Saidright's own window: where "Insert into …" will paste.
    private var offerDestination: DestinationInfo?

    init() {
        Paths.prepare()
        let settingsData = JSONFile.data("settings.json")
        let loadedSettings = settingsData.map(AppSettings.decode) ?? AppSettings()
        settings = loadedSettings
        Localizer.shared.load(directory: Bundle.main.resourceURL ?? Bundle.main.bundleURL)
        Localizer.shared.setLanguage(loadedSettings.uiLanguage)
        Self.applyProcessLanguage(loadedSettings.uiLanguage)

        if let saved = JSONFile.load(ModeLibrary.self, from: "modes.json"), !saved.modes.isEmpty {
            modes = saved
        } else {
            if JSONFile.data("modes.json") != nil { JSONFile.quarantine("modes.json") }
            modes = ModeLibrary(modes: ModePresets.starter(names: Self.presetNames(), spoken: Self.defaultSpokenLanguages()))
        }
        if let saved = JSONFile.load(HistoryStore.self, from: "history.json") {
            history = saved
        } else {
            if JSONFile.data("history.json") != nil { JSONFile.quarantine("history.json") }
            history = HistoryStore()
        }
        JSONFile.save(settings, to: "settings.json")
        JSONFile.save(modes, to: "modes.json")

        importLegacyIfNeeded()
        applyRetention()
        localizePresetNames()
        hasCredential = Keychain.exists(settings.provider.credentialAccount)

        WhisperInstallation.selected = ModelCatalog.model(settings.whisperModel) ?? ModelCatalog.whisperTurbo
        capsuleController = CapsuleController(model: capsule)
        capsule.apply(settings.capsule)
        capsule.hintLinger = settings.learningUI.linger.seconds
        capsule.onSaveItem = { [weak self] record, item in self?.saveForReview(item, record: record) }
        capsule.onVerdict = { [weak self] record, item, verdict in self?.setVerdict(verdict, for: item, record: record) }
        capsule.onOpenApp = { _ in WindowRouter.show("main") }
        capsule.onApplyCorrection = { [weak self] record in self?.applyCorrection(record, strict: false) }
        applyAppearance()
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in try? await Task.sleep(for: .milliseconds(100)); self?.applyAppearance() }
        }
        recorder.onLevel = { [weak self] level in self?.capsule.push(level: level) }
        recorder.onInterruption = { [weak self] in self?.inputInterrupted() }
        hotkeys.onEvent = { [weak self] event in self?.handleHotkey(event) }
        hotkeys.onStatusChange = { [weak self] status in self?.hotkeyStatus = status }
        hotkeys.onTargetKeySeen = { [weak self] in self?.keyTestPassed = true }
        // QA instances (SAIDRIGHT_QA_OPEN) never listen to the keyboard, so they cannot react to
        // the person's own key presses while a regular Saidright is running.
        if !Self.isQAInstance {
            hotkeys.apply(settings.hotkeys)
            permissions.onChange = { [weak self] in self?.hotkeys.installTapIfPossible() }
        }
        refreshDevices()
        AudioRecorder.observeDeviceChanges { [weak self] in Task { @MainActor in self?.refreshDevices() } }
        whisper.onUnexpectedExit = { [weak self] in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                guard let self, !self.isBusy else { return }
                // Avoid a crash loop (e.g. out of memory): at most two automatic restarts per 5 minutes.
                let now = Date()
                self.unexpectedExits = self.unexpectedExits.filter { now.timeIntervalSince($0) < 300 } + [now]
                guard self.unexpectedExits.count <= 2 else {
                    self.recognizer = .failed(tr("error.workerStopped"))
                    return
                }
                Log.info("recognizer exited unexpectedly; warming up again")
                self.warmUpRecognizer()
            }
        }
        warmUpRecognizer()
    }

    static let isQAInstance = ProcessInfo.processInfo.environment["SAIDRIGHT_QA_OPEN"] != nil

    static func presetNames() -> [String: String] {
        [ModePresets.messageID: tr("preset.message"), ModePresets.promptID: tr("preset.prompt"), ModePresets.originalID: tr("preset.original"), ModePresets.practiceID: tr("preset.practice")]
    }

    static func defaultSpokenLanguages() -> [String] {
        var result: [String] = []
        for tag in Locale.preferredLanguages {
            let code = String(tag.prefix(2))
            let id = code == "zh" ? "zh-Hans" : code
            if LanguageCatalog.info(id) != nil, !result.contains(id) { result.append(id) }
        }
        if !result.contains("en") { result.append("en") }
        return Array(result.prefix(3))
    }

    // MARK: Derived

    var activeMode: Mode { modes.active ?? ModePresets.starter(names: [:], spoken: [])[0] }
    var isRecording: Bool { phase == .recording }
    var isBusy: Bool { phase?.isBusy ?? false }

    var statusLine: String {
        switch phase {
        case .starting: return tr("status.starting")
        case .recording: return tr("status.recording")
        case .transcribing: return tr("status.transcribing")
        case .editing: return tr("status.editing")
        case .delivering: return tr("status.delivering")
        case .finished(let outcome)?: return Self.describe(outcome)
        case .noSpeech: return tr("status.noSpeech")
        case .failed(let message)?: return message
        case .cancelled: return tr("status.cancelled")
        case nil:
            switch recognizer {
            case .notInstalled: return tr("status.recognizerMissing")
            case .installing: return tr("status.installing")
            case .loading: return tr("status.loading")
            case .failed(let message): return message
            case .ready: return tr("status.ready")
            }
        }
    }

    static func describe(_ outcome: DeliveryOutcome) -> String {
        switch outcome {
        case .insertedVerified(let app): return tr("delivery.verified", app)
        case .insertedUnverified(let app): return tr("delivery.unverified", app)
        case .kept: return tr("delivery.kept")
        case .copied(let reason):
            switch reason {
            case .modeSetting: return tr("delivery.copied")
            case .startedInApp: return tr("delivery.startedInApp")
            case .focusChanged: return tr("delivery.focusChanged")
            case .noDestination: return tr("delivery.noDestination")
            case .noPostPermission: return tr("delivery.noPermission")
            case .secureInput: return tr("delivery.secureInput")
            case .pasteNotConfirmed: return tr("delivery.notConfirmed")
            }
        }
    }

    // MARK: Hotkeys

    private func handleHotkey(_ event: HotkeyService.Event) {
        switch event {
        case .toggle:
            if phase == .recording { stopRecording() }
            else if isBusy { capsule.nudge() }
            else { startRecording(trigger: .hotkey, provisional: false) }
        case .holdBegan:
            if !isBusy { startRecording(trigger: .hotkey, provisional: true) }
        case .holdEnded:
            if phase == .recording { stopRecording() } else if phase == .starting { cancel(silently: true) }
        case .holdCancelled:
            if phase == .recording || phase == .starting { cancel(silently: true) }
        case .cancel:
            if isBusy { cancel() }
        case .lastTip:
            toggleLastTip()
        case .switchMode:
            guard !isBusy else { return }
            modes.activateNext()
            capsule.flashMode(activeMode.name, symbol: activeMode.symbol)
        }
    }

    /// QA only: a hotkey-style session that stops itself after `seconds`.
    func qaDictate(seconds: Double) {
        startRecording(trigger: .hotkey)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            MainActor.assumeIsolated { self?.stopRecording() }
        }
    }

    // MARK: Session lifecycle

    /// Starts recording for the active mode. `provisional` hides the capsule briefly so a
    /// press that turns into a shortcut leaves no visual trace.
    func startRecording(trigger: SessionTrigger, provisional: Bool = false) {
        guard !isBusy else { return }
        notice = nil
        let mode = activeMode
        if let problem = recognizerProblem(for: mode) { notice = problem; NSApp.sendAction(#selector(AppDelegate.showMainWindow), to: nil, from: nil); return }
        switch recorder.usesTestAudio ? .granted : permissions.microphone {
        case .notDetermined:
            Task { if await permissions.requestMicrophone() { notice = Notice(text: tr("notice.micGrantedPressAgain"), isError: false) } }
            return
        case .denied:
            notice = Notice(text: tr("notice.micDenied"), action: .openPermissions)
            NSApp.sendAction(#selector(AppDelegate.showMainWindow), to: nil, from: nil)
            return
        case .granted:
            break
        }
        let destination = trigger == .hotkey ? delivery.captureDestination() : nil
        let fallbackDestination = trigger == .button ? delivery.lastExternalDestination() : nil
        let snapshot = SessionSnapshot(mode: mode, trigger: trigger, destination: destination)
        guard machine.begin(snapshot) else { return }
        offerDestination = fallbackDestination
        phase = machine.phase
        let recordingURL: URL
        do {
            recordingURL = try recorder.start(deviceUID: settings.inputDeviceUID)
        } catch {
            fail(snapshot.id, message: Self.message(for: error))
            return
        }
        timing = SessionTiming()
        timing.recordingStarted = Date()
        recordingStarted = timing.recordingStarted
        advance(snapshot.id, .recording)
        startRecognizingAhead(recordingURL, mode: mode)
        if mode.cleanup.usesEditor || mode.learning.runsAutomatically {
            let provider = provider
            Task.detached(priority: .utility) { await TextProvider.warmUp(provider) }
        }
        Sound.play(.start, enabled: settings.playSounds)
        capsule.modeName = mode.name
        capsule.modeSymbol = mode.symbol
        capsuleDelay?.cancel()
        if provisional {
            capsuleDelay = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(220))
                guard let self, !Task.isCancelled, self.machine.isCurrent(snapshot.id), self.phase == .recording else { return }
                self.capsule.show(.recording)
            }
        } else {
            capsule.show(.recording)
        }
        maxDurationTimer?.invalidate()
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: Self.maxRecordingSeconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { if self?.phase == .recording { self?.stopRecording() } }
        }
    }

    func stopRecording() {
        guard phase == .recording, let snapshot = machine.current else { return }
        maxDurationTimer?.invalidate()
        aheadTimer?.invalidate()
        capsuleDelay?.cancel()
        guard let recording = recorder.stop() else { fail(snapshot.id, message: tr("error.recordingLost")); return }
        timing.recordingEnded = Date()
        let tooShort = recording.duration < 0.3
        let silent = recording.voicedSeconds < 0.12 && recording.peakDB < -50
        if tooShort || silent {
            Log.info("no speech: audio=\(String(format: "%.1f", recording.duration))s voiced=\(String(format: "%.2f", recording.voicedSeconds))s peak=\(Int(recording.peakDB))dB")
            try? FileManager.default.removeItem(at: recording.url)
            advance(snapshot.id, .noSpeech)
            capsule.show(.noSpeech)
            return
        }
        advance(snapshot.id, .transcribing)
        capsule.show(.processing)
        sessionTask = Task { [weak self] in
            await self?.process(snapshot, recording: recording)
        }
    }

    /// Cancels the active session. Late results of this session are ignored by id.
    func cancel(silently: Bool = false) {
        guard let id = machine.cancel() else { return }
        _ = id
        maxDurationTimer?.invalidate()
        aheadTimer?.invalidate()
        capsuleDelay?.cancel()
        recorder.discard()
        sessionTask?.cancel()
        whisper.abandonAll()
        parakeet.abandonAll()
        phase = machine.phase
        if silently { capsule.hide() } else { capsule.show(.cancelled) }
    }

    private func process(_ snapshot: SessionSnapshot, recording: AudioRecorder.Result) async {
        let id = snapshot.id
        let mode = snapshot.mode
        let fileName = recording.url.lastPathComponent
        timing.recognitionStarted = Date()

        // 1. Recognition
        let transcript: Transcript
        do {
            transcript = try await recognize(recording.url, mode: mode, seconds: recording.duration)
        } catch is CancellationError {
            return
        } catch {
            guard machine.isCurrent(id) else { return }
            // Keep the audio so recognition can be retried without speaking again.
            fail(id, message: Self.message(for: error))
            saveRecord(id: id, mode: mode, raw: "", edit: nil, languages: [], audioFile: fileName, delivery: "recognitionFailed")
            return
        }
        guard machine.isCurrent(id), !Task.isCancelled else { try? FileManager.default.removeItem(at: recording.url); return }
        timing.recognitionEnded = Date()
        timing.coldRecognizer = transcript.cold
        let raw = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            try? FileManager.default.removeItem(at: recording.url)
            advance(id, .noSpeech)
            capsule.show(.noSpeech)
            return
        }

        // 2. Optional editing. With cleanup off, no provider is contacted.
        var edit = EditResult(output: raw, edited: nil, issues: [], failure: nil)
        // Instant insert: the transcript goes in right away and the edit replaces it later.
        var firstOutcome: DeliveryOutcome?
        var firstInserted: Date?
        if mode.cleanup.usesEditor {
            advance(id, .editing)
            // Lists are written as Markdown only for apps that show it (TextFlavor).
            let flavor = mode.output == .insert && snapshot.trigger == .hotkey ? TextFlavor.forApp(bundleID: snapshot.destination?.bundleID) : .markdown
            if settings.instantInsert, mode.output == .insert, snapshot.trigger == .hotkey, snapshot.destination != nil {
                let editing = Task { await TextPipeline.edit(raw: raw, mode: mode, flavor: flavor, provider: { try self.makeProvider() }) }
                firstOutcome = await delivery.deliver(raw, to: snapshot.destination, restoreClipboard: settings.restoreClipboard)
                firstInserted = Date()
                edit = await editing.value
            } else {
                edit = await TextPipeline.edit(raw: raw, mode: mode, flavor: flavor, provider: { try self.makeProvider() })
            }
            guard machine.isCurrent(id), !Task.isCancelled else { return }
        }
        timing.editingEnded = Date()

        // 3. Delivery: only the intended text, never explanations.
        advance(id, .delivering)
        let outcome: DeliveryOutcome
        switch mode.output {
        case .insert:
            // Formatted-text apps also get HTML: a real table and real lists (RichText).
            let html = TextFlavor.wantsRichText(bundleID: snapshot.destination?.bundleID) && RichText.hasLayout(edit.output) ? RichText.html(edit.output) : nil
            if let first = firstOutcome, let destination = snapshot.destination {
                if !first.isInsertion {
                    delivery.copy(edit.output)
                } else if edit.output != raw, !(await delivery.replaceDelivered(raw, with: edit.output, html: html, destination: destination, restoreClipboard: settings.restoreClipboard)) {
                    // Something changed in the field: the transcript stays, the edit is in the result.
                    notice = Notice(text: tr("notice.instantKept"), action: .none)
                    edit.output = raw
                }
                outcome = first
            } else if snapshot.trigger == .hotkey, snapshot.destination != nil {
                outcome = await delivery.deliver(edit.output, html: html, to: snapshot.destination, restoreClipboard: settings.restoreClipboard)
            } else {
                delivery.copy(edit.output)
                outcome = .copied(reason: snapshot.trigger == .hotkey ? .noDestination : .startedInApp)
            }
        case .copy:
            delivery.copy(edit.output)
            outcome = .copied(reason: .modeSetting)
        case .keep:
            outcome = .kept
        }
        guard machine.isCurrent(id) else { return }
        timing.delivered = Date()
        advance(id, .finished(outcome))
        capsule.show(outcome.isInsertion ? .done : .doneElsewhere)
        Sound.play(.done, enabled: settings.playSounds)

        let keepAudio = settings.retention.keepAudio && settings.retention.keepText
        if !keepAudio { try? FileManager.default.removeItem(at: recording.url) }
        result = SessionResult(recordID: id, modeName: mode.name, raw: raw, edited: edit.edited, output: edit.output, outcome: outcome, editFailure: edit.failure, editIssues: edit.issues, destination: snapshot.destination ?? offerDestination, languages: transcript.languages, timing: timing, feedback: nil, feedbackState: .none, learningLevel: mode.learning, learningLanguage: mode.learningLanguage, audioFile: keepAudio ? fileName : nil)
        if let failure = edit.failure { reportEditFailure(failure) }
        saveRecord(id: id, mode: mode, raw: raw, edit: edit, languages: transcript.languages, audioFile: keepAudio ? fileName : nil, delivery: outcome.code)
        Log.info("session done audio=\(String(format: "%.1f", recording.duration))s asr=\(String(format: "%.2f", timing.recognition ?? 0))s ready=\(String(format: "%.2f", timing.speechToText ?? 0))s delivered=\(String(format: "%.2f", timing.speechToDelivery ?? 0))s ahead=\(String(format: "%.1f", aheadSeconds))s\(firstInserted.map { String(format: " first=%.2fs", $0.timeIntervalSince(timing.recordingEnded ?? $0)) } ?? "") cold=\(transcript.cold) outcome=\(outcome.code)")

        // 4. Optional learning feedback. The text is already delivered; the hint, if any,
        //    arrives in the capsule later and never needs the main window.
        if mode.learning.runsAutomatically { requestFeedback(automatic: true) }
        if mode.output == .keep {
            NSApp.sendAction(#selector(AppDelegate.showMainWindow), to: nil, from: nil)
        }
    }

    /// Shows editing failures that need attention. Setup gaps are shown persistently elsewhere.
    private func reportEditFailure(_ failure: EditFailure) {
        // Missing key / local-only is already explained next to the record button and in the mode summary.
        if failure.isProviderSetup { return }
        notice = Notice(text: Self.message(for: failure), action: failure.isProviderSetup ? .openProvider : .retryEdit)
    }

    /// True when a mode's automatic editing or learning cannot run with the current provider setup.
    func providerUnavailable(for mode: Mode) -> Bool {
        guard mode.needsProviderAutomatically else { return false }
        if provider.localOnly && !provider.isOnDevice { return true }
        if provider.requiresCredential && !hasCredential { return true }
        return false
    }

    /// The engine a mode actually uses now (`auto` decided by languages and what is installed).
    func engine(for mode: Mode) -> RecognizerChoice {
        mode.recognizer.resolved(spokenLanguages: mode.spokenLanguages, parakeetInstalled: ParakeetInstallation.current() != nil)
    }

    private func recognize(_ url: URL, mode: Mode, seconds: Double) async throws -> Transcript {
        switch engine(for: mode) {
        case .auto: throw RecognizerError.runtimeMissing // resolved above; never reached
        case .whisper:
            guard let installation = WhisperInstallation.current() else { throw RecognizerError.runtimeMissing }
            return try await whisper.transcribe(url, languages: mode.spokenLanguages, prompt: recognitionPrompt, audioSeconds: seconds, installation: installation)
        case .appleDictation:
            guard let language = mode.spokenLanguages.first else { throw RecognizerError.unsupportedLanguage("auto") }
            return try await AppleDictation.transcribe(url, languageID: language)
        case .parakeet:
            guard let installation = ParakeetInstallation.current() else { throw RecognizerError.runtimeMissing }
            // Parakeet takes no vocabulary prompt; languages only label the result. It spells
            // numbers out, so they are written as digits here, as Whisper does.
            var transcript = try await parakeet.transcribe(url, languages: mode.spokenLanguages, prompt: nil, audioSeconds: seconds, installation: installation.asWorkerInstallation)
            transcript.text = NumberNormalizer.digits(transcript.text)
            return transcript
        }
    }

    /// Vocabulary the person confirmed, passed to Whisper as context.
    private var recognitionPrompt: String? { history.recognitionHints.isEmpty ? nil : history.recognitionHints.prefix(40).joined(separator: ", ") }

    /// Long dictations: Whisper recognises finished phrases while the person still speaks, so
    /// after the stop only the last part is left (docs/RECOGNITION.md → Recognition ahead).
    /// Reads the WAV being written; the recorder itself is untouched.
    private func startRecognizingAhead(_ url: URL, mode: Mode) {
        aheadTimer?.invalidate()
        aheadSeconds = 0
        guard engine(for: mode) == .whisper, let installation = WhisperInstallation.current() else { return }
        aheadTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.phase == .recording, !self.aheadRunning,
                      let started = self.timing.recordingStarted, Date().timeIntervalSince(started) >= 6 else { return }
                self.aheadRunning = true
                let prompt = self.recognitionPrompt
                Task { [weak self] in
                    let seconds = try? await self?.whisper.recognizeAhead(url, languages: mode.spokenLanguages, prompt: prompt, installation: installation)
                    self?.aheadRunning = false
                    if let seconds { self?.aheadSeconds = seconds }
                }
            }
        }
    }

    private func advance(_ id: UUID, _ next: SessionPhase) {
        if machine.advance(id, to: next) { phase = machine.phase }
    }

    private func fail(_ id: UUID, message: String) {
        recorder.discard()
        advance(id, .failed(message))
        capsule.show(.error)
        Sound.play(.error, enabled: settings.playSounds)
        notice = Notice(text: message)
        Log.error("session failed")
    }

    private func inputInterrupted() {
        guard phase == .recording else { return }
        notice = Notice(text: tr("notice.inputChanged"), isError: false)
        stopRecording()
    }

    private func recognizerProblem(for mode: Mode) -> Notice? {
        switch engine(for: mode) {
        case .auto: break
        case .whisper:
            if WhisperInstallation.current() == nil { return Notice(text: tr("notice.installRecognizer"), action: .openRecognizer) }
            if case .failed = recognizer { return Notice(text: tr("notice.recognizerFailed"), action: .openRecognizer) }
        case .appleDictation:
            if !AppleDictation.isAvailable { return Notice(text: tr("notice.appleUnavailable"), action: .openRecognizer) }
            if mode.spokenLanguages.count != 1 { return Notice(text: tr("notice.appleOneLanguage"), action: .none) }
        case .parakeet:
            if ParakeetInstallation.current() == nil { return Notice(text: tr("notice.installParakeet"), action: .openRecognizer) }
        }
        return nil
    }

    // MARK: Results and history

    private func saveRecord(id: UUID, mode: Mode, raw: String, edit: EditResult?, languages: [String], audioFile: String?, delivery: String) {
        guard settings.retention.keepText else { return }
        let note: String? = edit?.failure.map { Self.message(for: $0) }
        let record = DictationRecord(id: id, modeName: mode.name, modeSymbol: mode.symbol, raw: raw, edited: edit?.edited, detectedLanguage: languages.first, audioFile: audioFile, timing: timing, delivery: delivery, editNote: note)
        history.upsert(record)
        applyRetention()
    }

    private func persistHistory() { JSONFile.save(history, to: "history.json") }

    func applyRetention() {
        let files = history.applyRetention(settings.retention)
        files.forEach(Paths.deleteRecording)
        removeOrphanRecordings()
        persistHistory()
    }

    /// Deletes our own recordings that no record references (crashes, cancelled sessions).
    private func removeOrphanRecordings() {
        let referenced = Set(history.records.compactMap(\.audioFile))
        let active = result?.audioFile
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Paths.recordings.path)) ?? []
        for name in files where RecordingFiles.isOwnRecording(name) && !referenced.contains(name) && name != active {
            let url = Paths.recordings.appendingPathComponent(name)
            // Skip a file that is being written right now.
            if let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, Date().timeIntervalSince(modified) < 60 { continue }
            Paths.deleteRecording(name)
        }
    }

    func deleteRecord(_ id: UUID) {
        guard let record = history.records.first(where: { $0.id == id }) else { return }
        if let file = record.audioFile { Paths.deleteRecording(file) }
        history.records.removeAll { $0.id == id }
        if result?.recordID == id { result = nil }
        persistHistory()
    }

    func deleteAllHistory() {
        history.records.forEach { if let f = $0.audioFile { Paths.deleteRecording(f) } }
        history.records.removeAll()
        result = nil
        removeOrphanRecordings()
        persistHistory()
    }

    func open(_ record: DictationRecord) {
        guard !isBusy else { return }
        result = SessionResult(recordID: record.id, modeName: record.modeName, raw: record.raw, edited: record.edited, output: record.output, outcome: nil, editFailure: nil, editIssues: [], destination: nil, languages: record.detectedLanguage.map { [$0] } ?? [], timing: record.timing, feedback: record.feedback, feedbackState: record.feedback == nil ? .none : .ready, learningLevel: .onDemand, learningLanguage: record.feedback?.learningLanguage ?? activeMode.learningLanguage, audioFile: record.audioFile, transcriptConfirmed: record.transcriptConfirmed)
        phase = nil
    }

    func copyResult() {
        guard let result else { return }
        delivery.copy(result.output)
        notice = Notice(text: tr("notice.copied"), isError: false)
    }

    func useRawTranscript() {
        guard var r = result else { return }
        r.output = r.raw
        result = r
        delivery.copy(r.raw)
        notice = Notice(text: tr("notice.rawCopied"), isError: false)
    }

    /// Re-inserts into the original app after the person clicked in this window.
    func insertAgain() {
        guard let r = result, let destination = r.destination, let app = NSRunningApplication(processIdentifier: destination.processID) else { copyResult(); return }
        app.activate()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            var target = destination
            target.elementToken = nil
            let outcome = await delivery.deliver(r.output, to: target, restoreClipboard: settings.restoreClipboard)
            result?.outcome = outcome
            notice = Notice(text: Self.describe(outcome), isError: !outcome.isInsertion)
        }
    }

    /// Runs the editor again on the raw transcript (a visible, paid action).
    func retryEdit() {
        guard var r = result, !isBusy else { return }
        var mode = activeMode
        if mode.cleanup == .off { mode.cleanup = .light }
        Task {
            let edit = await TextPipeline.edit(raw: r.raw, mode: mode, provider: { try self.makeProvider() })
            r.edited = edit.edited
            r.output = edit.output
            r.editFailure = edit.failure
            r.editIssues = edit.issues
            result = r
            if let failure = edit.failure { notice = Notice(text: Self.message(for: failure), action: failure.isProviderSetup ? .openProvider : .none) } else { notice = nil }
            if var record = history.records.first(where: { $0.id == r.recordID }) {
                record.edited = edit.edited
                history.upsert(record)
                persistHistory()
            }
        }
    }

    /// Recognises a kept recording again, e.g. after a recogniser failure.
    func retryRecognition(_ record: DictationRecord) {
        guard let file = record.audioFile, !isBusy else { return }
        let url = Paths.recording(file)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let snapshot = SessionSnapshot(id: record.id, mode: activeMode, trigger: .retry, destination: nil)
        guard machine.begin(snapshot) else { return }
        phase = machine.phase
        timing = SessionTiming()
        let duration = (try? AVAudioFileDuration(url)) ?? 30
        timing.recordingEnded = Date()
        advance(snapshot.id, .transcribing)
        capsule.show(.processing)
        sessionTask = Task { [weak self] in
            await self?.process(snapshot, recording: AudioRecorder.Result(url: url, duration: duration, voicedSeconds: duration, peakDB: -20, interrupted: false))
        }
    }

    /// Recognises an audio file (any format AVFoundation reads), up to 30 minutes.
    /// The text stays in Saidright; nothing is inserted into other apps.
    func importAudio(_ source: URL) {
        guard !isBusy else { return }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let target = Paths.recordings.appendingPathComponent(UUID().uuidString + ".wav")
        let duration: Double
        do {
            duration = try AudioImport.convert(source, to: target, maxSeconds: 1800)
        } catch AudioImport.Failure.tooLong {
            notice = Notice(text: tr("import.tooLong"))
            return
        } catch {
            notice = Notice(text: tr("error.badAudio"))
            return
        }
        var mode = activeMode
        mode.output = .keep
        let snapshot = SessionSnapshot(mode: mode, trigger: .importedFile, destination: nil)
        guard machine.begin(snapshot) else { try? FileManager.default.removeItem(at: target); return }
        phase = machine.phase
        timing = SessionTiming()
        timing.recordingEnded = Date()
        advance(snapshot.id, .transcribing)
        sessionTask = Task { [weak self] in
            await self?.process(snapshot, recording: AudioRecorder.Result(url: target, duration: duration, voicedSeconds: duration, peakDB: -20, interrupted: false))
        }
    }

    /// Lets the person correct what was recognised before learning feedback counts.
    func confirmTranscript(_ text: String) {
        guard var r = result else { return }
        let changed = text.trimmingCharacters(in: .whitespacesAndNewlines) != r.raw
        r.raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        r.transcriptConfirmed = true
        if changed { r.feedback = nil; r.feedbackState = .none }
        result = r
        if var record = history.records.first(where: { $0.id == r.recordID }) {
            record.raw = r.raw
            record.transcriptConfirmed = true
            if changed { record.feedback = nil }
            history.upsert(record)
            persistHistory()
        }
        if changed && r.learningLevel != .off { requestFeedback(automatic: false) }
    }

    // MARK: Learning

    func requestFeedback(automatic: Bool) {
        guard var r = result else { return }
        if (provider.localOnly && !provider.isOnDevice) || (provider.requiresCredential && !hasCredential) {
            r.feedbackState = .skippedNoProvider
            result = r
            return
        }
        let provider: TextProvider
        do { provider = try makeProvider() } catch {
            r.feedbackState = .skippedNoProvider
            result = r
            return
        }
        r.feedbackState = .running
        result = r
        let level: LearningLevel = automatic ? r.learningLevel : .detailed
        let explanation = activeMode.explanationLanguage ?? settings.explanationLanguage ?? Localizer.shared.language.rawValue
        let recordID = r.recordID
        let transcript = r.raw
        let language = r.learningLanguage
        let goal = settings.learningGoal
        let ui = settings.learningUI
        let modeLevel = r.learningLevel
        feedbackTask?.cancel()
        // Feedback runs after delivery while Saidright is in the background; keep it from being
        // throttled by App Nap so the tip arrives promptly.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "Language feedback")
        feedbackTask = Task { [weak self] in
            defer { ProcessInfo.processInfo.endActivity(activity) }
            do {
                let feedback = try await TextPipeline.feedback(transcript: transcript, learningLanguage: language, explanationLanguage: explanation, level: level, goal: goal, learner: ui.level, depth: ui.depth, provider: provider)
                guard let self, self.result?.recordID == recordID, !Task.isCancelled else { return }
                self.result?.feedback = feedback
                self.result?.feedbackState = .ready
                self.storeFeedback(feedback, for: recordID)
                if automatic {
                    self.prepareCorrection(feedback, recordID: recordID)
                    self.offerHint(feedback, recordID: recordID, level: modeLevel)
                }
            } catch {
                guard let self, self.result?.recordID == recordID else { return }
                self.result?.feedbackState = .failed(Self.message(for: error))
            }
        }
    }

    /// Shows the useful part of new feedback in the capsule, unless a newer session is running
    /// or the person prefers to read feedback in the window.
    private func offerHint(_ feedback: Feedback, recordID: UUID, level: LearningLevel) {
        let ui = settings.learningUI
        let items = CapsuleHints.select(feedback, level: level, includeUncertain: ui.showUncertainInCapsule)
        guard !items.isEmpty else { return }
        let fixable = pendingCorrection?.recordID == recordID && ui.applyCorrections == .button
        lastHint = CapsuleHint(recordID: recordID, items: items, fixable: fixable)
        guard ui.presentation != .window, !isBusy else { return }
        capsule.offerHint(CapsuleHint(recordID: recordID, items: items, fixable: fixable), asMarker: ui.presentation == .indicator)
    }

    /// Fixes a tip suggests for text that was just inserted: (record, inserted text, fixed text).
    private var pendingCorrection: (recordID: UUID, old: String, new: String)?

    /// Prepares the tip's fixes for the inserted text and, when the person chose so, applies them
    /// right away (only if nothing was typed or clicked since the insertion).
    private func prepareCorrection(_ feedback: Feedback, recordID: UUID) {
        pendingCorrection = nil
        guard let r = result, r.recordID == recordID, r.outcome?.isInsertion == true, r.destination != nil,
              let fixed = FeedbackValidator.corrected(r.output, by: feedback) else { return }
        pendingCorrection = (recordID, r.output, fixed)
        if settings.learningUI.applyCorrections == .automatic { applyCorrection(recordID, strict: true) }
    }

    /// Replaces the inserted text with the fixed one in the field it went to. From the card's
    /// button a failure copies the fixed text instead, so the person can paste it.
    func applyCorrection(_ recordID: UUID, strict: Bool) {
        guard let pending = pendingCorrection, pending.recordID == recordID, let destination = result?.destination else { return }
        pendingCorrection = nil
        Task { [weak self] in
            guard let self else { return }
            let html = TextFlavor.wantsRichText(bundleID: destination.bundleID) && RichText.hasLayout(pending.new) ? RichText.html(pending.new) : nil
            let done = await self.delivery.replaceDelivered(pending.old, with: pending.new, html: html, destination: destination, restoreClipboard: self.settings.restoreClipboard, strict: strict)
            self.capsule.markCorrectionHandled(recordID)
            if done {
                if self.result?.recordID == recordID { self.result?.output = pending.new }
            } else if !strict {
                self.delivery.copy(pending.new)
                self.notice = Notice(text: tr("notice.correctionCopied"), action: .none)
            }
        }
    }

    /// The tips of the most recent dictation that had any, for the reopen shortcut.
    private var lastHint: CapsuleHint?

    /// QA: behave as if feedback with the sample tip just arrived.
    func qaSampleFeedback() {
        let hint = CapsuleModel.sampleHint()
        lastHint = hint
        capsule.offerHint(hint, asMarker: false)
    }

    /// ⌃⌥L: closes an open tip, or opens the last one again (pinned, so it stays to be read).
    func toggleLastTip() {
        if capsule.isInteractive { capsule.hide(); return }
        guard !isBusy else { capsule.nudge(); return }
        // Prefer what is still unresolved in history; items marked as handled are not shown again.
        if var hint = lastHint {
            if let feedback = history.records.first(where: { $0.id == hint.recordID })?.feedback {
                hint.items = hint.items.filter { item in
                    let stored = feedback.items.first { $0.id == item.id }
                    return stored?.verdict == nil && stored?.savedForReview != true
                }
            }
            if !hint.items.isEmpty {
                capsule.offerHint(hint, asMarker: false)
                capsule.pin()
                Log.info("last tip reopened (\(hint.items.count))")
                return
            }
        }
        Log.info("last tip: none")
        capsule.flash(tr("tip.none"), symbol: "character.book.closed")
    }

    private func storeFeedback(_ feedback: Feedback, for recordID: UUID) {
        guard var record = history.records.first(where: { $0.id == recordID }) else { return }
        record.feedback = feedback
        history.upsert(record)
        persistHistory()
    }

    func setVerdict(_ verdict: UserVerdict?, for itemID: UUID, record: UUID? = nil) {
        updateFeedback(record: record ?? result?.recordID) { feedback, _ in
            guard let i = feedback.items.firstIndex(where: { $0.id == itemID }) else { return }
            feedback.items[i].verdict = verdict
        }
    }

    func saveForReview(_ itemID: UUID, record: UUID? = nil) {
        updateFeedback(record: record ?? result?.recordID) { feedback, transcript in
            guard let i = feedback.items.firstIndex(where: { $0.id == itemID }) else { return }
            let card = ReviewScheduler.card(from: feedback.items[i], feedback: feedback, transcript: transcript)
            if !history.cards.contains(where: { $0.prompt == card.prompt && $0.answer == card.answer }) { history.cards.append(card) }
            feedback.items[i].savedForReview = true
        }
        // From the capsule the card itself confirms the save; the window shows a notice.
        if record == nil { notice = Notice(text: tr("notice.savedForReview"), isError: false) }
    }

    /// Changes feedback of the current result or of an older record (actions from a capsule
    /// hint can arrive after a newer dictation replaced the result).
    private func updateFeedback(record id: UUID?, _ change: (inout Feedback, String) -> Void) {
        guard let id else { return }
        if var r = result, r.recordID == id, var feedback = r.feedback {
            change(&feedback, r.raw)
            r.feedback = feedback
            result = r
            storeFeedback(feedback, for: id)
        } else if let record = history.records.first(where: { $0.id == id }), var feedback = record.feedback {
            change(&feedback, record.raw)
            storeFeedback(feedback, for: id)
        }
    }

    var dueCards: [ReviewCard] { history.cards.filter { $0.due <= Date() }.sorted { $0.due < $1.due } }

    func grade(_ card: ReviewCard, _ grade: ReviewGrade) {
        guard let i = history.cards.firstIndex(where: { $0.id == card.id }) else { return }
        history.cards[i] = ReviewScheduler.schedule(card, grade: grade)
        persistHistory()
    }

    func deleteCard(_ id: UUID) {
        history.cards.removeAll { $0.id == id }
        persistHistory()
    }

    func addVocabulary(_ entry: VocabularyEntry) {
        history.vocabulary.append(entry)
        persistHistory()
    }

    func removeVocabulary(_ id: UUID) {
        history.vocabulary.removeAll { $0.id == id }
        persistHistory()
    }

    func updateVocabulary(_ entry: VocabularyEntry) {
        guard let i = history.vocabulary.firstIndex(where: { $0.id == entry.id }) else { return }
        history.vocabulary[i] = entry
        persistHistory()
    }

    // MARK: Provider

    /// The configured provider, or for QA (SAIDRIGHT_QA_LOCAL_MODEL=<ollama model>) a local-only
    /// Ollama provider held in memory, so tests never use the owner's cloud key or settings.
    var provider: ProviderSettings {
        guard let qaModel = ProcessInfo.processInfo.environment["SAIDRIGHT_QA_LOCAL_MODEL"] else { return settings.provider }
        var p = ProviderSettings()
        p.kind = .compatible
        p.compatibleBaseURL = "http://localhost:11434/v1"
        p.compatibleModel = qaModel
        p.compatibleNoReasoning = true
        p.localOnly = true
        return p
    }

    func makeProvider() throws -> TextProvider {
        var credential: String?
        if provider.kind == .openAI || !provider.isOnDevice {
            credential = Keychain.read(provider.credentialAccount)
        }
        return TextProvider(settings: provider, credential: credential)
    }

    func saveCredential(_ value: String) -> Bool {
        do {
            try Keychain.save(value, account: settings.provider.credentialAccount)
            hasCredential = true
            return true
        } catch { return false }
    }

    func removeCredential() {
        Keychain.remove(settings.provider.credentialAccount)
        hasCredential = false
    }

    func importLegacyCredential() -> Bool {
        let ok = Keychain.importLegacyOpenAIKey()
        hasCredential = Keychain.exists(settings.provider.credentialAccount)
        return ok
    }

    // MARK: Recogniser

    /// Loads Parakeet ahead of time when a mode uses it, so its first dictation is warm too.
    func warmUpParakeetIfUsed() {
        guard modes.modes.contains(where: { engine(for: $0) == .parakeet }), let installation = ParakeetInstallation.current(), !parakeet.isRunning else { return }
        Task { try? await parakeet.prepare(modelDir: installation.modelDir, python: installation.python, onProgress: nil) }
    }

    func stopParakeet() { parakeet.stop() }

    func warmUpRecognizer() {
        warmUpParakeetIfUsed()
        guard let installation = WhisperInstallation.current() else { recognizer = .notInstalled; return }
        recognizer = .loading
        Task {
            do {
                try await whisper.prepare(modelDir: installation.modelDir, python: installation.python, onProgress: nil)
                recognizer = .ready
            } catch {
                recognizer = .failed(Self.message(for: error))
            }
        }
    }

    var whisperInstallation: WhisperInstallation? { WhisperInstallation.current() }
    var recognizerDiagnostics: String { whisper.diagnostics }

    func setRecognizerState(_ state: RecognizerState) { recognizer = state }

    func restartRecognizer() {
        whisper.stop()
        warmUpRecognizer()
    }

    // MARK: Automation

    func handleAutomation(_ url: URL) {
        guard url.scheme == "saidright" else { return }
        guard settings.allowAutomationLinks else {
            Log.info("automation link ignored (disabled)")
            return
        }
        let command = url.host ?? ""
        switch command {
        case "toggle": handleHotkey(.toggle)
        case "start": if !isBusy { startRecording(trigger: .hotkey) }
        case "stop": stopRecording()
        case "cancel": cancel()
        case "next-mode": handleHotkey(.switchMode)
        case "mode":
            let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "name" }?.value
            if let mode = modes.modes.first(where: { $0.name.caseInsensitiveCompare(name ?? "") == .orderedSame }), !isBusy {
                modes.setActive(mode.id)
                capsule.flashMode(mode.name, symbol: mode.symbol)
            }
        default:
            // Any app can open a link: never log its own text.
            Log.info("automation: unknown command")
            return
        }
        Log.info("automation: \(command)")
    }

    // MARK: Devices & settings

    func refreshDevices() { inputDevices = AudioRecorder.devices() }

    private func settingsChanged(from old: AppSettings) {
        JSONFile.save(settings, to: "settings.json")
        if settings.uiLanguage != old.uiLanguage {
            Localizer.shared.setLanguage(settings.uiLanguage)
            Self.applyProcessLanguage(settings.uiLanguage)
            localizePresetNames()
        }
        if settings.hotkeys != old.hotkeys, !Self.isQAInstance { hotkeys.apply(settings.hotkeys) }
        if settings.capsule != old.capsule { capsule.apply(settings.capsule) }
        if settings.whisperModel != old.whisperModel {
            WhisperInstallation.selected = ModelCatalog.model(settings.whisperModel) ?? ModelCatalog.whisperTurbo
            restartRecognizer()
        }
        if settings.learningUI != old.learningUI { capsule.hintLinger = settings.learningUI.linger.seconds }
        if settings.theme != old.theme || settings.appIcon != old.appIcon { applyAppearance() }
        if settings.retention != old.retention { applyRetention() }
        if settings.provider.credentialAccount != old.provider.credentialAccount { hasCredential = Keychain.exists(settings.provider.credentialAccount) }
    }

    /// Window theme and Dock icon. The capsule follows the theme for its glass card.
    func applyAppearance() {
        // The QA override (SAIDRIGHT_APPEARANCE) wins so screenshots stay reproducible.
        if ProcessInfo.processInfo.environment["SAIDRIGHT_APPEARANCE"] == nil {
            NSApp.appearance = switch settings.theme {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
        let dark = (NSApp.appearance ?? NSApp.effectiveAppearance).bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        capsuleController?.scheme = dark ? .dark : .light
        IconRenderer.applyDockIcon(settings.appIcon)
    }

    /// Standard AppKit menus and dialogs follow the process language, which macOS reads at
    /// launch. Saidright's own strings switch immediately; system menus follow after a restart.
    static func applyProcessLanguage(_ language: UILanguage) {
        if language == .system { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
        else { UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages") }
    }

    /// Starter modes the person has not renamed follow the interface language.
    func localizePresetNames() {
        for var mode in modes.modes {
            guard let preset = mode.presetID else { continue }
            let key = "preset.\(preset)"
            let known = Set(UILanguage.translated.compactMap { Localizer.shared.table($0)[key] })
            let current = tr(key)
            if known.contains(mode.name), mode.name != current {
                mode.name = current
                modes.update(mode)
            }
        }
    }

    func startKeyTest() { keyTestPassed = false; hotkeys.installTapIfPossible(); hotkeys.refreshSecureInput() }

    // MARK: Legacy import

    private func importLegacyIfNeeded() {
        guard history.importedLegacyAt == nil else { return }
        let file = Paths.legacyRoot.appendingPathComponent("library.json")
        guard let data = try? Data(contentsOf: file) else { return }
        do {
            let imported = try LegacyImport.parse(data, practiceName: tr("preset.practice"), dictationName: tr("legacy.dictation"))
            for (name, source) in imported.audioToCopy where FileManager.default.fileExists(atPath: source) {
                try? FileManager.default.copyItem(atPath: source, toPath: Paths.recording(name).path)
            }
            var records = imported.records
            for i in records.indices where records[i].audioFile.map({ !FileManager.default.fileExists(atPath: Paths.recording($0).path) }) ?? false {
                records[i].audioFile = nil
            }
            let existing = Set(history.records.map(\.id))
            history.records.append(contentsOf: records.filter { !existing.contains($0.id) })
            history.records.sort { $0.date > $1.date }
            history.cards.append(contentsOf: imported.cards)
            history.importedLegacyAt = Date()
            persistHistory()
            Log.info("imported legacy library: \(records.count) records, \(imported.cards.count) cards")
        } catch {
            Log.error("legacy import failed: \(type(of: error))")
        }
    }

    // MARK: Messages

    static func message(for error: Error) -> String {
        switch error {
        case let e as RecognizerError:
            switch e {
            case .runtimeMissing: return tr("error.runtimeMissing")
            case .modelMissing: return tr("error.modelMissing")
            case .workerStopped: return tr("error.workerStopped")
            case .timeout: return tr("error.timeout")
            case .memory: return tr("error.memory")
            case .badAudio: return tr("error.badAudio")
            case .unsupportedLanguage: return tr("error.unsupportedLanguage")
            case .assetsUnavailable: return tr("error.assetsUnavailable")
            case .failed(let code): return tr("error.recognizerFailed", code)
            }
        case let e as RecorderError:
            switch e {
            case .microphoneDenied: return tr("notice.micDenied")
            case .noInputDevice, .deviceUnavailable: return tr("error.noInput")
            case .engineFailed: return tr("error.engine")
            }
        case let e as ProviderError: return message(for: EditFailure.provider(e))
        case is FeedbackValidator.Failure: return tr("error.feedbackFormat")
        default: return tr("error.generic")
        }
    }

    static func message(for failure: EditFailure) -> String {
        switch failure {
        case .rejected(let issues):
            if issues.contains(.numbersChanged) || issues.contains(.linksChanged) { return tr("edit.rejected.numbers") }
            return tr("edit.rejected.size")
        case .provider(let e):
            switch e {
            case .blockedByLocalOnly: return tr("provider.localOnly")
            case .missingCredential: return tr("provider.missingKey")
            case .invalidCredential: return tr("provider.invalidKey")
            case .forbidden: return tr("provider.forbidden")
            case .modelUnavailable(let m): return tr("provider.model", m)
            case .insufficientQuota: return tr("provider.quota")
            case .rateLimited: return tr("provider.rate")
            case .network, .timeout: return tr("provider.network")
            case .refused: return tr("provider.refused")
            case .truncated: return tr("provider.truncated")
            case .emptyResponse, .invalidResponse: return tr("provider.invalidResponse")
            case .server(let code): return tr("provider.server", code)
            case .invalidConfiguration: return tr("provider.config")
            case .cancelled: return tr("status.cancelled")
            }
        }
    }
}

extension DeliveryOutcome {
    var isInsertion: Bool {
        switch self { case .insertedVerified, .insertedUnverified: true; default: false }
    }

    var code: String {
        switch self {
        case .insertedVerified: "insertedVerified"
        case .insertedUnverified: "insertedUnverified"
        case .kept: "kept"
        case .copied(let reason): "copied:\(reason.rawValue)"
        }
    }
}

extension EditFailure {
    /// Failures the person fixes in provider settings rather than by retrying.
    var isProviderSetup: Bool {
        guard case .provider(let e) = self else { return false }
        switch e {
        case .missingCredential, .invalidCredential, .modelUnavailable, .blockedByLocalOnly, .invalidConfiguration, .forbidden: return true
        default: return false
        }
    }
}

import AVFoundation

enum AudioImport {
    enum Failure: Error { case tooLong, unreadable }

    /// Converts any readable audio file to 16 kHz mono 16-bit WAV. Returns the duration.
    static func convert(_ source: URL, to target: URL, maxSeconds: Double) throws -> Double {
        let input = try AVAudioFile(forReading: source)
        let seconds = Double(input.length) / input.fileFormat.sampleRate
        guard seconds <= maxSeconds else { throw Failure.tooLong }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input.processingFormat, to: format),
              let inBuffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 8192) else { throw Failure.unreadable }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false]
        let output = try AVAudioFile(forWriting: target, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        var finished = false
        while true {
            guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { throw Failure.unreadable }
            var error: NSError?
            let status = converter.convert(to: out, error: &error) { _, state in
                if finished { state.pointee = .endOfStream; return nil }
                let remaining = input.length - input.framePosition
                guard remaining > 0, (try? input.read(into: inBuffer, frameCount: AVAudioFrameCount(min(Int64(inBuffer.frameCapacity), remaining)))) != nil, inBuffer.frameLength > 0 else {
                    finished = true
                    state.pointee = .endOfStream
                    return nil
                }
                state.pointee = .haveData
                return inBuffer
            }
            if error != nil { throw Failure.unreadable }
            if out.frameLength > 0 { try output.write(from: out) }
            if status == .endOfStream || status == .error { break }
        }
        return seconds
    }
}

private func AVAudioFileDuration(_ url: URL) throws -> Double {
    let file = try AVAudioFile(forReading: url)
    return Double(file.length) / file.fileFormat.sampleRate
}
