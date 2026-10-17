import AppKit
import SaidrightCore

enum Paths {
    static let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    /// SAIDRIGHT_DATA_DIR redirects all of Saidright's own data (QA and fresh-install checks), so
    /// tests never touch the person's history or settings.
    static let root = ProcessInfo.processInfo.environment["SAIDRIGHT_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? appSupport.appendingPathComponent("Saidright", isDirectory: true)
    static let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
    static let runtime = root.appendingPathComponent("Runtime", isDirectory: true)
    /// Separate environment for Parakeet, so installing it never changes the Whisper runtime.
    static let parakeetRuntime = root.appendingPathComponent("Runtime-Parakeet", isDirectory: true)
    static let models = root.appendingPathComponent("Models", isDirectory: true)
    static let cache = root.appendingPathComponent("Cache", isDirectory: true)
    static let logs = root.appendingPathComponent("Logs", isDirectory: true)
    /// Govori 0.2 data. Read-only: never modified or deleted by this app.
    /// SAIDRIGHT_LEGACY_DIR points elsewhere (e.g. an empty folder) to simulate a Mac without Govori.
    static let legacyRoot = ProcessInfo.processInfo.environment["SAIDRIGHT_LEGACY_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? appSupport.appendingPathComponent("Govori", isDirectory: true)

    /// The data folder used while the app was called Saywell (until 0.5.0).
    /// SAIDRIGHT_PREVIOUS_DATA_DIR points elsewhere to test the move on a copy.
    static let previousRoot = ProcessInfo.processInfo.environment["SAIDRIGHT_PREVIOUS_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? appSupport.appendingPathComponent("Saywell", isDirectory: true)

    static func prepare() {
        moveDataFromPreviousName()
        for dir in [root, recordings, models, cache, logs] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: recordings.path)
    }

    /// Moves the Saywell data folder to the new name once (a rename on the same volume: nothing
    /// is copied or deleted). The Python environments inside store absolute paths to their
    /// interpreter, so those links are pointed at the new location afterwards.
    private static func moveDataFromPreviousName() {
        let fm = FileManager.default
        let custom = ProcessInfo.processInfo.environment["SAIDRIGHT_DATA_DIR"] != nil
        let testingMove = ProcessInfo.processInfo.environment["SAIDRIGHT_PREVIOUS_DATA_DIR"] != nil
        guard !custom || testingMove, !fm.fileExists(atPath: root.path), fm.fileExists(atPath: previousRoot.path) else { return }
        // A still-running Saywell would recreate its folder and split the data; it is moved on the
        // next launch after Saywell quits.
        let previousIDs: Set<String> = ["io.github.gomin1i.saywell", "local.saywell.app"]
        if !testingMove && NSWorkspace.shared.runningApplications.contains(where: { previousIDs.contains($0.bundleIdentifier ?? "") }) { return }
        do {
            try fm.moveItem(at: previousRoot, to: root)
        } catch {
            return
        }
        let oldPath = previousRoot.standardizedFileURL.path, newPath = root.standardizedFileURL.path
        for venv in [runtime, parakeetRuntime] {
            let cfg = venv.appendingPathComponent("pyvenv.cfg")
            if let text = try? String(contentsOf: cfg, encoding: .utf8), text.contains(oldPath) {
                try? text.replacingOccurrences(of: oldPath, with: newPath).write(to: cfg, atomically: true, encoding: .utf8)
            }
            let bin = venv.appendingPathComponent("bin")
            for name in (try? fm.contentsOfDirectory(atPath: bin.path)) ?? [] {
                let link = bin.appendingPathComponent(name)
                guard let target = try? fm.destinationOfSymbolicLink(atPath: link.path), target.hasPrefix(oldPath) else { continue }
                try? fm.removeItem(at: link)
                try? fm.createSymbolicLink(atPath: link.path, withDestinationPath: newPath + target.dropFirst(oldPath.count))
            }
        }
    }

    static func recording(_ name: String) -> URL { recordings.appendingPathComponent(name) }

    /// Deletes a recording only if it is one of ours (UUID.wav inside the recordings folder).
    static func deleteRecording(_ name: String) {
        guard RecordingFiles.isOwnRecording(name) else { return }
        let url = recordings.appendingPathComponent(name)
        guard url.deletingLastPathComponent().standardizedFileURL == recordings.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// Atomic JSON persistence with owner-only permissions.
enum JSONFile {
    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: Paths.root.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func data(_ name: String) -> Data? { try? Data(contentsOf: Paths.root.appendingPathComponent(name)) }

    static func save<T: Encodable>(_ value: T, to name: String) {
        let url = Paths.root.appendingPathComponent(name)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(value)
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            Log.error("save \(name) failed: \(type(of: error))")
        }
    }

    /// Keeps a copy of a file that failed to decode instead of overwriting it with defaults.
    static func quarantine(_ name: String) {
        let url = Paths.root.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try? FileManager.default.copyItem(at: url, to: Paths.root.appendingPathComponent("\(name).unreadable-\(stamp)"))
    }
}

/// Minimal diagnostics log. Never receives transcripts, audio, prompts or credentials.
enum Log {
    private static let queue = DispatchQueue(label: "saidright.log")
    private static let file = Paths.logs.appendingPathComponent("saidright.log")

    static func info(_ message: String) { write("INFO", message) }
    static func error(_ message: String) { write("ERROR", message) }

    private static func write(_ level: String, _ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(level) \(message)\n"
        queue.async {
            if let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int, size > 1_000_000 {
                try? FileManager.default.removeItem(at: file.appendingPathExtension("1"))
                try? FileManager.default.moveItem(at: file, to: file.appendingPathExtension("1"))
            }
            if let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: file)
            }
        }
        #if DEBUG
        FileHandle.standardError.write(Data(line.utf8))
        #endif
    }
}
