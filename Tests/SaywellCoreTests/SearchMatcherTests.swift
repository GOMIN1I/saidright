import Testing
@testable import SaywellCore

@Suite struct SearchMatching {
    private func s(_ query: String, _ fields: [(String, Int)]) -> Int? {
        SearchMatcher.score(query: query, fields: fields.map { SearchMatcher.Field($0.0, weight: $0.1) })
    }

    @Test func everyWordMustMatchAsPrefix() {
        #expect(s("input dev", [("Input device", 3)]) != nil)
        #expect(s("input mouse", [("Input device", 3)]) == nil)
        #expect(s("put", [("Input device", 3)]) == nil)
    }

    @Test func caseDiacriticsAndYoAreIgnored() {
        #expect(s("ЗВУК", [("Звуки", 3)]) != nil)
        #expect(s("еще", [("Ещё раз", 3)]) != nil)
        #expect(s("uber", [("Über Saywell", 3)]) != nil)
    }

    @Test func titleRanksAboveDetail() {
        let title = s("microphone", [("Microphone", 3), ("Choose the input", 1)])!
        let detail = s("microphone", [("Input device", 3), ("Which microphone to record from", 1)])!
        #expect(title > detail)
    }

    @Test func chineseMatchesWithoutSpaces() {
        #expect(s("麦克风", [("输入设备", 3), ("选择麦克风", 1)]) != nil)
        #expect(s("键盘", [("输入设备", 3)]) == nil)
    }

    @Test func emptyQueryMatchesNothing() {
        #expect(s("  ", [("Anything", 3)]) == nil)
    }
}
