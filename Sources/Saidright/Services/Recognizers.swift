import AVFoundation
import Foundation
import SaidrightCore
import Speech

struct Transcript: Equatable {
    var text: String
    /// Catalog language ids detected or used.
    var languages: [String]
    var seconds: Double
    var cold: Bool
}

enum RecognizerError: Error, Equatable {
    case runtimeMissing
    case modelMissing
    case workerStopped
    case timeout
    case memory
    case badAudio
    case unsupportedLanguage(String)
    case assetsUnavailable
    case failed(String)
}

/// Locates the Python runtime and Whisper weights. Prefers this app's own folders and falls back
/// to a Govori 0.2 installation in place (read-only, nothing is copied or duplicated).
struct WhisperInstallation: Equatable {
    var python: URL
    var modelDir: URL
    var isLegacy: Bool

    /// The Whisper model chosen in settings; AppModel keeps this in sync.
    nonisolated(unsafe) static var selected: SpeechModel = ModelCatalog.whisperTurbo
    static var modelFolderName: String { selected.folder ?? "whisper-large-v3-turbo" }

    static func pythonCandidates() -> [URL] {
        [Paths.runtime.appendingPathComponent("bin/python3"), Paths.legacyRoot.appendingPathComponent("runtime/bin/python3")]
    }

    /// Saidright's own copy first; the Govori folder only holds large-v3-turbo.
    static func modelCandidates(for model: SpeechModel = selected) -> [URL] {
        var list = [Paths.models.appendingPathComponent(model.folder ?? "")]
        if model.id == ModelCatalog.whisperTurbo.id { list.append(Paths.legacyRoot.appendingPathComponent("models/whisper-turbo")) }
        return list
    }

    static func modelPresent(_ dir: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: dir.appendingPathComponent("config.json").path) && (fm.fileExists(atPath: dir.appendingPathComponent("weights.safetensors").path) || fm.fileExists(atPath: dir.appendingPathComponent("weights.npz").path))
    }

    static func runtime() -> URL? { pythonCandidates().first { FileManager.default.isExecutableFile(atPath: $0.path) } }

    static func installedModel(_ model: SpeechModel = selected) -> URL? { modelCandidates(for: model).first(where: modelPresent) }

    /// The catalog entry a model folder belongs to (the Govori folder is large-v3-turbo).
    static func catalogEntry(for modelDir: URL) -> SpeechModel {
        (ModelCatalog.whisper + [ModelCatalog.parakeet]).first { $0.folder == modelDir.lastPathComponent } ?? ModelCatalog.whisperTurbo
    }

    static func current() -> WhisperInstallation? {
        guard let python = runtime(), let model = installedModel() else { return nil }
        return WhisperInstallation(python: python, modelDir: model, isLegacy: python.path.hasPrefix(Paths.legacyRoot.path) || model.path.hasPrefix(Paths.legacyRoot.path))
    }
}

/// Parakeet runs in its own Python environment (Saidright/Runtime-Parakeet) with its own model folder.
struct ParakeetInstallation: Equatable {
    var python: URL
    var modelDir: URL

    static var python: URL { Paths.parakeetRuntime.appendingPathComponent("bin/python3") }
    static var modelDir: URL { Paths.models.appendingPathComponent(ModelCatalog.parakeet.folder ?? "parakeet") }

    static func runtimeReady() -> Bool { FileManager.default.isExecutableFile(atPath: python.path) }
    static func modelPresent() -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: modelDir.appendingPathComponent("config.json").path) && fm.fileExists(atPath: modelDir.appendingPathComponent("model.safetensors").path)
    }

    static func current() -> ParakeetInstallation? {
        runtimeReady() && modelPresent() ? ParakeetInstallation(python: python, modelDir: modelDir) : nil
    }

    var asWorkerInstallation: WhisperInstallation { WhisperInstallation(python: python, modelDir: modelDir, isLegacy: false) }
}

/// Resident MLX recogniser process (Whisper or Parakeet) speaking `WorkerProtocol`.
final class WhisperEngine: @unchecked Sendable {
    typealias Progress = @Sendable (String, Double?) -> Void

    private let lock = NSLock()
    private var process: Process?
    private var stdin: FileHandle?
    private var lines = LineBuffer()
    private var waiting: [String: CheckedContinuation<WorkerProtocol.Reply, Error>] = [:]
    private var progress: [String: Progress] = [:]
    private var stderrTail = ""
    private(set) var modelLoaded = false
    /// Called (on a background queue) when the process exits without being asked to.
    var onUnexpectedExit: (@Sendable () -> Void)?
    private var stopping = false

    var isRunning: Bool { lock.withLock { process?.isRunning == true } }

