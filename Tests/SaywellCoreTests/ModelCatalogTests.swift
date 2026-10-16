import Foundation
import Testing
@testable import SaywellCore

@Suite struct ModelChoice {
    let gb: UInt64 = 1_073_741_824

    @Test func mixedOrNonEnglishGetsTheLargeModel() {
        #expect(ModelCatalog.recommendedWhisper(spokenLanguages: ["ru", "en"], physicalMemory: 8 * gb).id == ModelCatalog.whisperTurbo.id)
        #expect(ModelCatalog.recommendedWhisper(spokenLanguages: ["de"], physicalMemory: 8 * gb).id == ModelCatalog.whisperTurbo.id)
    }

    @Test func englishOnlyOnSmallMacGetsTheSmallModel() {
        #expect(ModelCatalog.recommendedWhisper(spokenLanguages: ["en"], physicalMemory: 8 * gb).id == ModelCatalog.whisperSmall.id)
        #expect(ModelCatalog.recommendedWhisper(spokenLanguages: ["en"], physicalMemory: 24 * gb).id == ModelCatalog.whisperTurbo.id)
    }

    @Test func whisperEntriesArePinned() {
        for m in ModelCatalog.whisper {
            #expect(m.repo != nil && m.folder != nil)
            #expect(m.revision?.count == 40)
            #expect(m.downloadBytes > 0)
        }
    }

    @Test func parakeetFitsOneEuropeanLanguage() {
        #expect(ModelCatalog.parakeetFit(spokenLanguages: ["ru"]) == .good)
        #expect(ModelCatalog.parakeetFit(spokenLanguages: ["ru", "en"]) == .switchesRisky)
        #expect(ModelCatalog.parakeetFit(spokenLanguages: ["zh-Hans"]) == .unsupported(["zh-Hans"]))
        #expect(ModelCatalog.parakeetFit(spokenLanguages: []) == .unsupported([]))
    }

    @Test func olderModesStillDecodeAndNewChoiceRoundTrips() throws {
        var mode = ModePresets.starter(names: [:], spoken: ["ru"])[0]
        mode.recognizer = .parakeet
        let back = try JSONDecoder().decode(Mode.self, from: JSONEncoder().encode(mode))
        #expect(back.recognizer == .parakeet)
    }

    @Test func autoUsesParakeetOnlyForOneSupportedLanguage() {
        #expect(RecognizerChoice.auto.resolved(spokenLanguages: ["en"], parakeetInstalled: true) == .parakeet)
        #expect(RecognizerChoice.auto.resolved(spokenLanguages: ["ru", "en"], parakeetInstalled: true) == .whisper)
        #expect(RecognizerChoice.auto.resolved(spokenLanguages: ["zh-Hans"], parakeetInstalled: true) == .whisper)
        #expect(RecognizerChoice.auto.resolved(spokenLanguages: ["en"], parakeetInstalled: false) == .whisper)
        #expect(RecognizerChoice.whisper.resolved(spokenLanguages: ["en"], parakeetInstalled: true) == .whisper)
    }
}
