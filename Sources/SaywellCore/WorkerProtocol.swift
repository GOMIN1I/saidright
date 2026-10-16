import Foundation

/// JSON-lines protocol between the app and the local recogniser process.
/// Every request carries an id; every reply echoes it. Replies for an id the app no
/// longer waits for are dropped, so a slow or cancelled request cannot leak into a new one.
public enum WorkerProtocol {
    public struct TranscribeRequest: Codable, Equatable, Sendable {
        public var id: String
        public var command = "transcribe"
        public var path: String
        /// Whisper codes. Empty = detect among all; one = fixed; several = detect among these.
        public var languages: [String]
        /// Vocabulary passed as context to bias recognition.
        public var prompt: String?

        public init(id: String, path: String, languages: [String], prompt: String?) {
            self.id = id
            self.path = path
            self.languages = languages
            self.prompt = prompt
        }
    }

    public struct SimpleRequest: Codable, Equatable, Sendable {
        public var id: String
        public var command: String
        public init(id: String, command: String) { self.id = id; self.command = command }
    }

    public enum Reply: Equatable, Sendable {
        case progress(id: String, stage: String, fraction: Double?)
        case transcript(id: String, text: String, languages: [String], seconds: Double, cold: Bool, segments: Int)
        case ready(id: String, seconds: Double)
        case failure(id: String, code: String, message: String)
        case pong(id: String, modelLoaded: Bool)
    }

    public static func encode<T: Encodable>(_ request: T) throws -> Data {
        var data = try JSONEncoder().encode(request)
        data.append(0x0A)
        return data
    }

    public static func decode(line: Data) -> Reply? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let id = object["id"] as? String, let type = object["type"] as? String else { return nil }
        switch type {
        case "progress":
            return .progress(id: id, stage: object["stage"] as? String ?? "", fraction: object["fraction"] as? Double)
        case "transcript":
            return .transcript(id: id, text: object["text"] as? String ?? "", languages: object["languages"] as? [String] ?? [], seconds: object["seconds"] as? Double ?? 0, cold: object["cold"] as? Bool ?? false, segments: object["segments"] as? Int ?? 0)
        case "ready":
            return .ready(id: id, seconds: object["seconds"] as? Double ?? 0)
        case "error":
            return .failure(id: id, code: object["code"] as? String ?? "unknown", message: String((object["message"] as? String ?? "").prefix(400)))
        case "pong":
            return .pong(id: id, modelLoaded: object["model_loaded"] as? Bool ?? false)
        default:
            return nil
        }
    }

    /// Generous but bounded time for a transcription: model load plus ~1.5× real time.
    public static func timeout(audioSeconds: Double, cold: Bool) -> TimeInterval {
        (cold ? 90 : 20) + audioSeconds * 1.5
    }
}

/// Splits a byte stream into lines without losing partial data between reads.
public struct LineBuffer: Sendable {
    private var buffer = Data()
    public init() {}

    public mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        while let index = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<index]
            if !line.isEmpty { lines.append(Data(line)) }
            buffer.removeSubrange(buffer.startIndex...index)
        }
        // A runaway line without a newline is a protocol error; cap memory.
        if buffer.count > 4_000_000 { buffer.removeAll() }
        return lines
    }
}
