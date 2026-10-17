import Foundation
import Testing
@testable import SaidrightCore

@Suite struct Modes {
    @Test func starterModesAreDistinct() {
        let modes = ModePresets.starter(names: [:], spoken: ["ru", "en"])
        #expect(modes.count == 4)
        let message = modes.first { $0.presetID == ModePresets.messageID }!
        let prompt = modes.first { $0.presetID == ModePresets.promptID }!
        let original = modes.first { $0.presetID == ModePresets.originalID }!
        #expect(message.cleanup == .light && message.learning == .off)
        #expect(prompt.cleanup == .correct && prompt.learning == .hint)
        #expect(!original.needsProviderAutomatically)
    }

    @Test func persistRoundTrip() throws {
        var library = ModeLibrary(modes: ModePresets.starter(names: [:], spoken: ["ru"]))
        library.activateNext()
        let data = try JSONEncoder().encode(library)
        let back = try JSONDecoder().decode(ModeLibrary.self, from: data)
        #expect(back == library)
    }

    @Test func duplicateRenameDelete() {
        var library = ModeLibrary(modes: ModePresets.starter(names: [:], spoken: ["ru"]))
        let first = library.modes[0]
        let copy = library.duplicate(first.id, suffix: "copy")!
        #expect(copy.name == "Message copy")
        #expect(copy.id != first.id)
        var renamed = copy
        renamed.name = "   "
        library.update(renamed)
        #expect(library.modes.first { $0.id == copy.id }?.name == "Message copy")
        library.setActive(copy.id)
        check(library.delete(copy.id))
        #expect(library.activeModeID != copy.id)
    }

    @Test func cannotDeleteLastMode() {
        var library = ModeLibrary(modes: [ModePresets.starter(names: [:], spoken: [])[0]])
        check(!library.delete(library.modes[0].id))
    }

    @Test func importNeverOverwrites() throws {
        var library = ModeLibrary(modes: ModePresets.starter(names: [:], spoken: ["ru"]))
        let data = try library.export([library.modes[0].id])
        let before = library.modes
        let added = try library.importModes(from: data)
        #expect(added.count == 1)
        #expect(library.modes.prefix(before.count).elementsEqual(before))
        #expect(added[0].id != before[0].id)
        #expect(added[0].name == "Message 2")
    }

    @Test func exportContainsNoSecretsFields() throws {
        let library = ModeLibrary(modes: ModePresets.starter(names: [:], spoken: ["ru"]))
        let text = String(data: try library.export(library.modes.map(\.id)), encoding: .utf8)!
        #expect(!text.lowercased().contains("key"))
        #expect(!text.contains("sk-"))
    }

    @Test func resetRestoresPresetButKeepsIdentity() {
        var mode = ModePresets.starter(names: [:], spoken: ["ru", "en"])[1]
        mode.name = "My prompt"
        mode.cleanup = .rewrite
        mode.learning = .off
        let reset = ModePresets.reset(mode)
        #expect(reset.id == mode.id && reset.name == "My prompt")
        #expect(reset.cleanup == .correct && reset.learning == .hint)
    }

    @Test func cycleWraps() {
        var library = ModeLibrary(modes: ModePresets.starter(names: [:], spoken: []))
        for _ in 0..<library.modes.count { library.activateNext() }
        #expect(library.activeModeID == library.modes[0].id)
    }
}

@Suite struct Retention {
    func record(daysAgo: Double, audio: String?) -> DictationRecord {
        DictationRecord(id: UUID(), date: Date(timeIntervalSince1970: 1_000_000 - daysAgo * 86_400), modeName: "M", modeSymbol: "m", raw: "t", edited: nil, detectedLanguage: nil, audioFile: audio, timing: .init(), delivery: "kept")
    }

    @Test func audioExpiresIndependentlyOfText() {
        var store = HistoryStore()
        store.records = [record(daysAgo: 1, audio: "a.wav"), record(daysAgo: 10, audio: "b.wav")]
        let deleted = store.applyRetention(RetentionPolicy(), now: Date(timeIntervalSince1970: 1_000_000))
        #expect(deleted == ["b.wav"])
        #expect(store.records.count == 2)
        #expect(store.records[1].audioFile == nil)
    }

    @Test func textOffRemovesEverything() {
        var store = HistoryStore()
        store.records = [record(daysAgo: 0, audio: "a.wav")]
        var policy = RetentionPolicy()
        policy.keepText = false
        check(store.applyRetention(policy, now: Date(timeIntervalSince1970: 1_000_000)) == ["a.wav"])
        #expect(store.records.isEmpty)
    }

    @Test func onlyOwnRecordingNamesAreDeletable() {
        #expect(RecordingFiles.isOwnRecording(UUID().uuidString + ".wav"))
        #expect(!RecordingFiles.isOwnRecording("../library.json"))
        #expect(!RecordingFiles.isOwnRecording("notes.wav"))
        #expect(!RecordingFiles.isOwnRecording("x/" + UUID().uuidString + ".wav"))
    }
}

@Suite struct Settings {
    @Test func unknownFieldsAndMissingFieldsAreTolerated() throws {
        var s = AppSettings()
        s.capsule.glow = 0.2
        s.hotkeys.bareModifierEnabled = false
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        object["futureField"] = 42
        var capsule = object["capsule"] as! [String: Any]
        capsule.removeValue(forKey: "placement")
        object["capsule"] = capsule
        let decoded = AppSettings.decode(try JSONSerialization.data(withJSONObject: object))
        #expect(decoded.capsule.glow == 0.2)
        #expect(decoded.capsule.placement == .bottom)
        #expect(decoded.hotkeys.bareModifierEnabled == false)
    }

