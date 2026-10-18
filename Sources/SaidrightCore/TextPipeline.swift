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
        // A light edit of a short, already clean phrase returns it unchanged; skipping the
        // request saves the whole provider round trip (eval/results/2026-10-18-editing-speed.md).
        if lightEditIsNoOp(text, mode: mode) { return EditResult(output: text, edited: text, issues: [], failure: nil) }
        do {
            let client = try provider()
            // Layout is asked for at the same time as the edit, on the transcript itself; the
            // answer is used only if it also fits the edited text (see `structure`).
            let early: Task<String?, Never>? = mode.rules.smartStructure && SmartStructure.worthAsking(text)
                ? Task { try? await requestLayout(text, mode: mode, provider: client) } : nil
            let answer: String
            do { answer = try await client.complete(system: EditorPrompt.system(for: mode), user: EditorPrompt.wrap(text), maxOutputTokens: max(256, text.count * 2 + 200)) } catch { early?.cancel(); throw error }
            let edited = EditorPrompt.unwrap(answer)
            let report = IntegrityReport.check(raw: text, edited: edited, level: mode.cleanup)
            if report.reject { early?.cancel(); return EditResult(output: text, edited: nil, issues: report.issues, failure: .rejected(report.issues)) }
            let shaped = mode.rules.smartStructure ? await structure(edited, raw: text, mode: mode, provider: client, early: await early?.value) : edited
            return EditResult(output: shaped, edited: shaped, issues: report.issues, failure: nil)
        } catch let error as ProviderError {
            return EditResult(output: text, edited: nil, issues: [], failure: .provider(error))
        } catch {
            return EditResult(output: text, edited: nil, issues: [], failure: .provider(.network("\(type(of: error))")))
        }
    }

    /// Longest phrase the light level may pass through without asking the editor. Longer
    /// recognised sentences sometimes miss a comma the editor would add.
    static let noOpMaxWords = 12

    /// Hesitation fillers and spoken commands the light level acts on, matched as whole words.
    static let lightEditTriggers: Set<String> = [
        "uh", "um", "umm", "uhm", "erm", "hmm", "mm", "э", "ээ", "эээ", "эм", "мм", "ммм", "ну", "короче", "типа", "вот",
        "äh", "ähm", "öhm", "嗯", "呃", "额",
        "paragraph", "line", "bullet", "абзац", "строки", "absatz", "换行",
    ]

    /// True when the light level could not change anything: a short phrase that starts with a
    /// capital, ends with sentence punctuation, and has no filler, immediate repetition or spoken
    /// formatting command. Recognition already punctuates, so the editor would return it as is.
    static func lightEditIsNoOp(_ text: String, mode: Mode) -> Bool {
        guard mode.cleanup == .light, mode.extraInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty, words.count <= noOpMaxWords, !text.contains("\n") else { return false }
        guard let first = text.first(where: \.isLetter), first.isUppercase, let last = text.last, ".?!…".contains(last) else { return false }
        if mode.rules.smartStructure && SmartStructure.worthAsking(text) { return false }
        let bare = words.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        if bare.contains(where: { lightEditTriggers.contains($0) || $0.hasPrefix("э-") }) { return false }
        if zip(bare, bare.dropFirst()).contains(where: { $0 == $1 && !$0.isEmpty }) { return false }
        return true
    }

    /// Smart formatting after an accepted edit. Any problem keeps the prose edit.
    /// `early` is a layout answer for the raw transcript, requested in parallel with the edit.
    /// It is used when it passes every check against the edited text (so a word the editor
    /// corrected sends the request again), or when it says "prose" and the edit changed only
    /// punctuation and capitals. Otherwise the layout is asked for the edited text as before.
    static func structure(_ edited: String, raw: String, mode: Mode, provider: TextProvider, early: String? = nil) async -> String {
        guard SmartStructure.worthAsking(edited) else { return edited }
        if let early {
            if let rendered = layoutResult(early, edited: edited, raw: raw, mode: mode), rendered != edited { return rendered }
            if !early.contains("\"structured\""), !SmartStructure.requestsTable(edited), sameWords(raw, edited) { return edited }
        }
        // One more try only when the model wanted structure but its answer failed the checks
        // (small local models sometimes drop or repeat a sentence).
        for _ in 0..<2 {
            guard let json = try? await requestLayout(edited, mode: mode, provider: provider) else { return edited }
            if let rendered = layoutResult(json, edited: edited, raw: raw, mode: mode) { return rendered }
            // A spoken table request deserves the second try even when the model said "prose".
            guard json.contains("\"structured\"") || SmartStructure.requestsTable(edited) else { return edited }
        }
        return edited
    }

    static func requestLayout(_ text: String, mode: Mode, provider: TextProvider) async throws -> String {
        try await provider.completeJSON(system: SmartStructure.system(allowTitle: mode.cleanup != .light, table: SmartStructure.requestsTable(text)), user: EditorPrompt.wrap(text), schemaName: "layout", schema: SmartStructure.schema, maxOutputTokens: max(400, text.count * 3 + 300))
    }

    /// The rendered layout when it is valid for the edited text, else nil.
    static func layoutResult(_ json: String, edited: String, raw: String, mode: Mode) -> String? {
        guard let layout = SmartStructure.parse(json, source: edited, allowTitle: mode.cleanup != .light) else { return nil }
        let rendered = SmartStructure.render(title: layout.title, blocks: layout.blocks)
        return IntegrityReport.check(raw: raw, edited: rendered, level: mode.cleanup).reject ? edited : rendered
    }

    /// Same words in the same order, ignoring punctuation and capitals.
    static func sameWords(_ a: String, _ b: String) -> Bool {
        func words(_ s: String) -> [String] { s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init) }
        return words(a) == words(b)
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
