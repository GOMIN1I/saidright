import AppKit
import Carbon
import SaidrightCore

/// Global shortcuts: a bare modifier (default right Command) through a listen-only event tap,
/// plus key combinations through Carbon, which need no permission and serve as the fallback.
@MainActor final class HotkeyService {
    enum Event {
        /// Toggle: start or stop. Hold: begin (provisional) / end / cancel.
        case toggle
        case holdBegan
        case holdEnded
        case holdCancelled
        case switchMode
        /// Reopen or close the last language tip.
        case lastTip
        /// Esc while a session is active.
        case cancel
    }

    struct Status: Equatable {
        var tapInstalled = false
        /// At least one keyboard event reached the tap since it was installed: proof it works.
        var tapReceivedEvents = false
        var comboRegistered = false
        var comboConflict = false
        var switchRegistered = false
        var switchConflict = false
        var tipRegistered = false
        var tipConflict = false
        var secureInput = false
    }

    var onEvent: ((Event) -> Void)?
    /// Set by the owner while recording or processing, so Esc can cancel.
    var sessionActive = false
    /// Raw target-key observations for the "press the key now" test.
    var onTargetKeySeen: (() -> Void)?
    private(set) var status = Status() { didSet { if status != oldValue { onStatusChange?(status) } } }
    var onStatusChange: ((Status) -> Void)?

    private var settings = HotkeySettings()
    private var detector = ModifierDetector(key: .rightCommand, behavior: .toggle)
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var carbonHandler: EventHandlerRef?
    private var observers: [NSObjectProtocol] = []

