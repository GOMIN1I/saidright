import Foundation
import Testing
@testable import SaywellCore

private func json(_ object: Any) -> String { String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)! }

private func item(_ original: String, _ suggestion: String, kind: String = "grammar", uncertain: Bool = false) -> [String: Any] {
    ["original": original, "suggestion": suggestion, "kind": kind, "explanation": "e", "rule": "r", "example": "x", "uncertain": uncertain, "topic": "past simple"]
}

@Suite struct FeedbackValidation {
    let transcript = "Yesterday I go to the shop and buy some milk."

    @Test func validFeedbackIsKept() throws {
        let raw = json(["corrected": "Yesterday I went to the shop and bought some milk.", "items": [item("I go", "I went"), item("buy", "bought")], "alternative": "", "practice": ["kind": "gap", "prompt": "Yesterday I ___ (go) home.", "answer": "Yesterday I went home."]])
        let f = try FeedbackValidator.parse(raw, transcript: transcript, learningLanguage: "en", explanationLanguage: "ru", level: .detailed)
        #expect(f.items.count == 2)
        #expect(f.discarded == 0)
        #expect(f.practice != nil)
    }

    @Test func fabricatedQuoteIsDropped() throws {
        let raw = json(["corrected": transcript, "items": [item("I goes", "I went")], "alternative": "", "practice": NSNull()])
        let f = try FeedbackValidator.parse(raw, transcript: transcript, learningLanguage: "en", explanationLanguage: "ru", level: .detailed)
        #expect(f.items.isEmpty)
        #expect(f.discarded == 1)
    }

    @Test func unknownCategoryIsDropped() throws {
        let raw = json(["corrected": transcript, "items": [item("I go", "I went", kind: "pronunciation")], "alternative": "", "practice": NSNull()])
        let f = try FeedbackValidator.parse(raw, transcript: transcript, learningLanguage: "en", explanationLanguage: "ru", level: .detailed)
        #expect(f.items.isEmpty)
    }

    @Test func noChangeSuggestionIsDropped() throws {
        let raw = json(["corrected": transcript, "items": [item("the shop", "the shop")], "alternative": "", "practice": NSNull()])
        #expect(try FeedbackValidator.parse(raw, transcript: transcript, learningLanguage: "en", explanationLanguage: "ru", level: .detailed).items.isEmpty)
    }

    @Test func emptyListIsValid() throws {
        let raw = json(["corrected": "All good.", "items": [], "alternative": "", "practice": NSNull()])
        let f = try FeedbackValidator.parse(raw, transcript: "All good.", learningLanguage: "en", explanationLanguage: "ru", level: .hint)
        #expect(f.items.isEmpty)
        #expect(f.practice == nil)
    }

    @Test func hintKeepsOneItem() throws {
        let raw = json(["corrected": transcript, "items": [item("I go", "I went"), item("buy", "bought")], "alternative": "", "practice": NSNull()])
        let f = try FeedbackValidator.parse(raw, transcript: transcript, learningLanguage: "en", explanationLanguage: "ru", level: .hint)
        #expect(f.items.count == 1)
    }

    @Test func malformedJSONThrows() {
        #expect(throws: FeedbackValidator.Failure.malformed) { try FeedbackValidator.parse("{\"items\": 3}", transcript: "x", learningLanguage: "en", explanationLanguage: "ru", level: .detailed) }
        #expect(throws: FeedbackValidator.Failure.malformed) { try FeedbackValidator.parse("not json", transcript: "x", learningLanguage: "en", explanationLanguage: "ru", level: .detailed) }
    }

    @Test func practiceWithoutRealErrorIsDropped() throws {
        let raw = json(["corrected": transcript, "items": [item("some milk", "milk", kind: "style")], "alternative": "", "practice": ["kind": "gap", "prompt": "a ___", "answer": "a b"]])
        let f = try FeedbackValidator.parse(raw, transcript: transcript, learningLanguage: "en", explanationLanguage: "ru", level: .detailed)
        #expect(f.practice == nil)
    }

