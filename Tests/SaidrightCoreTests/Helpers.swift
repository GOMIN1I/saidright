import Testing
@testable import SaidrightCore

/// `#expect` cannot wrap calls to mutating methods; evaluate first, then check.
func check(_ condition: Bool, _ comment: Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(condition, comment, sourceLocation: sourceLocation)
}

extension ProviderSettings {
    /// OpenAI (Responses API), as the editing tests were written for; the app default is Groq.
    static var openAITest: ProviderSettings {
        var s = ProviderSettings()
        s.kind = .openAI
        return s
    }
}
