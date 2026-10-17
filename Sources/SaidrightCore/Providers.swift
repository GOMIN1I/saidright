import Foundation

/// Where text processing goes. Each provider has its own credential slot; a credential is
/// only ever sent to its own provider's host.
public enum ProviderKind: String, Codable, CaseIterable, Sendable {
    /// api.openai.com, Responses API, strict JSON schema.
    case openAI
    /// Any OpenAI-compatible Chat Completions endpoint (another vendor or a local server).
    case compatible
}

public struct ProviderSettings: Codable, Equatable, Sendable {
    public var kind: ProviderKind = .openAI
    public var openAIModel: String = "gpt-6-luna"
    /// Base URL for a compatible server, e.g. http://localhost:11434/v1
    public var compatibleBaseURL: String = ""
    public var compatibleModel: String = ""
    /// Sends reasoning_effort "none" to compatible servers (Ollama and others honour it);
    /// thinking models otherwise spend the whole token budget before answering.
    public var compatibleNoReasoning: Bool = true
    /// Hard switch: when true, no text provider request may leave the Mac.
    public var localOnly: Bool = false

    public init() {}

    public var model: String { kind == .openAI ? openAIModel : compatibleModel }

    /// Keychain account that holds the credential for the active provider.
    public var credentialAccount: String {
        switch kind {
        case .openAI: "openai"
        case .compatible: "compatible:" + (URL(string: compatibleBaseURL)?.host ?? "unknown")
        }
    }

    public var endpointHost: String? {
        switch kind {
        case .openAI: "api.openai.com"
        case .compatible: URL(string: compatibleBaseURL)?.host
        }
    }

    /// A compatible server on this Mac keeps text local.
    public var isOnDevice: Bool {
        guard kind == .compatible, let host = endpointHost else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

public enum ProviderError: Error, Equatable, Sendable {
    case blockedByLocalOnly
    case missingCredential
    case invalidCredential
    case forbidden
    case modelUnavailable(String)
    case insufficientQuota
    case rateLimited
    case network(String)
    case timeout
    case refused(String)
    case truncated
    case emptyResponse
    case invalidResponse
    case server(Int)
    case invalidConfiguration(String)
    case cancelled
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.invalidResponse }
        return (data, http)
    }
}

/// Sends one text task to the configured provider. No automatic retries: every retry is a
/// visible user action, so a slow response can never be billed twice silently.
public struct TextProvider: Sendable {
    public var settings: ProviderSettings
    public var credential: String?
    public var transport: HTTPTransport
    public var timeout: TimeInterval = 45

    public init(settings: ProviderSettings, credential: String?, transport: HTTPTransport = URLSessionTransport()) {
        self.settings = settings
        self.credential = credential
        self.transport = transport
    }

    /// Plain-text completion (editor).
    public func complete(system: String, user: String, maxOutputTokens: Int = 2000) async throws -> String {
        try await run(system: system, user: user, schema: nil, maxOutputTokens: maxOutputTokens)
    }

    /// Structured completion that must match `schema`.
    public func completeJSON(system: String, user: String, schemaName: String, schema: [String: Any], maxOutputTokens: Int = 2500) async throws -> String {
        try await run(system: system, user: user, schema: (schemaName, schema), maxOutputTokens: maxOutputTokens)
    }

    /// Lists model ids available to this credential (GET /models). Free of charge.
    public func listModels() async throws -> [String] {
        let request = try makeRequest(path: "models", body: nil)
        let (data, response) = try await send(request)
        try Self.check(response, data: data, model: settings.model)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let list = object["data"] as? [[String: Any]] else { throw ProviderError.invalidResponse }
        return list.compactMap { $0["id"] as? String }.sorted()
    }