    @Test func driftedCorrectionIsRebuiltFromItems() throws {
        let raw = json(["corrected": "Completely different long essay text that the model wrote instead of a minimal correction of the sentence at all.", "items": [item("I go", "I went")], "alternative": "", "practice": NSNull()])
        let f = try FeedbackValidator.parse(raw, transcript: transcript, learningLanguage: "en", explanationLanguage: "ru", level: .detailed)
        #expect(f.corrected == "Yesterday I went to the shop and buy some milk.")
    }

    @Test func excerptMatchingToleratesWhitespaceAndCase() {
        #expect(FeedbackValidator.locate("i  GO", in: transcript) != nil)
    }
}

@Suite struct ConfirmedErrors {
    func record(confirmed: Bool, items: [FeedbackItem]) -> DictationRecord {
        DictationRecord(id: UUID(), modeName: "P", modeSymbol: "x", raw: "r", edited: nil, detectedLanguage: "en", audioFile: nil, timing: .init(), delivery: "kept", transcriptConfirmed: confirmed, feedback: Feedback(corrected: "", items: items, alternative: "", practice: nil, learningLanguage: "en", explanationLanguage: "ru"))
    }

    @Test func onlyConfirmedUndisputedCertainErrorsCount() {
        var disputed = FeedbackItem(original: "a", suggestion: "b", kind: .grammar, explanation: "", rule: "", example: "", uncertain: false, topic: "Articles")
        disputed.verdict = .recognitionError
        let certain = FeedbackItem(original: "a", suggestion: "b", kind: .grammar, explanation: "", rule: "", example: "", uncertain: false, topic: "Articles")
        let unsure = FeedbackItem(original: "a", suggestion: "b", kind: .grammar, explanation: "", rule: "", example: "", uncertain: true, topic: "Articles")
        let style = FeedbackItem(original: "a", suggestion: "b", kind: .style, explanation: "", rule: "", example: "", uncertain: false, topic: "Style")
        var store = HistoryStore()
        store.records = [record(confirmed: true, items: [certain, unsure, style, disputed]), record(confirmed: false, items: [certain])]
        let topics = store.confirmedTopics()
        #expect(topics.analysedSessions == 1)
        #expect(topics.topics.count == 1)
        #expect(topics.topics.first?.topic == "articles")
        #expect(topics.topics.first?.count == 1)
    }
}

@Suite struct Review {
    @Test func againComesBackSoon() {
        let card = ReviewCard(language: "en", prompt: "p", answer: "a", explanation: "", source: "", topic: "")
        let now = Date(timeIntervalSince1970: 0)
        let next = ReviewScheduler.schedule(card, grade: .again, now: now)
        #expect(next.due == now.addingTimeInterval(600))
        #expect(next.lapses == 1)
    }

    @Test func goodGrowsAndIsCapped() {
        var card = ReviewCard(language: "en", prompt: "p", answer: "a", explanation: "", source: "", topic: "")
        let now = Date(timeIntervalSince1970: 0)
        var intervals: [Double] = []
        for _ in 0..<12 { card = ReviewScheduler.schedule(card, grade: .good, now: now); intervals.append(card.intervalDays) }
        #expect(intervals[0] == 1)
        #expect(intervals[1] == 3)
        #expect(intervals == intervals.sorted())
        #expect(intervals.last == 120)
    }
}

@Suite struct Tutor {
    @Test func schemaIsStrict() {
        let schema = TutorPrompt.schema
        #expect(schema["additionalProperties"] as? Bool == false)
        let required = Set(schema["required"] as? [String] ?? [])
        let properties = Set((schema["properties"] as? [String: Any] ?? [:]).keys)
        #expect(required == properties)
    }

    @Test func promptNamesLanguagesAndForbidsScores() {
        let p = TutorPrompt.system(learningLanguage: "de", explanationLanguage: "zh-Hans", level: .hint, goal: nil)
        #expect(p.contains("German"))
        #expect(p.contains("Chinese"))
        #expect(p.contains("never assess pronunciation"))
        #expect(p.contains("at most ONE item"))
    }

    @Test func itemSchemaAsksForDetails() {
        let props = (TutorPrompt.schema["properties"] as? [String: Any])?["items"] as? [String: Any]
        let item = props?["items"] as? [String: Any]
        #expect((item?["required"] as? [String])?.contains("details") == true)
    }

