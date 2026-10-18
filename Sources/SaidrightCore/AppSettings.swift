import Foundation

public enum CapsulePlacement: String, Codable, CaseIterable, Sendable { case bottom, top }

/// Window appearance. The capsule has its own style, coordinated with this.
public enum ThemePreference: String, Codable, CaseIterable, Sendable { case system, light, dark }

/// Window colours: Saidright's own indigo (light and dark shades that follow the theme) or
/// plain macOS greys.
public enum WindowTint: String, Codable, CaseIterable, Sendable { case saidright, neutral }

/// Capsule material: native Liquid Glass (macOS 26+) or a restrained solid ink body.
public enum CapsuleStyle: String, Codable, CaseIterable, Sendable { case glass, ink }

public enum CapsuleSize: String, Codable, CaseIterable, Sendable {
    case compact, regular, large
    public var scale: Double {
        switch self {
        case .compact: 0.88
        case .regular: 1
        case .large: 1.18
        }
    }
}

/// Coordinated state colours. `custom` uses the two colours stored in CapsuleSettings.
public enum CapsulePalette: String, Codable, CaseIterable, Sendable {
    case signal, ember, aurora, graphite, custom

    /// Recording, processing and delivered colours (sRGB hex).
    public var colors: (recording: UInt32, processing: UInt32, done: UInt32)? {
        switch self {
        case .signal: (0x4F9DFF, 0xFF5FA8, 0x3FD08A)
        case .ember: (0xFF7A45, 0xFFC247, 0x5FD39A)
        case .aurora: (0x2FD3C1, 0xA58BFF, 0x7FE07A)
        case .graphite: (0xE9EEF7, 0x9AA6B8, 0xE9EEF7)
        case .custom: nil
        }
    }
}

/// Motion beyond the system Reduce Motion setting, which always wins.
public enum MotionPreference: String, Codable, CaseIterable, Sendable { case standard, gentle, minimal }

/// Dock icon variant while Saidright runs. Finder and Launchpad always show the bundle icon.
public enum AppIconVariant: String, Codable, CaseIterable, Sendable { case standard, light, mono }

/// How learning feedback reaches the person after a dictation.
public enum HintPresentation: String, Codable, CaseIterable, Sendable {
    /// The capsule opens a small card with the correction.
    case card
    /// The capsule shows a subtle marker; the card opens on click.
    case indicator
    /// Nothing near the cursor; feedback waits in the main window.
    case window
}

public enum HintLinger: String, Codable, CaseIterable, Sendable {
    case short, long, untilDismissed
    /// nil = stays until dismissed or the next dictation starts.
    public var seconds: Double? {
        switch self {
        case .short: 7
        case .long: 15
        case .untilDismissed: nil
        }
    }
}

/// How much an explanation says by default. Details stay one click away either way.
public enum ExplanationDepth: String, Codable, CaseIterable, Sendable { case brief, thorough }

/// Self-chosen, used only to pitch explanations; never assessed or scored.
public enum LearnerLevel: String, Codable, CaseIterable, Sendable { case beginner, intermediate, advanced }

public struct LearningPresentation: Codable, Equatable, Sendable {
    public var presentation: HintPresentation = .card
    public var linger: HintLinger = .short
    public var depth: ExplanationDepth = .brief
    public var level: LearnerLevel = .intermediate
    /// Also show "possibly misheard" and style suggestions in the capsule (otherwise app only).
    public var showUncertainInCapsule = false

    public init() {}
}

public struct HotkeySettings: Codable, Equatable, Sendable {
    /// Off = combination shortcut only.
    public var bareModifierEnabled = true
    public var bareModifier: BareModifier = .rightCommand
    public var behavior: PressBehavior = .toggle
    /// Carbon key code + modifier mask for the combination shortcut (default ⌃⌥Space).
    public var comboKeyCode: UInt32 = 49
    public var comboModifiers: UInt32 = 0x1000 | 0x0800
    public var comboEnabled = true
    /// Cycles modes (default ⌃⌥M).
    public var switchKeyCode: UInt32 = 46
    public var switchModifiers: UInt32 = 0x1000 | 0x0800
    public var switchEnabled = true
    /// Opens the last language tip again, or closes an open one (default ⌃⌥L).
    public var tipKeyCode: UInt32 = 37
    public var tipModifiers: UInt32 = 0x1000 | 0x0800
    public var tipEnabled = true

