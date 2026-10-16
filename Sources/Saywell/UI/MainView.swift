import SaywellCore
import SwiftUI

/// The small everyday window: active mode, how to start, what is happening, the last result.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, DS.Space.l)
                .padding(.top, DS.Space.m)
                .padding(.bottom, DS.Space.s)
            RecordPanel()
                .padding(.horizontal, DS.Space.l)
                .padding(.vertical, DS.Space.m)
            if let notice = model.notice {
                NoticeBar(notice: notice)
                    .padding(.horizontal, DS.Space.l)
                    .padding(.bottom, DS.Space.s)
            }
            if model.result != nil {
                Divider()
                ResultView()
                    .padding(DS.Space.l)
            }
            Divider()
            footer
                .padding(.horizontal, DS.Space.l)
                .padding(.vertical, DS.Space.s)
        }
        .frame(width: DS.Size.mainWidth)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            WindowRouter.openWindow = openWindow
            if !model.settings.onboardingCompleted { WindowRouter.onboardingRequested = true; openWindow(id: "onboarding") }
        }
    }

    private var header: some View {
        GlassGroup {
            HStack(spacing: DS.Space.s) {
                ModeMenu()
                Spacer(minLength: DS.Space.s)
                Button { SettingsRouter.open() } label: {
                    Image(systemName: "gearshape").font(.system(size: 13, weight: .medium)).frame(width: DS.Size.minTarget + 2, height: DS.Size.minTarget + 2)
                        .glass(Circle(), interactive: true)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.Palette.secondaryText)
                .help(tr("main.settings"))
                .accessibilityLabel(tr("main.settings"))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: DS.Space.m) {
            Button { openWindow(id: "history") } label: { Label(tr("window.history"), systemImage: "clock") }
            Button { openWindow(id: "practice") } label: {
                Label(model.dueCards.isEmpty ? tr("window.practice") : tr("main.practiceDue", model.dueCards.count), systemImage: "rectangle.on.rectangle.angled")
            }
            Spacer()
            RecognizerBadge()
        }
        .buttonStyle(.plain)
        .font(DS.Font.caption)
        .foregroundStyle(DS.Palette.secondaryText)
    }
}

/// Mode switcher: a compact menu with a chevron, symbol and name (never colour alone).
struct ModeMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ForEach(model.modes.modes) { mode in
                Button {
                    model.modes.setActive(mode.id)
                } label: {
                    Label(mode.name + (mode.id == model.activeMode.id ? "  ✓" : ""), systemImage: mode.symbol)
                }
            }
            Divider()
            Button(tr("mode.manage")) { SettingsRouter.open(.modes) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.activeMode.symbol)
                Text(model.activeMode.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(DS.Palette.secondaryText)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 12).padding(.vertical, 7)
        .glass(Capsule(), interactive: true)
        .contentShape(Capsule())
        .disabled(model.isBusy)
        .help(model.isBusy ? tr("mode.nextSession") : tr("mode.switchHelp", shortcutText(model.settings.hotkeys, switching: true)))
        .accessibilityLabel(tr("mode.accessibility", model.activeMode.name))
    }
}

struct RecordPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: DS.Space.l) {
            RecordButton()
            VStack(alignment: .leading, spacing: 3) {
                Text(headline).font(DS.Font.headline).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(detail).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                ModeSummary(mode: model.activeMode).padding(.top, 2)
            }
            Spacer(minLength: 0)
            if model.isBusy && !model.isRecording {
                Button(tr("main.cancel")) { model.cancel() }.buttonStyle(PillButtonStyle()).keyboardShortcut(.cancelAction)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func isFinished(_ phase: SessionPhase) -> Bool {
        if case .finished = phase { return true }
        return false
    }

    private var headline: String {
        switch model.phase {
        case .recording: tr("main.listening")
        case .starting, .transcribing, .editing, .delivering: model.statusLine
        default:
            switch model.recognizer {
            case .ready: tr("main.pressToSpeak")
            case .loading: tr("status.loading")
            case .notInstalled: tr("main.setupNeeded")
            case .installing: tr("status.installing")
            case .failed: tr("main.recognizerProblem")
            }
        }
    }

    private var detail: String {
        if model.isRecording, let start = model.recordingStarted {
            return tr("main.recordingDetail", shortcutText(model.settings.hotkeys, switching: false), Int(Date().timeIntervalSince(start)))
        }
        if model.isBusy { return tr("main.cancelHint") }
        if let phase = model.phase, phase.isTerminal, !isFinished(phase) { return model.statusLine }
        if model.providerUnavailable(for: model.activeMode) { return tr("main.editingUnavailable") }
        return tr("main.shortcutHint", shortcutText(model.settings.hotkeys, switching: false))
    }
}

/// The record control repeats the floating capsule: the same black instrument and bars,
/// driven by the same state, inside a Liquid Glass bezel on macOS 26+.
struct RecordButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovering = false