    @Test func explanationsArePitchedToTheLearner() {
        let beginner = TutorPrompt.system(learningLanguage: "en", explanationLanguage: "ru", level: .detailed, goal: nil, learner: .beginner, depth: .brief)
        let advanced = TutorPrompt.system(learningLanguage: "en", explanationLanguage: "ru", level: .detailed, goal: nil, learner: .advanced, depth: .thorough)
        #expect(beginner.contains("avoid grammar terms"))
        #expect(advanced.contains("grammar terms are fine"))
        #expect(beginner.contains("one or two short sentences"))
        #expect(advanced.contains("up to three sentences"))
        #expect(beginner.contains("never praise"))
    }

    @Test func detailsAreKeptAndOptional() throws {
        let transcript = "I am agree with you."
        var withDetails = item("I am agree", "I agree")
        withDetails["details"] = "Am ставят перед прилагательными."
        let raw = json(["corrected": "I agree with you.", "items": [withDetails], "alternative": "", "practice": NSNull()])
        let f = try FeedbackValidator.parse(raw, transcript: transcript, learningLanguage: "en", explanationLanguage: "ru", level: .detailed)
        #expect(f.items.first?.details == "Am ставят перед прилагательными.")
        let old = json(["corrected": "I agree with you.", "items": [item("I am agree", "I agree")], "alternative": "", "practice": NSNull()])
        let g = try FeedbackValidator.parse(old, transcript: transcript, learningLanguage: "en", explanationLanguage: "ru", level: .detailed)
        #expect(g.items.first?.details == "")
        // Stored records from before this field still decode.
        let stored = try JSONEncoder().encode(g.items[0])
        var object = try JSONSerialization.jsonObject(with: stored) as! [String: Any]
        object.removeValue(forKey: "details")
        let back = try JSONDecoder().decode(FeedbackItem.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(back.details == "")
    }

    @Test func wholeSentenceSuggestionIsNarrowedToTheChange() throws {
        let transcript = "Yesterday I go to the shop and buy a new microphone."
        var whole = item("I go", "Yesterday I went to the shop and bought a new microphone.")
        whole["details"] = ""
        let raw = json(["corrected": "Yesterday I went to the shop and bought a new microphone.", "items": [whole], "alternative": "", "practice": NSNull()])
        let f = try FeedbackValidator.parse(raw, transcript: transcript, learningLanguage: "en", explanationLanguage: "ru", level: .detailed)
        #expect(f.items.first?.original == "I go to the shop and buy a")
        #expect(f.items.first?.suggestion == "I went to the shop and bought a")
    }

    @Test func detailsInTheWrongLanguageAreDropped() throws {
        var english = item("I am agree", "I agree")
        english["details"] = "Am goes with adjectives that describe you."
        let raw = json(["corrected": "I agree.", "items": [english], "alternative": "", "practice": NSNull()])
        let f = try FeedbackValidator.parse(raw, transcript: "I am agree.", learningLanguage: "en", explanationLanguage: "ru", level: .detailed)
        #expect(f.items.first?.details == "")
        #expect(f.items.count == 1)
    }
}

@Suite struct Scripts {
    @Test func translationIsNotACorrection() {
        #expect(!ScriptGuard.consistent(original: "Сегодня я работаю над новым проектом.", suggestion: "I am working on a new project.", learningLanguage: "en"))
        #expect(ScriptGuard.consistent(original: "I go", suggestion: "I went", learningLanguage: "en"))
        #expect(ScriptGuard.consistent(original: "я пошёл в магазин вчера", suggestion: "вчера я пошёл в магазин", learningLanguage: "ru"))
        #expect(!ScriptGuard.consistent(original: "I go", suggestion: "я иду", learningLanguage: "en"))
        #expect(ScriptGuard.consistent(original: "我去了商店", suggestion: "我去商店了", learningLanguage: "zh-Hans"))
        #expect(ScriptGuard.consistent(original: "Ich gehe gestern", suggestion: "Ich bin gestern gegangen", learningLanguage: "de"))
    }

