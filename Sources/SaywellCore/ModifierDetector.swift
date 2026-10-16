import Foundation

/// A single modifier key that can be used on its own as the dictation key.
public enum BareModifier: String, Codable, CaseIterable, Sendable {
    case rightCommand, rightOption, rightControl, rightShift

    /// Virtual key code reported in flagsChanged events.
    public var keyCode: UInt16 {
        switch self {
        case .rightCommand: 54
        case .rightOption: 61
        case .rightControl: 62
        case .rightShift: 60
        }
    }

    /// Device-dependent bit (IOKit NX_DEVICE*KEYMASK). Distinguishes left from right.
    public var deviceMask: UInt64 {
        switch self {
        case .rightCommand: 0x0000_0010
        case .rightOption: 0x0000_0040
        case .rightControl: 0x0000_2000
        case .rightShift: 0x0000_0004
        }
    }
}

/// All device-dependent modifier bits (left and right Control, Shift, Command, Option).
public let deviceModifierBits: UInt64 = 0x0000_0001 | 0x0000_0002 | 0x0000_0004 | 0x0000_0008 | 0x0000_0010 | 0x0000_0020 | 0x0000_0040 | 0x0000_2000
/// Fn/Globe (NX_SECONDARYFNMASK). Holding it with the dictation key counts as a chord.
public let secondaryFnBit: UInt64 = 0x0080_0000

public enum PressBehavior: String, Codable, CaseIterable, Sendable {
    /// Tap to start, tap again to stop.
    case toggle
    /// Record while held.
    case hold
}

public enum ModifierEvent: Sendable {
    /// A flagsChanged event: which key changed and the full flag word after the change.
    case flagsChanged(keyCode: UInt16, flags: UInt64, time: TimeInterval)
    /// Any ordinary key press (including repeats).
    case keyDown(time: TimeInterval)
    /// Any mouse button press or scroll (⌘-scroll zooms in many apps).
    case mouseDown(time: TimeInterval)
}

public enum ModifierAction: Equatable, Sendable {
    /// Toggle behaviour: a clean tap was recognised.
    case tap
    /// Hold behaviour: the key went down alone. Recording may start provisionally.
    case holdBegan
    /// Hold behaviour: the key was released after a clean hold.
    case holdEnded
    /// Hold behaviour: the press turned out to be part of a shortcut, or too short. Discard silently.
    case holdCancelled
}

/// Recognises a bare modifier used as a dictation key without stealing ordinary shortcuts.
///
/// Toggle: fires `.tap` on release, only if nothing else was pressed meanwhile and the press
/// was shorter than `maxTapDuration`. ⌘C, ⌘-click, ⌥⌘ and the like never fire.
/// Hold: fires `.holdBegan` immediately so the first syllable is not lost, then either
/// `.holdEnded` or `.holdCancelled` if the press turned into a chord or was a brief accident.
public struct ModifierDetector: Sendable {
    public var key: BareModifier
    public var behavior: PressBehavior
    public var maxTapDuration: TimeInterval = 0.6
    public var minHoldDuration: TimeInterval = 0.25

    private var pressedAt: TimeInterval?
    private var chorded = false

    public init(key: BareModifier, behavior: PressBehavior) {
        self.key = key
        self.behavior = behavior
    }

    public var isPressed: Bool { pressedAt != nil }

    /// Forget any in-flight press (sleep/wake, screen lock, configuration change).
    public mutating func reset() -> ModifierAction? {
        defer { pressedAt = nil; chorded = false }
        if pressedAt != nil, behavior == .hold { return .holdCancelled }
        return nil
    }

    public mutating func handle(_ event: ModifierEvent) -> ModifierAction? {
        switch event {
        case .keyDown, .mouseDown:
            guard pressedAt != nil else { return nil }
            if !chorded {
                chorded = true
                if behavior == .hold { return .holdCancelled }
            }
            return nil

        case let .flagsChanged(keyCode, flags, time):
            let targetDown = flags & key.deviceMask != 0
            let others = flags & (deviceModifierBits | secondaryFnBit) & ~key.deviceMask

            if keyCode != key.keyCode {
                // Another modifier changed while ours is held: this is a shortcut, not dictation.
                if pressedAt != nil, others != 0, !chorded {
                    chorded = true
                    if behavior == .hold { return .holdCancelled }
                }
                // Missed release (e.g. event lost during a permission dialog): resynchronise.
                if pressedAt != nil, !targetDown {
                    let wasHold = behavior == .hold && !chorded
                    pressedAt = nil
                    chorded = false
                    return wasHold ? .holdCancelled : nil
                }
                return nil
            }

            if targetDown {
                if pressedAt != nil { return nil } // duplicate down
                pressedAt = time
                // Pressed while another modifier is already held: treat as a shortcut.
                chorded = others != 0
                if behavior == .hold, !chorded { return .holdBegan }
                return nil
            }

            // Release of our key.
            guard let start = pressedAt else { return nil }
            let duration = time - start
            let clean = !chorded
            pressedAt = nil
            chorded = false
            switch behavior {
            case .toggle:
                return clean && duration <= maxTapDuration ? .tap : nil
            case .hold:
                guard clean else { return nil } // .holdCancelled was already emitted
                return duration >= minHoldDuration ? .holdEnded : .holdCancelled
            }
        }
    }
}