    public init() {}
}

public struct CapsuleSettings: Codable, Equatable, Sendable {
    public var enabled = true
    public var recordingColor: UInt32 = 0x4F9DFF
    public var processingColor: UInt32 = 0xFF4FA3
    /// 0…1. Glow is internal light within the capsule, not a halo.
    public var glow: Double = 0.6
    public var placement: CapsulePlacement = .bottom
    /// Follows the system Reduce Motion setting in addition to this switch.
    public var reduceMotion = false
    public var showModeBadge = true
    public var style: CapsuleStyle = .glass
    public var size: CapsuleSize = .regular
    public var palette: CapsulePalette = .signal
    public var motion: MotionPreference = .standard

    /// Recording / processing / delivered colours after applying the palette.
    public var resolvedColors: (recording: UInt32, processing: UInt32, done: UInt32) {
        palette.colors ?? (recordingColor, processingColor, recordingColor)
    }

    public init() {}
}

public struct SpeechSettings: Codable, Equatable, Sendable {
    /// Voice identifier per language id; nil = system default for that language.
    public var voices: [String: String] = [:]
    /// 0.3…0.6 for AVSpeechUtterance.
    public var rate: Double = 0.45

    public init() {}
}

public struct AppSettings: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var schemaVersion = currentVersion
    public var uiLanguage: UILanguage = .system
    /// Default explanation language for feedback when a mode does not set one. nil = UI language.
    public var explanationLanguage: String? = nil
    public var hotkeys = HotkeySettings()
    public var capsule = CapsuleSettings()
    public var theme: ThemePreference = .system
    public var windowTint: WindowTint = .saidright
    public var appIcon: AppIconVariant = .standard
    public var learningUI = LearningPresentation()
    /// Which Whisper model the local recognizer loads (ModelCatalog id).
    public var whisperModel: String = ModelCatalog.whisperTurbo.id
    public var provider = ProviderSettings()
    public var retention = RetentionPolicy()
    public var speech = SpeechSettings()
    /// CoreAudio device UID; nil = system default input.
    public var inputDeviceUID: String? = nil
    /// Require transcript confirmation before feedback counts towards personal topics.
    public var confirmBeforeLearning = true
    public var learningGoal: String = ""
    public var onboardingCompleted = false
    /// Step to resume the introduction at when it was left before finishing.
    public var onboardingStep = 0
    /// Restore the previous clipboard contents after inserting.
    public var restoreClipboard = true
    public var playSounds = false
    /// Accept saidright:// automation links (Shortcuts, scripts). Off by default: any app can open a link.
    public var allowAutomationLinks = false

    public init() {}

    /// Decodes leniently: unknown or missing fields fall back to defaults instead of
    /// discarding the person's settings after an update.
    public static func decode(_ data: Data) -> AppSettings {
        guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return AppSettings() }
        let defaults = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings()))) as? [String: Any] ?? [:]
        object = merge(defaults, object)
        guard let merged = try? JSONSerialization.data(withJSONObject: object), var value = try? JSONDecoder().decode(AppSettings.self, from: merged) else { return AppSettings() }
        // Settings from before palettes and motion presets: keep chosen colours and the motion switch.
        if let original = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let capsule = original["capsule"] as? [String: Any] {
            let defaults = CapsuleSettings()
            if capsule["palette"] == nil, value.capsule.recordingColor != defaults.recordingColor || value.capsule.processingColor != defaults.processingColor {
                value.capsule.palette = .custom
            }
            if capsule["motion"] == nil, value.capsule.reduceMotion { value.capsule.motion = .minimal }
        }
        return value
    }

    private static func merge(_ base: [String: Any], _ over: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in over {
            if let a = base[key] as? [String: Any], let b = value as? [String: Any] { result[key] = merge(a, b) } else { result[key] = value }
        }
        return result
    }
}
