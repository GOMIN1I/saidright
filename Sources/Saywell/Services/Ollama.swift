import Foundation
import Observation
import SaywellCore

/// A local text model offered for editing and learning feedback through Ollama.
/// Sizes come from the Ollama registry manifests at the time of writing (2026-10-16).
struct LocalTextModel: Identifiable, Equatable {
    var id: String
    var downloadBytes: Int64
    var testedHere: Bool
    /// Thinking models must be asked not to reason for fast, plain answers.
    var needsNoReasoning: Bool
    /// Localized one-line description (keys listed in scripts/check-localization.py).
    var noteKey: String { "ollama." + id.replacingOccurrences(of: ":", with: "_") }

    static let recommended = [
        LocalTextModel(id: "gemma4:e2b", downloadBytes: 4_590_000_000, testedHere: true, needsNoReasoning: true),
        LocalTextModel(id: "qwen3:4b", downloadBytes: 2_500_000_000, testedHere: false, needsNoReasoning: true),
        LocalTextModel(id: "gemma4:e4b", downloadBytes: 6_580_000_000, testedHere: false, needsNoReasoning: true),
    ]
}

/// Talks to a local Ollama server (http://localhost:11434). Only this Mac is contacted;
/// downloads go through Ollama itself, which verifies each layer's SHA-256 digest.
@MainActor @Observable final class OllamaService {
    enum Status: Equatable { case unknown, notRunning, running(version: String) }

    static let base = URL(string: "http://localhost:11434")!
    private(set) var status: Status = .unknown
    private(set) var installed: [String] = []
    private(set) var pulling: String?
    private(set) var fraction: Double?
    private(set) var error: String?
    private var pullTask: Task<Void, Never>?

    func refresh() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.base.appendingPathComponent("api/version"))
            let version = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["version"] as? String ?? "?"
            let (tags, _) = try await URLSession.shared.data(from: Self.base.appendingPathComponent("api/tags"))
            let models = ((try? JSONSerialization.jsonObject(with: tags) as? [String: Any])?["models"] as? [[String: Any]]) ?? []
            installed = models.compactMap { $0["name"] as? String }
            status = .running(version: version)
        } catch {
            status = .notRunning
            installed = []
        }
    }

    func isInstalled(_ id: String) -> Bool { installed.contains(id) || installed.contains(id + ":latest") }

    func pull(_ id: String) {
        guard pulling == nil else { return }
        pulling = id
        fraction = nil
        error = nil
        pullTask = Task { [weak self] in
            await self?.runPull(id)
        }
    }

    func cancel() {
        pullTask?.cancel()
        pullTask = nil
        pulling = nil
        fraction = nil
    }

    private func runPull(_ id: String) async {
        var request = URLRequest(url: Self.base.appendingPathComponent("api/pull"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": id, "stream": true])
        request.timeoutInterval = 3600
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                if let message = object["error"] as? String { error = message; break }
                if let total = object["total"] as? Double, total > 0, let completed = object["completed"] as? Double { fraction = completed / total }
                if (object["status"] as? String) == "success" { break }
            }
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            self.error = tr("ollama.pullFailed")
        }
        pulling = nil
        fraction = nil
        await refresh()
    }

    /// Settings that point Saywell's text features at this Ollama model.
    static func providerSettings(for model: LocalTextModel, keeping current: ProviderSettings) -> ProviderSettings {
        var p = current
        p.kind = .compatible
        p.compatibleBaseURL = base.appendingPathComponent("v1").absoluteString
        p.compatibleModel = model.id
        p.compatibleNoReasoning = model.needsNoReasoning
        return p
    }
}
