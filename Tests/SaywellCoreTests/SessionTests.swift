import Foundation
import Testing
@testable import SaywellCore

private func mode() -> Mode { ModePresets.starter(names: [:], spoken: ["ru", "en"])[0] }

@Suite struct SessionLifecycle {
    @Test func normalFlow() {
        var m = SessionMachine()
        let s = SessionSnapshot(mode: mode(), trigger: .hotkey, destination: nil)
        check(m.begin(s))
        check(m.advance(s.id, to: .recording))
        check(m.advance(s.id, to: .transcribing))
        check(m.advance(s.id, to: .editing))
        check(m.advance(s.id, to: .delivering))
        check(m.advance(s.id, to: .finished(.kept)))
        #expect(!m.isBusy)
    }

    @Test func cannotStartWhileBusy() {
        var m = SessionMachine()
        check(m.begin(SessionSnapshot(mode: mode(), trigger: .hotkey, destination: nil)))
        check(!m.begin(SessionSnapshot(mode: mode(), trigger: .hotkey, destination: nil)))
    }

    @Test func staleResultAfterCancelAndRestartIsRejected() {
        var m = SessionMachine()
        let old = SessionSnapshot(mode: mode(), trigger: .hotkey, destination: nil)
        _ = m.begin(old); _ = m.advance(old.id, to: .recording); _ = m.advance(old.id, to: .transcribing)
        check(m.cancel() == old.id)
        let new = SessionSnapshot(mode: mode(), trigger: .hotkey, destination: nil)
        check(m.begin(new))
        check(m.advance(new.id, to: .recording))
        // The old recogniser finishes late: it must not move the new session.
        check(!m.advance(old.id, to: .delivering))
        check(!m.advance(old.id, to: .finished(.insertedVerified(app: "TextEdit"))))
        #expect(m.phase == .recording)
        #expect(m.current?.id == new.id)
    }

    @Test func terminalStatesAreFinal() {
        var m = SessionMachine()
        let s = SessionSnapshot(mode: mode(), trigger: .button, destination: nil)
        _ = m.begin(s); _ = m.advance(s.id, to: .recording)
        check(m.advance(s.id, to: .noSpeech))
        check(!m.advance(s.id, to: .transcribing))
        check(m.cancel() == nil)
    }

    @Test func illegalJumpIsRejected() {
        var m = SessionMachine()
        let s = SessionSnapshot(mode: mode(), trigger: .button, destination: nil)
        _ = m.begin(s)
        check(!m.advance(s.id, to: .delivering))
    }

    @Test func snapshotIsolatesModeEdits() {
        var library = ModeLibrary(modes: ModePresets.starter(names: [:], spoken: ["ru"]))
        let snapshot = SessionSnapshot(mode: library.active!, trigger: .hotkey, destination: nil)
        var edited = library.active!
        edited.cleanup = .rewrite
        library.update(edited)
        #expect(snapshot.mode.cleanup == .light)
    }

    @Test func timingMeasuresFromEndOfSpeech() {
        var t = SessionTiming()
        let base = Date(timeIntervalSince1970: 1000)
        t.recordingStarted = base
        t.recordingEnded = base.addingTimeInterval(4)
        t.recognitionStarted = base.addingTimeInterval(4.05)
        t.recognitionEnded = base.addingTimeInterval(4.8)
        t.delivered = base.addingTimeInterval(5.1)
        #expect(abs((t.speechToText ?? 0) - 0.8) < 0.001)
        #expect(abs((t.speechToDelivery ?? 0) - 1.1) < 0.001)
        #expect(abs((t.recognition ?? 0) - 0.75) < 0.001)
    }
}