    /// Prepares the model: downloads if needed (only when `allowDownload`), loads and warms up.
    func prepare(modelDir: URL, python: URL, onProgress: Progress?) async throws {
        let reply = try await send(command: "prepare", extra: [:], python: python, modelDir: modelDir, timeout: 3600, onProgress: onProgress)
        if case .ready = reply { lock.withLock { modelLoaded = true } }
    }

    func transcribe(_ url: URL, languages: [String], prompt: String?, audioSeconds: Double, installation: WhisperInstallation) async throws -> Transcript {
        let cold = !lock.withLock { modelLoaded && process?.isRunning == true }
        let whisperCodes = languages.compactMap { LanguageCatalog.info($0)?.whisperCode }
        var extra: [String: Any] = ["path": url.path, "languages": whisperCodes]
        if let prompt, !prompt.isEmpty { extra["prompt"] = prompt }
        let reply = try await send(command: "transcribe", extra: extra, python: installation.python, modelDir: installation.modelDir, timeout: WorkerProtocol.timeout(audioSeconds: audioSeconds, cold: cold), onProgress: nil)
        guard case let .transcript(_, text, codes, seconds, wasCold, _) = reply else { throw RecognizerError.failed("protocol") }
        lock.withLock { modelLoaded = true }
        let ids = codes.map { LanguageCatalog.fromWhisper($0)?.id ?? $0 }
        return Transcript(text: text, languages: ids, seconds: seconds, cold: wasCold)
    }

    /// Ends the process. Pending requests fail with `.workerStopped`.
    func stop() {
        let (p, pending) = lock.withLock { () -> (Process?, [CheckedContinuation<WorkerProtocol.Reply, Error>]) in
            stopping = true
            let p = process
            process = nil
            stdin = nil
            modelLoaded = false
            let pending = Array(waiting.values)
            waiting = [:]
            progress = [:]
            return (p, pending)
        }
        if p?.isRunning == true { p?.terminate() }
        pending.forEach { $0.resume(throwing: RecognizerError.workerStopped) }
    }

    var diagnostics: String { lock.withLock { stderrTail } }

    // MARK: Process

    private func ensureRunning(python: URL, modelDir: URL) throws {
        if lock.withLock({ process?.isRunning == true }) { return }
        guard let script = Bundle.main.url(forResource: "recognizer", withExtension: "py") else { throw RecognizerError.runtimeMissing }
        let p = Process()
        let input = Pipe(), output = Pipe(), errors = Pipe()
        p.executableURL = python
        // -I: isolated mode, ignores user site-packages and the current directory.
        let entry = WhisperInstallation.catalogEntry(for: modelDir)
        p.arguments = ["-I", "-u", script.path, "--model-dir", modelDir.path, "--cache-dir", Paths.cache.appendingPathComponent("huggingface").path, "--repo", entry.repo ?? "", "--revision", entry.revision ?? "", "--engine", entry.engine == .parakeetMLX ? "parakeet" : "whisper"]
        p.standardInput = input
        p.standardOutput = output
        p.standardError = errors
        var env: [String: String] = [:]
        for key in ["HOME", "PATH", "TMPDIR", "LANG"] { env[key] = ProcessInfo.processInfo.environment[key] }
        env["PYTHONUNBUFFERED"] = "1"
        env["HF_HUB_DISABLE_TELEMETRY"] = "1"
        p.environment = env // No API keys or other secrets are inherited.
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            self?.received(data)
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            self?.appendDiagnostics(String(decoding: data, as: UTF8.self))
        }
        p.terminationHandler = { [weak self] proc in self?.terminated(proc) }
        try p.run()
        lock.withLock {
            process = p
            stdin = input.fileHandleForWriting
            lines = LineBuffer()
            modelLoaded = false
        }
        Log.info("recognizer started pid \(p.processIdentifier)")
    }

    private func send(command: String, extra: [String: Any], python: URL, modelDir: URL, timeout: TimeInterval, onProgress: Progress?) async throws -> WorkerProtocol.Reply {
        try ensureRunning(python: python, modelDir: modelDir)
        let id = UUID().uuidString
        var body = extra
        body["id"] = id
        body["command"] = command
        var data = try JSONSerialization.data(withJSONObject: body)
        data.append(0x0A)
        let reply: WorkerProtocol.Reply = try await withCheckedThrowingContinuation { continuation in
            let handle: FileHandle? = lock.withLock {
                waiting[id] = continuation
                if let onProgress { progress[id] = onProgress }
                return stdin
            }
            do {
                guard let handle else { throw RecognizerError.workerStopped }
                try handle.write(contentsOf: data)
            } catch {
                if let c = lock.withLock({ waiting.removeValue(forKey: id) }) { c.resume(throwing: RecognizerError.workerStopped) }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self, let c = self.lock.withLock({ self.waiting.removeValue(forKey: id) }) else { return }
                Log.error("recognizer timeout for \(command)")
                c.resume(throwing: RecognizerError.timeout)
                self.stop()
            }
        }
        if case let .failure(_, code, message) = reply {
            switch code {
            case "model_missing": throw RecognizerError.modelMissing
            case "memory": throw RecognizerError.memory
            case "format": throw RecognizerError.badAudio
            default: throw RecognizerError.failed(code == "internal" ? message : code)
            }
        }
        return reply
    }

    private func received(_ data: Data) {
        let replies = lock.withLock { lines.append(data) }.compactMap(WorkerProtocol.decode(line:))
        for reply in replies {
            switch reply {
            case let .progress(id, stage, fraction):
                let callback = lock.withLock { progress[id] }
                callback?(stage, fraction)
            case let .transcript(id, _, _, _, _, _), let .ready(id, _), let .failure(id, _, _), let .pong(id, _):
                // Replies for ids nobody waits for (cancelled, timed out) are dropped here.
                let c = lock.withLock { () -> CheckedContinuation<WorkerProtocol.Reply, Error>? in
                    progress.removeValue(forKey: id)
                    return waiting.removeValue(forKey: id)
                }
                c?.resume(returning: reply)
            }
        }
    }

    private func appendDiagnostics(_ text: String) {
        lock.withLock {
            stderrTail = String((stderrTail + text).suffix(4000))
        }
    }

    private func terminated(_ proc: Process) {
        let expected = lock.withLock { () -> Bool in
            defer { stopping = false }
            return stopping || process !== proc
        }
        let pending = lock.withLock { () -> [CheckedContinuation<WorkerProtocol.Reply, Error>] in
            guard process === proc || process == nil else { return [] }
            process = nil
            stdin = nil
            modelLoaded = false
            let pending = Array(waiting.values)
            waiting = [:]
            progress = [:]
            return pending
        }
        if !pending.isEmpty { Log.error("recognizer exited with status \(proc.terminationStatus)") }
        pending.forEach { $0.resume(throwing: RecognizerError.workerStopped) }
        if !expected { onUnexpectedExit?() }
    }

    /// Abandons a request: its reply will be ignored when it arrives.
    func abandonAll() {
        let pending = lock.withLock { () -> [CheckedContinuation<WorkerProtocol.Reply, Error>] in
            let pending = Array(waiting.values)
            waiting = [:]
            progress = [:]
            return pending
        }
        pending.forEach { $0.resume(throwing: CancellationError()) }
    }
}