    var body: some View {
        Button {
            if model.isRecording { model.stopRecording() } else { model.startRecording(trigger: .button) }
        } label: {
            ZStack {
                CapsuleBody(tint: tint, glow: hovering || model.isBusy ? 0.9 : 0.5, opaque: false, highContrast: contrast == .increased)
                if model.isBusy {
                    CapsuleBars(model: model.capsule, tint: tint, reduceMotion: reduceMotion || model.capsule.reduceMotionSetting)
                } else {
                    IdleBars(tint: tint)
                }
            }
            .frame(width: 84, height: 44)
            .padding(5)
            .glass(Capsule(), interactive: true)
            .contentShape(Capsule())
            .scaleEffect(hovering && !reduceMotion ? 1.03 : 1)
            .animation(DS.Motion.quick, value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(model.isBusy && !model.isRecording)
        .accessibilityLabel(model.isRecording ? tr("main.stopRecording") : tr("main.startRecording"))
    }

    private var tint: Color {
        if model.isRecording { return model.capsule.recordingColor }
        if model.isBusy { return model.capsule.processingColor }
        return model.capsule.recordingColor
    }
}

/// Resting bars: a quiet voice shape, not a meter.
private struct IdleBars: View {
    var tint: Color
    var body: some View {
        HStack(spacing: CapsuleMetrics.barSpacing) {
            ForEach([5.0, 9, 13, 17, 13, 9, 5], id: \.self) { h in
                Capsule().fill(tint.opacity(0.9)).frame(width: CapsuleMetrics.barWidth, height: h)
                    .shadow(color: tint.opacity(0.5), radius: 2)
            }
        }
    }
}

/// One line that says what the active mode will do, so nothing is a surprise.
struct ModeSummary: View {
    var mode: Mode

    var body: some View {
        WrapLayout(spacing: 8) {
            tag(languagesText, "globe")
            tag(tr("cleanup.\(mode.cleanup.rawValue)"), "wand.and.rays")
            if mode.learning != .off { tag(tr("learning.\(mode.learning.rawValue)"), "graduationcap") }
            tag(tr("output.\(mode.output.rawValue)"), mode.output == .insert ? "text.insert" : mode.output == .copy ? "doc.on.clipboard" : "tray")
        }
        .font(.system(size: 10))
        .foregroundStyle(DS.Palette.secondaryText)
        .accessibilityElement(children: .combine)
    }

    private var languagesText: String {
        if mode.spokenLanguages.isEmpty { return tr("lang.auto") }
        return mode.spokenLanguages.map { $0 == "zh-Hans" ? "ZH" : $0.uppercased() }.joined(separator: "+")
    }

    private func tag(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol).labelStyle(.titleAndIcon).fixedSize()
    }
}

struct RecognizerBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            SettingsRouter.open(.recognition)
        } label: {
            HStack(spacing: 5) {
                StatusDot(color: color, pulsing: model.recognizer == .loading)
                Text(text)
            }
        }
        .buttonStyle(.plain)
        .help(tr("recognizer.openSettings"))
    }

    private var color: Color {
        switch model.recognizer {
        case .ready: DS.Palette.success
        case .loading, .installing: DS.Palette.warning
        case .notInstalled, .failed: DS.Palette.danger
        }
    }

    private var text: String {
        switch model.recognizer {
        case .ready: switch model.engine(for: model.activeMode) {
            case .appleDictation: tr("recognizer.appleShort")
            case .parakeet: tr("recognizer.parakeetShort")
            default: tr("recognizer.readyLocal")
            }
        case .loading: tr("status.loading")
        case .installing: tr("status.installing")
        case .notInstalled: tr("recognizer.notInstalled")
        case .failed: tr("recognizer.failedShort")
        }
    }
}

struct NoticeBar: View {
    var notice: Notice
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s) {
            Image(systemName: notice.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(notice.isError ? DS.Palette.warning : DS.Palette.signal)
            Text(notice.text).font(DS.Font.caption).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 0)
            if let title = actionTitle {
                Button(title) { perform() }.buttonStyle(PillButtonStyle())
            }
            Button { model.notice = nil } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain).foregroundStyle(DS.Palette.secondaryText).accessibilityLabel(tr("common.dismiss"))
        }
        .padding(DS.Space.s)
        .background(DS.Palette.quietFill, in: RoundedRectangle(cornerRadius: DS.Radius.control))
    }

    private var actionTitle: String? {
        switch notice.action {
        case .openPermissions: tr("notice.action.permissions")
        case .openRecognizer: tr("notice.action.recognizer")
        case .openProvider: tr("notice.action.provider")
        case .retryEdit: tr("notice.action.retry")
        case .none: nil
        }
    }

    private func perform() {
        switch notice.action {
        case .openPermissions: SettingsRouter.open(.general)
        case .openRecognizer: SettingsRouter.open(.recognition)
        case .openProvider: SettingsRouter.open(.text)
        case .retryEdit: model.retryEdit()
        case .none: break
        }
    }
}

func shortcutText(_ hotkeys: HotkeySettings, switching: Bool) -> String {
    if switching { return ShortcutFormatter.combo(code: hotkeys.switchKeyCode, modifiers: hotkeys.switchModifiers) }
    if hotkeys.bareModifierEnabled { return tr("key.\(hotkeys.bareModifier.rawValue)") }
    return ShortcutFormatter.combo(code: hotkeys.comboKeyCode, modifiers: hotkeys.comboModifiers)
}
