import Testing

/// `#expect` cannot wrap calls to mutating methods; evaluate first, then check.
func check(_ condition: Bool, _ comment: Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(condition, comment, sourceLocation: sourceLocation)
}
