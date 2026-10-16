import CryptoKit
import Foundation
import Observation
import SaywellCore

/// Installs the local recogniser without Terminal: a pinned uv binary (checksum verified),
/// a private Python 3.11, the hashed dependency lock, then the Whisper weights through the
/// worker (checksum verified against the model repository).
///
/// Everything lives in ~/Library/Application Support/Saywell. Nothing outside it is changed.
@MainActor @Observable final class RuntimeInstaller {
    enum Stage: Equatable {
        case idle
        case checkingSpace
        case downloadingTool(Double?)
        case installingPython
        case installingPackages
        case downloadingModel(Double?)
        case verifying
        case loading
        case done
        case failed(String)
        case cancelled
    }

    private(set) var stage: Stage = .idle
    /// Catalog id of the model being installed, so only its row shows progress.
    private(set) var target: String?
    private var process: Process?
    private var task: Task<Void, Never>?

    static let uvVersion = "0.11.14"
    static let uvSHA256 = "4333af5c0730d94323a7819bbdf87ce92dd07fc857d67fff0059e0fca31b5c02"
    /// Approximate sizes shown before the person agrees to download.
    static let runtimeBytes: Int64 = 650_000_000
    static var modelBytes: Int64 { WhisperInstallation.selected.downloadBytes }
    static let requiredFreeBytes: Int64 = 3_000_000_000

    var isRunning: Bool {
        switch stage {
        case .idle, .done, .failed, .cancelled: false
        default: true
        }
    }

    static var tools: URL { Paths.root.appendingPathComponent("Tools", isDirectory: true) }
    static var ownPython: URL { Paths.runtime.appendingPathComponent("bin/python3") }
    static var ownModel: URL { Paths.models.appendingPathComponent(WhisperInstallation.modelFolderName) }