    func run(system: String, user: String, schema: (String, [String: Any])?, maxOutputTokens: Int) async throws -> String {
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, !model.contains(where: \.isWhitespace) else { throw ProviderError.invalidConfiguration("model") }
        let body: [String: Any]
        switch settings.kind {
        case .openAI:
            var b: [String: Any] = [
                "model": model,
                "instructions": system,
                "input": user,
                "max_output_tokens": maxOutputTokens,
                "store": false,
            ]
            if Self.supportsNoReasoning(model) { b["reasoning"] = ["effort": "none"] }
            if let (name, schema) = schema {
                b["text"] = ["format": ["type": "json_schema", "name": name, "strict": true, "schema": schema]]
            }
            body = b
        case .compatible:
            var b: [String: Any] = [
                "model": model,
                "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
                "max_tokens": maxOutputTokens,
                "temperature": 0.2,
            ]
            if settings.compatibleNoReasoning { b["reasoning_effort"] = "none" }
            if let (name, schema) = schema {
                b["response_format"] = ["type": "json_schema", "json_schema": ["name": name, "strict": true, "schema": schema]]
            }
            body = b
        }
        let request = try makeRequest(path: settings.kind == .openAI ? "responses" : "chat/completions", body: body)
        let (data, response) = try await send(request)
        try Self.check(response, data: data, model: model)
        return try settings.kind == .openAI ? Self.parseResponses(data) : Self.parseChat(data)
    }

    func makeRequest(path: String, body: [String: Any]?) throws -> URLRequest {
        if settings.localOnly && !settings.isOnDevice { throw ProviderError.blockedByLocalOnly }
        let base: String
        switch settings.kind {
        case .openAI: base = "https://api.openai.com/v1/"
        case .compatible:
            var b = settings.compatibleBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: b), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil else { throw ProviderError.invalidConfiguration("baseURL") }
            // Plain HTTP is only acceptable for servers on this Mac.
            if scheme == "http" && !settings.isOnDevice { throw ProviderError.invalidConfiguration("insecureURL") }
            if !b.hasSuffix("/") { b += "/" }
            base = b
        }
        guard let url = URL(string: base + path) else { throw ProviderError.invalidConfiguration("baseURL") }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = (credential ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if settings.kind == .openAI && key.isEmpty { throw ProviderError.missingCredential }
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        return request
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do { return try await transport.send(request) }
        catch is CancellationError { throw ProviderError.cancelled }
        catch let error as ProviderError { throw error }
        catch let error as URLError {
            switch error.code {
            case .cancelled: throw ProviderError.cancelled
            case .timedOut: throw ProviderError.timeout
            default: throw ProviderError.network(error.code.rawValue.description)
            }
        }
    }

    static func supportsNoReasoning(_ model: String) -> Bool {
        model.hasPrefix("gpt-6-luna") || model.hasPrefix("gpt-5")
    }

    static func check(_ response: HTTPURLResponse, data: Data, model: String) throws {
        guard response.statusCode != 200 else { return }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let error = object?["error"] as? [String: Any]
        let code = error?["code"] as? String ?? ""
        switch response.statusCode {
        case 401: throw ProviderError.invalidCredential
        case 403: throw ProviderError.forbidden
        case 404: throw ProviderError.modelUnavailable(model)
        case 400 where code == "model_not_found": throw ProviderError.modelUnavailable(model)
        case 429: throw code == "insufficient_quota" ? ProviderError.insufficientQuota : ProviderError.rateLimited
        default: throw ProviderError.server(response.statusCode)
        }
    }

    static func parseResponses(_ data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProviderError.invalidResponse }
        if (object["status"] as? String) == "incomplete" { throw ProviderError.truncated }
        var text = ""
        for item in object["output"] as? [[String: Any]] ?? [] where (item["type"] as? String) == "message" {
            for part in item["content"] as? [[String: Any]] ?? [] {
                switch part["type"] as? String {
                case "output_text": text += part["text"] as? String ?? ""
                case "refusal": throw ProviderError.refused(String((part["refusal"] as? String ?? "").prefix(200)))
                default: break
                }
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw ProviderError.emptyResponse }
        return trimmed
    }

    static func parseChat(_ data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let choice = (object["choices"] as? [[String: Any]])?.first else { throw ProviderError.invalidResponse }
        if (choice["finish_reason"] as? String) == "length" { throw ProviderError.truncated }
        let message = choice["message"] as? [String: Any]
        if let refusal = message?["refusal"] as? String, !refusal.isEmpty { throw ProviderError.refused(String(refusal.prefix(200))) }
        let text = (message?["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw ProviderError.emptyResponse }
        return text
    }
}