    @Test func validatorDropsTranslatedItems() throws {
        let transcript = "Сегодня я работаю. Yesterday I go home."
        let json = String(data: try JSONSerialization.data(withJSONObject: [
            "corrected": transcript, "alternative": "", "practice": NSNull(),
            "items": [
                ["original": "Сегодня я работаю.", "suggestion": "Today I am working.", "kind": "grammar", "explanation": "e", "rule": "", "example": "", "uncertain": false, "topic": "t"],
                ["original": "I go", "suggestion": "I went", "kind": "grammar", "explanation": "e", "rule": "", "example": "", "uncertain": false, "topic": "t"],
            ],
        ]), encoding: .utf8)!
        let f = try FeedbackValidator.parse(json, transcript: transcript, learningLanguage: "en", explanationLanguage: "ru", level: .detailed)
        #expect(f.items.map(\.suggestion) == ["I went"])
        #expect(f.discarded == 1)
    }
}

@Suite struct Narrowing {
    @Test func longQuoteIsNarrowedToTheChange() {
        let (a, b) = FeedbackValidator.narrow("Yesterday I go to the shop and buy a new microphone.", "Yesterday I went to the shop and bought a new microphone.")
        #expect(a == "I go to the shop and buy a")
        #expect(b == "I went to the shop and bought a")
    }

    @Test func shortQuoteIsKept() {
        let (a, b) = FeedbackValidator.narrow("I go home", "I went home")
        #expect(a == "I go home" && b == "I went home")
    }

    @Test func singleChangeKeepsOneWordOfContext() {
        let (a, b) = FeedbackValidator.narrow("We discussed about the plan for the next sprint today.", "We discussed the plan for the next sprint today.")
        #expect(a == "discussed about the")
        #expect(b == "discussed the")
    }
}

@Suite struct CapsuleHintSelection {
    private func feedback(_ items: [FeedbackItem]) -> Feedback {
        Feedback(corrected: "", items: items, alternative: "", practice: nil, learningLanguage: "en", explanationLanguage: "ru")
    }
    private func item(_ kind: FeedbackKind, uncertain: Bool = false) -> FeedbackItem {
        FeedbackItem(original: "a", suggestion: "b", kind: kind, explanation: "e", rule: "", example: "", uncertain: uncertain, topic: "")
    }

    @Test func noCorrectionsMeansNoHint() {
        #expect(CapsuleHints.select(feedback([]), level: .detailed, includeUncertain: true).isEmpty)
        #expect(CapsuleHints.select(feedback([item(.punctuation)]), level: .detailed, includeUncertain: true).isEmpty)
    }

    @Test func importantShowsOneConfirmedLearnerError() {
        let f = feedback([item(.style), item(.grammar, uncertain: true), item(.vocabulary), item(.grammar)])
        let picked = CapsuleHints.select(f, level: .hint, includeUncertain: true)
        #expect(picked.count == 1)
        #expect(picked.first?.kind == .vocabulary)
    }

    @Test func broaderAddsStyleAndOptionallyMishearings() {
        let f = feedback([item(.possibleRecognitionError), item(.style), item(.grammar)])
        #expect(CapsuleHints.select(f, level: .detailed, includeUncertain: false).map(\.kind) == [.grammar, .style])
        #expect(CapsuleHints.select(f, level: .detailed, includeUncertain: true).map(\.kind) == [.grammar, .style, .possibleRecognitionError])
    }

    @Test func learningOffShowsNothing() {
        #expect(CapsuleHints.select(feedback([item(.grammar)]), level: .off, includeUncertain: true).isEmpty)
    }
}

@Suite struct ExplanationLanguage {
    private func feedback(_ explanation: String) -> Feedback {
        Feedback(corrected: "", items: [FeedbackItem(original: "a", suggestion: "b", kind: .grammar, explanation: explanation, rule: "", example: "", uncertain: false, topic: "")], alternative: "", practice: nil, learningLanguage: "en", explanationLanguage: "ru")
    }

    @Test func wrongScriptIsDetected() {
        #expect(!TutorPrompt.explanationsMatchLanguage(feedback("You need the past tense."), explanationLanguage: "ru"))
        #expect(TutorPrompt.explanationsMatchLanguage(feedback("Нужно прошедшее время: went."), explanationLanguage: "ru"))
        #expect(TutorPrompt.explanationsMatchLanguage(feedback("需要用过去时 went。"), explanationLanguage: "zh-Hans"))
    }
}