    static func freeSpace() -> Int64 {
        let values = try? Paths.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    func install(model: AppModel) {
        guard !isRunning else { return }
        target = model.settings.whisperModel
        task = Task { await run(model: model) }
    }

    func cancel() {
        task?.cancel()
        process?.terminate()
        stage = .cancelled
    }

    private func run(model: AppModel) async {
        do {
            stage = .checkingSpace
            let needsRuntime = WhisperInstallation.runtime() == nil
            let needsModel = WhisperInstallation.installedModel() == nil
            let needed = (needsRuntime ? Self.runtimeBytes : 0) + (needsModel ? Self.modelBytes : 0) + 300_000_000
            if Self.freeSpace() < needed { throw InstallError.space(needed) }

            if needsRuntime {
                let uv = try await ensureUV()
                try Task.checkCancellation()
                stage = .installingPython
                var env = uvEnvironment()
                try await runProcess(uv, ["venv", "--python", "3.11", "--seed", "--allow-existing", Paths.runtime.path], env: env)
                try Task.checkCancellation()
                stage = .installingPackages
                guard let lock = Bundle.main.url(forResource: "requirements", withExtension: "lock") else { throw InstallError.missingResource }
                env["UV_NO_CONFIG"] = "1"
                try await runProcess(uv, ["pip", "install", "--python", Self.ownPython.path, "--require-hashes", "--no-deps", "-r", lock.path], env: env)
            }
            try Task.checkCancellation()

            guard let python = WhisperInstallation.runtime() else { throw InstallError.step("python") }
            let modelDir = WhisperInstallation.installedModel() ?? Self.ownModel
            stage = needsModel ? .downloadingModel(nil) : .loading
            model.setRecognizerState(.installing(stage: "model", fraction: nil))
            let engine = WhisperEngine()
            try await engine.prepare(modelDir: modelDir, python: python) { stageName, fraction in
                Task { @MainActor in
                    switch stageName {
                    case "downloading": self.stage = .downloadingModel(fraction)
                    case "verifying": self.stage = .verifying
                    default: self.stage = .loading
                    }
                    model.setRecognizerState(.installing(stage: stageName, fraction: fraction))
                }
            }
            engine.stop()
            stage = .done
            model.restartRecognizer()
        } catch is CancellationError {
            stage = .cancelled
            model.warmUpRecognizer()
        } catch {
            stage = .failed(Self.describe(error))
            model.setRecognizerState(WhisperInstallation.current() == nil ? .notInstalled : .failed(Self.describe(error)))
            Log.error("runtime install failed: \(error)")
        }
    }

    /// Parakeet: its own environment from the hashed lock, then the model through the worker
    /// (checksum verified). The Whisper runtime is not touched.
    static let parakeetRuntimeBytes: Int64 = 560_000_000

    func installParakeet(model: AppModel) {
        guard !isRunning else { return }
        target = ModelCatalog.parakeet.id
        task = Task { await runParakeet(model: model) }
    }

    private func runParakeet(model: AppModel) async {
        do {
            stage = .checkingSpace
            let needsRuntime = !ParakeetInstallation.runtimeReady()
            let needsModel = !ParakeetInstallation.modelPresent()
            let needed = (needsRuntime ? Self.parakeetRuntimeBytes : 0) + (needsModel ? ModelCatalog.parakeet.downloadBytes : 0) + 300_000_000
            if Self.freeSpace() < needed { throw InstallError.space(needed) }
            if needsRuntime {
                let uv = try await ensureUV()
                try Task.checkCancellation()
                stage = .installingPython
                var env = uvEnvironment()
                try await runProcess(uv, ["venv", "--python", "3.11", "--seed", "--allow-existing", Paths.parakeetRuntime.path], env: env)
                try Task.checkCancellation()
                stage = .installingPackages
                guard let lock = Bundle.main.url(forResource: "requirements-parakeet", withExtension: "lock") else { throw InstallError.missingResource }
                env["UV_NO_CONFIG"] = "1"
                try await runProcess(uv, ["pip", "install", "--python", ParakeetInstallation.python.path, "--require-hashes", "--no-deps", "-r", lock.path], env: env)
            }
            try Task.checkCancellation()
            stage = needsModel ? .downloadingModel(nil) : .loading
            let engine = WhisperEngine()
            try await engine.prepare(modelDir: ParakeetInstallation.modelDir, python: ParakeetInstallation.python) { stageName, fraction in
                Task { @MainActor in
                    switch stageName {
                    case "downloading": self.stage = .downloadingModel(fraction)
                    case "verifying": self.stage = .verifying
                    default: self.stage = .loading
                    }
                }
            }
            engine.stop()
            stage = .done
            model.warmUpParakeetIfUsed()
        } catch is CancellationError {
            stage = .cancelled
        } catch {
            stage = .failed(Self.describe(error))
            Log.error("parakeet install failed: \(error)")
        }
    }

    static func removeParakeet() {
        for url in [Paths.parakeetRuntime, ParakeetInstallation.modelDir] { try? FileManager.default.removeItem(at: url) }
    }

    enum InstallError: Error {
        case space(Int64)
        case download
        case checksum
        case missingResource
        case step(String)
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case InstallError.space(let bytes): return tr("install.error.space", ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        case InstallError.download: return tr("install.error.download")
        case InstallError.checksum: return tr("install.error.checksum")
        case InstallError.step(let s): return tr("install.error.step", s)
        case let e as RecognizerError: return AppModel.message(for: e)
        default: return tr("install.error.generic")
        }
    }

    private func uvEnvironment() -> [String: String] {
        var env: [String: String] = [:]
        for key in ["HOME", "PATH", "TMPDIR"] { env[key] = ProcessInfo.processInfo.environment[key] }
        env["UV_PYTHON_INSTALL_DIR"] = Self.tools.appendingPathComponent("python").path
        env["UV_CACHE_DIR"] = Paths.cache.appendingPathComponent("uv").path
        env["UV_PYTHON_PREFERENCE"] = "only-managed"
        return env
    }

    /// Downloads the pinned uv release and checks its SHA-256 before use.
    private func ensureUV() async throws -> URL {
        let binary = Self.tools.appendingPathComponent("uv-\(Self.uvVersion)/uv")
        if FileManager.default.isExecutableFile(atPath: binary.path) { return binary }
        stage = .downloadingTool(nil)
        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        let url = URL(string: "https://github.com/astral-sh/uv/releases/download/\(Self.uvVersion)/uv-aarch64-apple-darwin.tar.gz")!
        let (file, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw InstallError.download }
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == Self.uvSHA256 else { throw InstallError.checksum }
        let archive = binary.deletingLastPathComponent().appendingPathComponent("uv.tar.gz")
        try? FileManager.default.removeItem(at: archive)
        try FileManager.default.moveItem(at: file, to: archive)
        try await runProcess(URL(fileURLWithPath: "/usr/bin/tar"), ["-xzf", archive.path, "-C", binary.deletingLastPathComponent().path, "--strip-components", "1"], env: [:])
        try? FileManager.default.removeItem(at: archive)
        guard FileManager.default.isExecutableFile(atPath: binary.path) else { throw InstallError.step("uv") }
        return binary
    }

    private func runProcess(_ executable: URL, _ arguments: [String], env: [String: String]) async throws {
        let p = Process()
        p.executableURL = executable
        p.arguments = arguments
        if !env.isEmpty { p.environment = env }
        let errors = Pipe()
        p.standardError = errors
        p.standardOutput = FileHandle.nullDevice
        process = p
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            p.terminationHandler = { proc in
                if proc.terminationStatus == 0 { c.resume() }
                else {
                    let tail = String(decoding: errors.fileHandleForReading.readDataToEndOfFile().suffix(600), as: UTF8.self)
                    Log.error("\(executable.lastPathComponent) failed: \(tail)")
                    c.resume(throwing: proc.terminationReason == .uncaughtSignal ? CancellationError() : InstallError.step(executable.lastPathComponent))
                }
            }
            do { try p.run() } catch { c.resume(throwing: error) }
        }
        process = nil
    }

    /// Removes only what this app installed. A Govori installation used in place is never touched.
    static func removeOwnInstallation() {
        for url in [Paths.runtime, tools] + ModelCatalog.whisper.map(ownModelDir) { try? FileManager.default.removeItem(at: url) }
    }

    static func ownModelDir(_ model: SpeechModel) -> URL { Paths.models.appendingPathComponent(model.folder ?? "unknown") }

    /// Removes one downloaded model of Saywell's own (never a shared Govori folder).
    static func removeOwnModel(_ model: SpeechModel) {
        guard model.folder != nil else { return }
        try? FileManager.default.removeItem(at: ownModelDir(model))
    }

    static func ownInstallationSize() -> Int64 {
        ([Paths.runtime, tools] + ModelCatalog.whisper.map(ownModelDir)).reduce(0) { $0 + directorySize($1) }
    }

    static func directorySize(_ url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in e { total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0) }
        return total
    }
}
