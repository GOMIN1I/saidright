import Foundation

/// Result of the editing step. The raw transcript is always kept alongside.
public struct EditResult: Equatable, Sendable {
    /// Text to deliver: the edit when accepted, otherwise the raw transcript.
    public var output: String
    /// The editor's text when an edit was attempted and accepted.
    public var edited: String?
    public var issues: [IntegrityReport.Issue]
    /// Set when an edit was attempted and failed or was rejected; output is then raw.
    public var failure: EditFailure?

    public init(output: String, edited: String?, issues: [IntegrityReport.Issue], failure: EditFailure?) {
        self.output = output
        self.edited = edited
        self.issues = issues
        self.failure = failure
    }
}

public enum EditFailure: Equatable, Sendable {
    case provider(ProviderError)
    case rejected([IntegrityReport.Issue])
}

/// Runs the optional editing step for one session. With cleanup off it never touches the
/// provider, which is what makes "no hidden network call" testable.
public enum TextPipeline {
    public static func edit(raw: String, mode: Mode, provider: () throws -> TextProvider) async -> EditResult {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode.cleanup.usesEditor, !text.isEmpty else { return EditResult(output: text, edited: nil, issues: [], failure: nil) }
        do {
            let client = try provider()
            let answer = try await client.complete(system: EditorPrompt.system(for: mode), user: EditorPrompt.wrap(text), maxOutputTokens: max(256, text.count * 2 + 200))
            let edited = EditorPrompt.unwrap(answer)
            let report = IntegrityReport.check(raw: text, edited: edited, level: mode.cleanup)
            if report.reject { return EditResult(output: text, edited: nil, issues: report.issues, failure: .rejected(report.issues)) }
            return EditResult(output: edited, edited: edited, issues: report.issues, failure: nil)
        } catch let error as ProviderError {
            return EditResult(output: text, edited: nil, issues: [], failure: .provider(error))
        } catch {
            return EditResult(output: text, edited: nil, issues: [], failure: .provider(.network("\(type(of: error))")))
        }
    }

    public static func feedback(transcript: String, learningLanguage: String, explanationLanguage: String, level: LearningLevel, goal: String?, learner: LearnerLevel = .intermediate, depth: ExplanationDepth = .brief, provider: TextProvider) async throws -> Feedback {
        let analysisLevel: LearningLevel = level == .hint ? .hint : .detailed
        let system = TutorPrompt.system(learningLanguage: learningLanguage, explanationLanguage: explanationLanguage, level: analysisLevel, goal: goal, learner: learner, depth: depth)
        func ask(_ system: String) async throws -> Feedback {
            let json = try await provider.completeJSON(system: system, user: TutorPrompt.wrap(transcript, explanationLanguage: explanationLanguage), schemaName: "language_feedback", schema: TutorPrompt.schema)
            return try FeedbackValidator.parse(json, transcript: transcript, learningLanguage: learningLanguage, explanationLanguage: explanationLanguage, level: analysisLevel)
        }
        let first: Feedback
        do { first = try await ask(system) } catch ProviderError.truncated {
            // Small models occasionally run on inside the JSON; one more try usually ends cleanly.
            first = try await ask(system)
        }
        // Small local models sometimes explain in the learning language. Translating the few
        // explanation strings is a task they do reliably; it runs after the text was delivered,
        // so it never delays insertion. If it fails, the original explanations are kept.
        guard !TutorPrompt.explanationsMatchLanguage(first, explanationLanguage: explanationLanguage) else { return first }
        if let translated = try? await translateExplanations(first, to: explanationLanguage, provider: provider) { return translated }
        return first
    }

    static func translateExplanations(_ feedback: Feedback, to language: String, provider: TextProvider) async throws -> Feedback {
        var strings: [String] = []
        for item in feedback.items { strings += [item.explanation, item.details, item.rule, item.topic] }
        let name = LanguageCatalog.englishName(language)
        let system = """
        Translate every string of the JSON array in the user message into \(name)\(TutorPrompt.nativeHint(language)). Keep quoted words, example phrases and words of the language being learned exactly as they are. Keep the meaning and the friendly, plain tone. Empty strings stay empty. Return {"strings": [...]} with exactly as many strings, in the same order.
        """
        let input = String(data: try JSONSerialization.data(withJSONObject: strings), encoding: .utf8) ?? "[]"
        let schema: [String: Any] = ["type": "object", "additionalProperties": false, "required": ["strings"], "properties": ["strings": ["type": "array", "items": ["type": "string"]]]]
        let json = try await provider.completeJSON(system: system, user: input, schemaName: "translation", schema: schema)
        guard let data = json.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let out = object["strings"] as? [String], out.count == strings.count else { throw FeedbackValidator.Failure.malformed }
        var result = feedback
        for i in result.items.indices {
            let base = i * 4
            result.items[i].explanation = String(out[base].prefix(600))
            result.items[i].details = String(out[base + 1].prefix(900))
            result.items[i].rule = String(out[base + 2].prefix(300))
            result.items[i].topic = String(out[base + 3].prefix(40))
        }
        guard TutorPrompt.explanationsMatchLanguage(result, explanationLanguage: language) else { throw FeedbackValidator.Failure.malformed }
        return result
    }
}