    init() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resetPress(reinstall: true) }
            })
        }
        let dnc = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            observers.append(dnc.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resetPress(reinstall: true) }
            })
        }
    }

    func apply(_ settings: HotkeySettings) {
        self.settings = settings
        detector = ModifierDetector(key: settings.bareModifier, behavior: settings.behavior)
        registerCombos()
        installTapIfPossible()
    }

    /// Called after permission changes and wake: installs the tap as soon as it can work.
    func installTapIfPossible() {
        guard settings.bareModifierEnabled else { removeTap(); return }
        if let tap {
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard CGPreflightListenEventAccess() else { status.tapInstalled = false; return }
        let mask: CGEventMask = [CGEventType.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel].reduce(0) { $0 | (1 << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
            if let context {
                let service = Unmanaged<HotkeyService>.fromOpaque(context).takeUnretainedValue()
                let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags.rawValue
                let time = ProcessInfo.processInfo.systemUptime
                // The tap runs on the main run loop, so this is already the main thread.
                MainActor.assumeIsolated { service.handleTap(type: type, code: code, flags: flags, time: time) }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: context) else {
            status.tapInstalled = false
            Log.error("event tap creation failed")
            return
        }
        tap = port
        tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        status.tapInstalled = true
        status.tapReceivedEvents = false
        Log.info("event tap installed for \(settings.bareModifier.rawValue)")
    }

    private func removeTap() {
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        tapSource = nil
        status.tapInstalled = false
        status.tapReceivedEvents = false
    }

    private func handleTap(type: CGEventType, code: UInt16, flags: UInt64, time: TimeInterval) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            resetPress(reinstall: false)
            return
        }
        if type == .flagsChanged || type == .keyDown { status.tapReceivedEvents = true }
        let event: ModifierEvent
        switch type {
        case .flagsChanged:
            if code == settings.bareModifier.keyCode { onTargetKeySeen?() }
            event = .flagsChanged(keyCode: code, flags: flags, time: time)
        case .keyDown:
            if code == 53, sessionActive, flags & deviceModifierBits == 0 { onEvent?(.cancel) }
            event = .keyDown(time: time)
        default: event = .mouseDown(time: time)
        }
        guard let action = detector.handle(event) else { return }
        switch action {
        case .tap: onEvent?(.toggle)
        case .holdBegan: onEvent?(.holdBegan)
        case .holdEnded: onEvent?(.holdEnded)
        case .holdCancelled: onEvent?(.holdCancelled)
        }
    }

    private func resetPress(reinstall: Bool) {
        if detector.reset() == .holdCancelled { onEvent?(.holdCancelled) }
        status.secureInput = IsSecureEventInputEnabled()
        if reinstall { installTapIfPossible() }
    }

    func refreshSecureInput() { status.secureInput = IsSecureEventInputEnabled() }

    // MARK: Carbon combinations

    private static let signature: OSType = 0x5357_4C4C // 'SWLL'
    private static let dictationID: UInt32 = 1
    private static let switchID: UInt32 = 2
    private static let tipID: UInt32 = 3

    private func registerCombos() {
        for ref in hotKeyRefs.values { UnregisterEventHotKey(ref) }
        hotKeyRefs = [:]
        installCarbonHandler()
        status.comboRegistered = false
        status.comboConflict = false
        status.switchRegistered = false
        status.switchConflict = false
        if settings.comboEnabled {
            let result = register(id: Self.dictationID, code: settings.comboKeyCode, modifiers: settings.comboModifiers)
            status.comboRegistered = result == noErr
            status.comboConflict = result == OSStatus(eventHotKeyExistsErr)
        }
        if settings.switchEnabled {
            let result = register(id: Self.switchID, code: settings.switchKeyCode, modifiers: settings.switchModifiers)
            status.switchRegistered = result == noErr
            status.switchConflict = result == OSStatus(eventHotKeyExistsErr)
        }
        status.tipRegistered = false
        status.tipConflict = false
        if settings.tipEnabled {
            let result = register(id: Self.tipID, code: settings.tipKeyCode, modifiers: settings.tipModifiers)
            status.tipRegistered = result == noErr
            status.tipConflict = result == OSStatus(eventHotKeyExistsErr)
        }
    }

    private func register(id: UInt32, code: UInt32, modifiers: UInt32) -> OSStatus {
        var ref: EventHotKeyRef?
        let result = RegisterEventHotKey(code, modifiers, EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(), 0, &ref)
        if result == noErr, let ref { hotKeyRefs[id] = ref }
        return result
    }

    private func installCarbonHandler() {
        guard carbonHandler == nil else { return }
        let types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return noErr }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let service = Unmanaged<HotkeyService>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { service.handleCombo(id: id.id, pressed: pressed) }
            return noErr
        }, types.count, types, Unmanaged.passUnretained(self).toOpaque(), &carbonHandler)
    }

    private func handleCombo(id: UInt32, pressed: Bool) {
        switch id {
        case Self.switchID where pressed:
            onEvent?(.switchMode)
        case Self.tipID where pressed:
            onEvent?(.lastTip)
        case Self.dictationID:
            if settings.behavior == .hold { onEvent?(pressed ? .holdBegan : .holdEnded) } else if pressed { onEvent?(.toggle) }
        default:
            break
        }
    }

    /// Shortcuts that macOS or nearly every app already uses.
    static func reservedConflict(code: UInt32, modifiers: UInt32) -> Bool {
        let cmd = UInt32(cmdKey), ctrl = UInt32(controlKey)
        let reserved: [(UInt32, UInt32)] = [
            (UInt32(kVK_ANSI_Q), cmd), (UInt32(kVK_ANSI_W), cmd), (UInt32(kVK_ANSI_C), cmd), (UInt32(kVK_ANSI_V), cmd), (UInt32(kVK_ANSI_X), cmd),
            (UInt32(kVK_ANSI_Z), cmd), (UInt32(kVK_ANSI_A), cmd), (UInt32(kVK_ANSI_S), cmd), (UInt32(kVK_Tab), cmd), (UInt32(kVK_Space), cmd),
            (UInt32(kVK_Space), ctrl), (UInt32(kVK_ANSI_H), cmd), (UInt32(kVK_ANSI_M), cmd),
        ]
        return reserved.contains { $0.0 == code && $0.1 == modifiers }
    }
}