    @Test func olderCapsuleColoursBecomeCustomPalette() throws {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as! [String: Any]
        var capsule = object["capsule"] as! [String: Any]
        capsule.removeValue(forKey: "palette")
        capsule.removeValue(forKey: "motion")
        capsule["recordingColor"] = 0x2FD3C1
        capsule["reduceMotion"] = true
        object["capsule"] = capsule
        let decoded = AppSettings.decode(try JSONSerialization.data(withJSONObject: object))
        #expect(decoded.capsule.palette == .custom)
        #expect(decoded.capsule.resolvedColors.recording == 0x2FD3C1)
        #expect(decoded.capsule.motion == .minimal)
        // Untouched defaults get the new coordinated palette.
        let fresh = AppSettings.decode(try JSONEncoder().encode(AppSettings()))
        #expect(fresh.capsule.palette == .signal)
        #expect(fresh.learningUI == LearningPresentation())
    }
}

@Suite struct Legacy {
    @Test func govoriLibraryImports() throws {
        let sessionID = UUID()
        let legacy: [String: Any] = [
            "sessions": [[
                "id": sessionID.uuidString, "date": 700_000_000.0, "mode": "practice", "raw": "I go home", "corrected": "I went home",
                "lesson": ["corrected": "I went home", "corrections": [["before": "go", "after": "went", "category": "Tenses", "explanation": "прошедшее", "uncertain": false]], "naturalAlternative": "", "tip": "t", "exercise": "I ___ home.", "answer": "I went home."],
                "audioPath": "/tmp/old.wav", "duration": 2.0, "recognitionTime": 0.5, "verified": true,
            ]],
            "cards": [["id": UUID().uuidString, "question": "q", "answer": "a", "explanation": "e", "due": 700_000_000.0, "interval": 3]],
        ]
        let result = try LegacyImport.parse(JSONSerialization.data(withJSONObject: legacy), practiceName: "Practice", dictationName: "Dictation")
        #expect(result.records.count == 1)
        #expect(result.records[0].id == sessionID)
        #expect(result.records[0].transcriptConfirmed)
        #expect(result.records[0].feedback?.items.first?.suggestion == "went")
        #expect(result.records[0].feedback?.items.first?.topic == "Tenses")
        #expect(result.cards.first?.intervalDays == 3)
        #expect(result.audioToCopy.values.contains("/tmp/old.wav"))
        #expect(RecordingFiles.isOwnRecording(result.records[0].audioFile!))
    }
}

@Suite struct Diff {
    @Test func wordLevel() {
        let segments = TextDiff.compare("I go to shop", "I went to the shop")
        #expect(segments.contains(.removed("go")))
        #expect(segments.contains(.added("went")))
        #expect(segments.contains { if case .added(let s) = $0 { return s.contains("the") } else { return false } })
    }

    @Test func chineseIsComparedPerCharacter() {
        let segments = TextDiff.compare("我昨天去商店", "我昨天去了商店")
        #expect(segments.contains(.added("了")))
    }

    @Test func punctuationIsVisible() {
        #expect(TextDiff.compare("привет как дела", "привет, как дела?").contains(.added(",")))
    }

    @Test func noChange() { #expect(!TextDiff.hasChanges("same text", "same text")) }
}

@Suite struct Worker {
    @Test func linesSurvivePartialReads() {
        var buffer = LineBuffer()
        check(buffer.append(Data("{\"id\":\"1\",\"ty".utf8)).isEmpty)
        let lines = buffer.append(Data("pe\":\"pong\"}\n{\"id\":\"2\"".utf8))
        #expect(lines.count == 1)
        #expect(WorkerProtocol.decode(line: lines[0]) == .pong(id: "1", modelLoaded: false))
    }

    @Test func transcriptDecodes() {
        let line = Data(#"{"id":"a","type":"transcript","text":"Привет, world","languages":["ru","en"],"seconds":0.7,"cold":false,"segments":2}"#.utf8)
        #expect(WorkerProtocol.decode(line: line) == .transcript(id: "a", text: "Привет, world", languages: ["ru", "en"], seconds: 0.7, cold: false, segments: 2))
    }

    @Test func garbageIsIgnored() {
        #expect(WorkerProtocol.decode(line: Data("Loading weights…".utf8)) == nil)
    }

    @Test func timeoutScalesWithAudio() {
        #expect(WorkerProtocol.timeout(audioSeconds: 60, cold: false) > WorkerProtocol.timeout(audioSeconds: 5, cold: false))
        #expect(WorkerProtocol.timeout(audioSeconds: 5, cold: true) > WorkerProtocol.timeout(audioSeconds: 5, cold: false))
    }
}

@Suite struct Languages {
    @Test func systemLanguageResolution() {
        #expect(UILanguage.system.resolved(preferred: ["de-AT", "en"]) == .de)
        #expect(UILanguage.system.resolved(preferred: ["zh-Hans-CN"]) == .zhHans)
        #expect(UILanguage.system.resolved(preferred: ["zh-Hant-TW", "ru-RU"]) == .ru)
        #expect(UILanguage.system.resolved(preferred: ["fi-FI"]) == .en)
        #expect(UILanguage.ru.resolved(preferred: ["de"]) == .ru)
    }

    @Test func catalogMapsWhisperCodes() {
        #expect(LanguageCatalog.fromWhisper("zh")?.id == "zh-Hans")
        #expect(LanguageCatalog.info("ar")?.isRightToLeft == true)
    }
}
