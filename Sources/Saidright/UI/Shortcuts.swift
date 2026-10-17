import AppKit
import Carbon
import SaidrightCore
import SwiftUI

enum ShortcutFormatter {
    static func combo(code: UInt32, modifiers: UInt32) -> String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyName(code)
    }

    /// Key name from the current keyboard layout, so ⌃⌥M reads correctly on any layout.
    static func keyName(_ code: UInt32) -> String {
        switch Int(code) {
        case kVK_Space: return tr("key.space")
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "esc"
        case kVK_Delete: return "⌫"
        default: break
        }
        let fkeys: [Int: String] = [kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15"]
        if let f = fkeys[Int(code)] { return f }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "#\(code)" }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { ptr -> OSStatus in
            UCKeyTranslate(ptr.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self), UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "#\(code)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// Click, then press a combination. Requires at least one of ⌃ ⌥ ⌘ so ordinary typing is never captured.
struct ShortcutRecorder: View {
    enum Target: Equatable { case dictation, switchMode, lastTip }
    var target: Target
    var code: UInt32
    var modifiers: UInt32
    @Binding var active: Target?
    var onChange: (UInt32, UInt32) -> Void
    @State private var monitor: Any?
    @State private var warning: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Button {
                active == target ? stop() : start()
            } label: {
                Text(active == target ? tr("shortcut.pressNow") : ShortcutFormatter.combo(code: code, modifiers: modifiers))
                    .font(DS.Font.mono)
                    .frame(minWidth: 90)
            }
            .buttonStyle(PillButtonStyle(prominent: active == target))
            .accessibilityHint(tr("shortcut.recorderHint"))
            if let warning { Text(warning).font(.system(size: 10)).foregroundStyle(DS.Palette.warning) }
        }
        .onDisappear { stop() }
    }

    private func start() {
        stop()
        active = target
        warning = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            var mods: UInt32 = 0
            let f = event.modifierFlags
            if f.contains(.control) { mods |= UInt32(controlKey) }
            if f.contains(.option) { mods |= UInt32(optionKey) }
            if f.contains(.shift) { mods |= UInt32(shiftKey) }
            if f.contains(.command) { mods |= UInt32(cmdKey) }
            guard mods & UInt32(controlKey | optionKey | cmdKey) != 0 else { warning = tr("shortcut.needModifier"); return nil }
            if HotkeyService.reservedConflict(code: UInt32(event.keyCode), modifiers: mods) { warning = tr("shortcut.reserved"); return nil }
            onChange(UInt32(event.keyCode), mods)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if active == target { active = nil }
    }
}
