import Testing
@testable import SaywellCore

private let rCmd: UInt64 = 0x10 | 0x100000 // device bit + generic Command flag
private let lCmd: UInt64 = 0x08 | 0x100000
private let rOpt: UInt64 = 0x40 | 0x80000

private func flags(_ code: UInt16, _ f: UInt64, _ t: Double) -> ModifierEvent { .flagsChanged(keyCode: code, flags: f, time: t) }

@Suite struct ToggleBehaviour {
    @Test func cleanTapFires() {
        var d = ModifierDetector(key: .rightCommand, behavior: .toggle)
        check(d.handle(flags(54, rCmd, 0)) == nil)
        check(d.handle(flags(54, 0, 0.12)) == .tap)
    }

    @Test func commandCDoesNotFire() {
        var d = ModifierDetector(key: .rightCommand, behavior: .toggle)
        _ = d.handle(flags(54, rCmd, 0))
        _ = d.handle(.keyDown(time: 0.05)) // C
        check(d.handle(flags(54, 0, 0.1)) == nil)
    }

    @Test func commandClickDoesNotFire() {
        var d = ModifierDetector(key: .rightCommand, behavior: .toggle)
        _ = d.handle(flags(54, rCmd, 0))
        _ = d.handle(.mouseDown(time: 0.05))
        check(d.handle(flags(54, 0, 0.2)) == nil)
    }

    @Test func commandScrollDoesNotFire() {
        var d = ModifierDetector(key: .rightCommand, behavior: .toggle)
        _ = d.handle(flags(54, rCmd, 0))
        _ = d.handle(.mouseDown(time: 0.1)) // scroll wheel is reported as pointer activity
        check(d.handle(flags(54, 0, 0.3)) == nil)
    }

    @Test func leftCommandIsIgnored() {
        var d = ModifierDetector(key: .rightCommand, behavior: .toggle)
        check(d.handle(flags(55, lCmd, 0)) == nil)
        check(d.handle(flags(55, 0, 0.1)) == nil)
    }

    @Test func rightCommandWhileLeftHeldIsAShortcut() {
        var d = ModifierDetector(key: .rightCommand, behavior: .toggle)
        _ = d.handle(flags(55, lCmd, 0))
        _ = d.handle(flags(54, lCmd | rCmd, 0.05))
        check(d.handle(flags(54, lCmd, 0.1)) == nil)
    }

    @Test func addingOptionDuringPressIsAShortcut() {
        var d = ModifierDetector(key: .rightCommand, behavior: .toggle)
        _ = d.handle(flags(54, rCmd, 0))
        _ = d.handle(flags(61, rCmd | rOpt, 0.05))
        _ = d.handle(flags(61, rCmd, 0.08))
        check(d.handle(flags(54, 0, 0.12)) == nil)
    }

    @Test func longPressDoesNotFire() {
        var d = ModifierDetector(key: .rightCommand, behavior: .toggle)
        _ = d.handle(flags(54, rCmd, 0))
        check(d.handle(flags(54, 0, 1.5)) == nil)
    }

    @Test func nextTapAfterShortcutWorks() {
        var d = ModifierDetector(key: .rightCommand, behavior: .toggle)
        _ = d.handle(flags(54, rCmd, 0)); _ = d.handle(.keyDown(time: 0.1)); _ = d.handle(flags(54, 0, 0.2))
        _ = d.handle(flags(54, rCmd, 1)); check(d.handle(flags(54, 0, 1.1)) == .tap)
    }

    @Test func missedReleaseResynchronises() {
        var d = ModifierDetector(key: .rightCommand, behavior: .toggle)
        _ = d.handle(flags(54, rCmd, 0))
        // Release was swallowed (permission dialog); next event shows no Command bit.
        _ = d.handle(flags(56, 0x02, 5))
        #expect(!d.isPressed)
    }

    @Test func rightOptionWorks() {
        var d = ModifierDetector(key: .rightOption, behavior: .toggle)
        _ = d.handle(flags(61, rOpt, 0))
        check(d.handle(flags(61, 0, 0.1)) == .tap)
    }
}

@Suite struct HoldBehaviour {
    @Test func holdBeginsAndEnds() {
        var d = ModifierDetector(key: .rightCommand, behavior: .hold)
        check(d.handle(flags(54, rCmd, 0)) == .holdBegan)
        check(d.handle(flags(54, 0, 2)) == .holdEnded)
    }

    @Test func shortcutDuringHoldCancelsOnce() {
        var d = ModifierDetector(key: .rightCommand, behavior: .hold)
        check(d.handle(flags(54, rCmd, 0)) == .holdBegan)
        check(d.handle(.keyDown(time: 0.1)) == .holdCancelled)
        check(d.handle(.keyDown(time: 0.15)) == nil)
        check(d.handle(flags(54, 0, 0.3)) == nil)
    }

    @Test func accidentalBriefPressIsDiscarded() {
        var d = ModifierDetector(key: .rightCommand, behavior: .hold)
        _ = d.handle(flags(54, rCmd, 0))
        check(d.handle(flags(54, 0, 0.1)) == .holdCancelled)
    }

    @Test func resetDuringHoldCancels() {
        var d = ModifierDetector(key: .rightCommand, behavior: .hold)
        _ = d.handle(flags(54, rCmd, 0))
        check(d.reset() == .holdCancelled)
        check(d.handle(flags(54, 0, 1)) == nil)
    }

    @Test func pressWithOtherModifierAlreadyHeldNeverBegins() {
        var d = ModifierDetector(key: .rightCommand, behavior: .hold)
        _ = d.handle(flags(56, 0x02, 0))
        check(d.handle(flags(54, 0x02 | rCmd, 0.1)) == nil)
        check(d.handle(flags(54, 0x02, 1)) == nil)
    }
}