/// Apple's on-device dictation model (macOS 26+). No setup beyond a system language asset.
/// One language per request; no automatic language detection or code switching.
enum AppleDictation {
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    static func supports(_ languageID: String) async -> Bool {
        guard #available(macOS 26.0, *), let info = LanguageCatalog.info(languageID) else { return false }
        return await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: info.appleLocale)) != nil
    }

    /// Returns true when the language asset is installed; downloads it when `install` is set.
    static func ensureAsset(_ languageID: String, install: Bool, progress: (@Sendable (Double) -> Void)? = nil) async throws -> Bool {
        guard #available(macOS 26.0, *), let info = LanguageCatalog.info(languageID) else { return false }
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: info.appleLocale)) else { throw RecognizerError.unsupportedLanguage(languageID) }
        let transcriber = DictationTranscriber(locale: locale, preset: .shortDictation)
        let status = await AssetInventory.status(forModules: [transcriber])
        if status == .installed { return true }
        guard install else { return false }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            let observation = progress.map { cb in request.progress.observe(\.fractionCompleted) { p, _ in cb(p.fractionCompleted) } }
            try await request.downloadAndInstall()
            observation?.invalidate()
        }
        return await AssetInventory.status(forModules: [transcriber]) == .installed
    }

    static func transcribe(_ url: URL, languageID: String) async throws -> Transcript {
        guard #available(macOS 26.0, *) else { throw RecognizerError.assetsUnavailable }
        guard let info = LanguageCatalog.info(languageID), let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: info.appleLocale)) else { throw RecognizerError.unsupportedLanguage(languageID) }
        let started = Date()
        let transcriber = DictationTranscriber(locale: locale, preset: .shortDictation)
        guard try await ensureAsset(languageID, install: false) else { throw RecognizerError.assetsUnavailable }
        let file = try AVAudioFile(forReading: url)
        let collector = Task { () -> String in
            var text = ""
            for try await result in transcriber.results { text += String(result.text.characters) }
            return text
        }
        let analyzer = try await SpeechAnalyzer(inputAudioFile: file, modules: [transcriber], finishAfterFile: true)
        _ = analyzer
        let text = try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
        return Transcript(text: text, languages: text.isEmpty ? [] : [languageID], seconds: Date().timeIntervalSince(started), cold: false)
    }
}
