import AVFoundation
import SaywellCore
import SwiftUI
import UniformTypeIdentifiers

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, modes, shortcuts, recognition, text, learning, appearance, privacy, advanced
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .modes: "square.stack"
        case .shortcuts: "keyboard"
        case .recognition: "waveform"
        case .text: "wand.and.rays"
        case .learning: "graduationcap"
        case .appearance: "paintpalette"
        case .privacy: "hand.raised"
        case .advanced: "slider.horizontal.3"
        }
    }
}

/// Lets other views open Settings at a particular section (and optionally reveal one setting).
@MainActor enum SettingsRouter {
    static var section: SettingsSection = .general
    static var anchor: String?
    /// QA only: search text to show when the window opens.
    static var qaQuery: String?
    static var qaReveal = false

    static func open(_ section: SettingsSection? = nil, anchor: String? = nil) {
        if let section { self.section = section }
        self.anchor = anchor
        NotificationCenter.default.post(name: .settingsSection, object: nil)
        WindowRouter.show("settings")
    }
}

extension Notification.Name { static let settingsSection = Notification.Name("saywell.settingsSection") }

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var section: SettingsSection? = SettingsRouter.section
    @State private var query = ""
    @State private var resultSelection: SettingsEntry.ID?
    @State private var highlight: String?
    @State private var pendingAnchor: String?
    @State private var highlightTask: Task<Void, Never>?

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var results: [SettingsEntry] { searching ? SettingsIndex.search(query) : [] }
    private var current: SettingsSection { section ?? .general }

    var body: some View {
        NavigationSplitView {
            ZStack {
                if searching {
                    SettingsSearchResults(results: results, query: query, selection: $resultSelection)
                } else {
                    List(SettingsSection.allCases, selection: $section) { s in
                        Label(tr("settings.\(s.rawValue)"), systemImage: s.symbol).tag(s)
                    }
                }
            }
            .frame(minWidth: 210)
            .navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 300)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.xl) {
                        detail
                    }
                    .padding(.horizontal, DS.Space.xl)
                    .padding(.top, DS.Space.l)
                    .padding(.bottom, DS.Space.xl)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .environment(\.settingsHighlight, highlight)
                .onChange(of: pendingAnchor) { reveal(proxy) }
                .onAppear { reveal(proxy) }
            }
            .navigationTitle(tr("settings.\(current.rawValue)"))
        }
        .searchable(text: $query, placement: .sidebar, prompt: tr("search.prompt"))
        .onSubmit(of: .search) { if let first = results.first { go(to: first) } }
        .onChange(of: resultSelection) { _, id in
            if let id, let entry = results.first(where: { $0.id == id }) { go(to: entry) }
        }
        .onChange(of: query) { if !searching { resultSelection = nil } }
        .frame(minWidth: 800, minHeight: 540)
        .onReceive(NotificationCenter.default.publisher(for: .settingsSection)) { _ in
            section = SettingsRouter.section
            pendingAnchor = SettingsRouter.anchor
        }
        .onAppear {
            pendingAnchor = SettingsRouter.anchor
            if let q = SettingsRouter.qaQuery {
                query = q
                SettingsRouter.qaQuery = nil
                if SettingsRouter.qaReveal, let first = SettingsIndex.search(q).first { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { go(to: first) } }
            }
        }
    }

    private func go(to entry: SettingsEntry) {
        section = entry.section
        pendingAnchor = nil
        // Let the section render before scrolling to the row.
        DispatchQueue.main.async { pendingAnchor = entry.anchor }
    }

    private func reveal(_ proxy: ScrollViewProxy) {
        guard let anchor = pendingAnchor else { return }
        withAnimation(DS.Motion.standard) { proxy.scrollTo(anchor, anchor: .center) }
        highlight = anchor
        SettingsRouter.anchor = nil
        highlightTask?.cancel()
        highlightTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            highlight = nil
            pendingAnchor = nil
        }
    }

    @ViewBuilder private var detail: some View {
        switch current {
        case .general: GeneralSettings()
        case .modes: ModesSettings()
        case .shortcuts: ShortcutSettings()
        case .recognition: RecognitionSettings()
        case .text: TextSettings()
        case .learning: LearningSettings()
        case .appearance: AppearanceSettings()
        case .privacy: PrivacySettings()
        case .advanced: AdvancedSettings()
        }
    }
}

// MARK: - Building blocks

struct SettingsGroup<Content: View>: View {
    var title: String
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(title).sectionLabel().settingAnchor(title)
            VStack(alignment: .leading, spacing: DS.Space.m) { content }
                .padding(DS.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: DS.Radius.surface))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.surface).stroke(DS.Palette.hairline.opacity(0.5), lineWidth: 0.5))
            if let footer { Text(footer).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct SettingRow<Control: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DS.Font.body)
                if let detail { Text(detail).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: DS.Space.m)
            control
        }
        .settingAnchor(title)
    }
}

struct PermissionRow: View {
    var title: String
    var detail: String
    var granted: Bool
    var action: () -> Void

    var body: some View {
        SettingRow(title: title, detail: detail) {
            if granted {
                Label(tr("perm.granted"), systemImage: "checkmark.circle.fill").foregroundStyle(DS.Palette.success).font(DS.Font.caption)
            } else {
                Button(tr("perm.allow"), action: action).buttonStyle(PillButtonStyle(prominent: true))
            }
        }
    }
}

// MARK: - General

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        SettingsGroup(title: tr("settings.interfaceLanguage"), footer: tr("settings.interfaceLanguageFooter")) {
            SettingRow(title: tr("settings.language")) {
                Picker(tr("settings.language"), selection: $model.settings.uiLanguage) {
                    Text(tr("settings.systemLanguage")).tag(UILanguage.system)
                    Divider()
                    ForEach(UILanguage.translated) { lang in Text(lang.nativeName).tag(lang) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
        PermissionsGroup()
        SettingsGroup(title: tr("settings.microphone")) {
            SettingRow(title: tr("settings.inputDevice")) {
                Picker(tr("settings.inputDevice"), selection: $model.settings.inputDeviceUID) {
                    Text(tr("settings.systemDefault")).tag(String?.none)
                    ForEach(model.inputDevices) { d in Text(d.name).tag(Optional(d.uid)) }
                }
                .labelsHidden().frame(maxWidth: 240)
            }
            if let uid = model.settings.inputDeviceUID, !model.inputDevices.contains(where: { $0.uid == uid }) {
                Label(tr("settings.deviceMissing"), systemImage: "exclamationmark.triangle").font(DS.Font.caption).foregroundStyle(DS.Palette.warning)
            }
            MicLevelTest()
        }
        SettingsGroup(title: tr("settings.onboarding")) {
            SettingRow(title: tr("settings.replayOnboarding"), detail: tr("settings.replayOnboardingDetail")) {
                Button(tr("settings.open")) { WindowRouter.show("onboarding") }.buttonStyle(PillButtonStyle())
            }
        }
    }
}

struct PermissionsGroup: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.permissions
        SettingsGroup(title: tr("settings.permissions"), footer: p.signing.isAdHoc ? tr("perm.adhocWarning") : tr("perm.footer")) {
            PermissionRow(title: tr("perm.mic"), detail: tr("perm.micDetail"), granted: p.microphone == .granted) {
                if p.microphone == .notDetermined { Task { _ = await p.requestMicrophone() } } else { p.openSettings(.microphone) }
            }
            Divider()
            PermissionRow(title: tr("perm.listen"), detail: tr("perm.listenDetail"), granted: p.listenEvents) { p.requestListen() }
            Divider()
            PermissionRow(title: tr("perm.ax"), detail: tr("perm.axDetail"), granted: p.accessibility) { p.requestAccessibility() }
            if p.listenEvents && !model.hotkeyStatus.tapInstalled && model.settings.hotkeys.bareModifierEnabled {
                Label(tr("perm.tapFailed"), systemImage: "exclamationmark.triangle").font(DS.Font.caption).foregroundStyle(DS.Palette.warning)
            }
        }
        KeyTestGroup()
    }
}

/// Proves the hotkey works by observing a real key press, instead of trusting a switch.
struct KeyTestGroup: View {
    @Environment(AppModel.self) private var model
    @State private var testing = false

    var body: some View {
        let hk = model.settings.hotkeys
        SettingsGroup(title: tr("keytest.title"), footer: model.hotkeyStatus.secureInput ? tr("keytest.secureInput") : nil) {
            HStack(spacing: DS.Space.m) {
                Image(systemName: model.keyTestPassed ? "checkmark.circle.fill" : "keyboard")
                    .font(.system(size: 20))
                    .foregroundStyle(model.keyTestPassed ? DS.Palette.success : DS.Palette.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.keyTestPassed ? tr("keytest.passed") : testing ? tr("keytest.pressNow", tr("key.\(hk.bareModifier.rawValue)")) : tr("keytest.prompt"))
                        .font(DS.Font.body)
                    Text(statusLine).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText)
                }
                Spacer()
                Button(tr("keytest.start")) { testing = true; model.startKeyTest() }
                    .buttonStyle(PillButtonStyle())
                    .disabled(!hk.bareModifierEnabled)
            }
        }
    }

    private var statusLine: String {
        let s = model.hotkeyStatus
        var parts: [String] = []
        if model.settings.hotkeys.bareModifierEnabled {
            parts.append(s.tapInstalled ? (s.tapReceivedEvents ? tr("keytest.tapLive") : tr("keytest.tapWaiting")) : tr("keytest.tapMissing"))
        }
        if model.settings.hotkeys.comboEnabled {
            parts.append(s.comboRegistered ? tr("keytest.comboOK", ShortcutFormatter.combo(code: model.settings.hotkeys.comboKeyCode, modifiers: model.settings.hotkeys.comboModifiers)) : tr("keytest.comboFailed"))
        }
        return parts.joined(separator: " · ")
    }
}

struct MicLevelTest: View {
    @Environment(AppModel.self) private var model
    @State private var monitor = LevelMonitor()

    var body: some View {
        HStack(spacing: DS.Space.m) {
            Button(monitor.running ? tr("mic.stopTest") : tr("mic.test")) {
                monitor.running ? monitor.stop() : monitor.start(deviceUID: model.settings.inputDeviceUID)
            }
            .buttonStyle(PillButtonStyle())
            .disabled(model.isBusy || model.permissions.microphone != .granted)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Palette.quietFill)
                    Capsule().fill(monitor.level > 0.85 ? DS.Palette.warning : DS.Palette.signal).frame(width: geo.size.width * CGFloat(monitor.level))
                }
            }
            .frame(height: 6)
            .accessibilityLabel(tr("mic.level"))
            .accessibilityValue("\(Int(monitor.level * 100))%")
            Text(monitor.hint).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).frame(width: 150, alignment: .leading)
        }
        .onDisappear { monitor.stop() }
    }
}

/// Short level check without saving audio.
@MainActor @Observable final class LevelMonitor {
    private(set) var level: Float = 0
    private(set) var running = false
    private var peak: Float = 0
    private var recorder: AudioRecorder?

    var hint: String {
        guard running else { return "" }
        if peak < 0.15 { return tr("mic.hintSilent") }
        if peak > 0.95 { return tr("mic.hintLoud") }
        return tr("mic.hintGood")
    }

    func start(deviceUID: String?) {
        let r = AudioRecorder()
        r.onLevel = { [weak self] l in self?.level = l; self?.peak = max(self?.peak ?? 0, l) }
        do { _ = try r.start(deviceUID: deviceUID); recorder = r; running = true; peak = 0 } catch { running = false }
    }

    func stop() {
        recorder?.discard()
        recorder = nil
        running = false
        level = 0
    }
}

// MARK: - Shortcuts

struct ShortcutSettings: View {
    @Environment(AppModel.self) private var model
    @State private var recording: ShortcutRecorder.Target?

    var body: some View {
        @Bindable var model = model
        let hk = model.settings.hotkeys
        SettingsGroup(title: tr("shortcut.dictation")) {
            SettingRow(title: tr("shortcut.singleKey"), detail: tr("shortcut.singleKeyDetail")) {
                Toggle(tr("shortcut.singleKey"), isOn: $model.settings.hotkeys.bareModifierEnabled).labelsHidden().toggleStyle(.switch)
            }
            if hk.bareModifierEnabled {
                SettingRow(title: tr("shortcut.key")) {
                    Picker(tr("shortcut.key"), selection: $model.settings.hotkeys.bareModifier) {
                        ForEach(BareModifier.allCases, id: \.self) { Text(tr("key.\($0.rawValue)")).tag($0) }
                    }.labelsHidden().fixedSize()
                }
            }
            Divider()
            SettingRow(title: tr("shortcut.combo"), detail: tr("shortcut.comboDetail")) {
                HStack {
                    Toggle(tr("shortcut.combo"), isOn: $model.settings.hotkeys.comboEnabled).labelsHidden().toggleStyle(.switch)
                    ShortcutRecorder(target: .dictation, code: hk.comboKeyCode, modifiers: hk.comboModifiers, active: $recording) { code, mods in
                        model.settings.hotkeys.comboKeyCode = code
                        model.settings.hotkeys.comboModifiers = mods
                    }
                    .disabled(!hk.comboEnabled)
                }
            }
            if model.hotkeyStatus.comboConflict { Label(tr("shortcut.conflictOther"), systemImage: "exclamationmark.triangle").font(DS.Font.caption).foregroundStyle(DS.Palette.warning) }
            Divider()
            SettingRow(title: tr("shortcut.behavior")) {
                Picker(tr("shortcut.behavior"), selection: $model.settings.hotkeys.behavior) {
                    Text(tr("shortcut.toggle")).tag(PressBehavior.toggle)
                    Text(tr("shortcut.hold")).tag(PressBehavior.hold)
                }.labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            Text(hk.behavior == .toggle ? tr("shortcut.toggleDetail") : tr("shortcut.holdDetail")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText)
        }
        SettingsGroup(title: tr("shortcut.switchTitle"), footer: tr("shortcut.switchFooter")) {
            SettingRow(title: tr("shortcut.switch")) {
                HStack {
                    Toggle(tr("shortcut.switch"), isOn: $model.settings.hotkeys.switchEnabled).labelsHidden().toggleStyle(.switch)
                    ShortcutRecorder(target: .switchMode, code: hk.switchKeyCode, modifiers: hk.switchModifiers, active: $recording) { code, mods in
                        model.settings.hotkeys.switchKeyCode = code
                        model.settings.hotkeys.switchModifiers = mods
                    }
                    .disabled(!hk.switchEnabled)
                }
            }
            if model.hotkeyStatus.switchConflict { Label(tr("shortcut.conflictOther"), systemImage: "exclamationmark.triangle").font(DS.Font.caption).foregroundStyle(DS.Palette.warning) }
            SettingRow(title: tr("shortcut.lastTip"), detail: tr("shortcut.lastTipDetail")) {
                HStack {
                    Toggle(tr("shortcut.lastTip"), isOn: $model.settings.hotkeys.tipEnabled).labelsHidden().toggleStyle(.switch)
                    ShortcutRecorder(target: .lastTip, code: hk.tipKeyCode, modifiers: hk.tipModifiers, active: $recording) { code, mods in
                        model.settings.hotkeys.tipKeyCode = code
                        model.settings.hotkeys.tipModifiers = mods
                    }
                    .disabled(!hk.tipEnabled)
                }
            }
            if model.hotkeyStatus.tipConflict { Label(tr("shortcut.conflictOther"), systemImage: "exclamationmark.triangle").font(DS.Font.caption).foregroundStyle(DS.Palette.warning) }
            SettingRow(title: tr("shortcut.cancel"), detail: tr("shortcut.cancelDetail")) { Text("esc").font(DS.Font.mono).foregroundStyle(DS.Palette.secondaryText) }
        }
        KeyTestGroup()
        HStack { Spacer(); Button(tr("settings.resetSection")) { model.settings.hotkeys = HotkeySettings() }.buttonStyle(PillButtonStyle()) }
    }
}

// MARK: - Privacy

struct PrivacySettings: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDelete = false

    var body: some View {
        @Bindable var model = model
        SettingsGroup(title: tr("privacy.routes"), footer: nil) {
            routeRow("mic", tr("privacy.routeAudio"))
            routeRow("cpu", tr("privacy.routeASR"))
            routeRow(model.settings.provider.localOnly ? "lock" : "network", model.settings.provider.localOnly ? tr("privacy.routeLocalOnly") : tr("privacy.routeText", model.settings.provider.endpointHost ?? "—"))
            routeRow("internaldrive", tr("privacy.routeHistory"))
        }
        SettingsGroup(title: tr("privacy.retention"), footer: tr("privacy.retentionFooter")) {
            SettingRow(title: tr("privacy.keepText")) { Toggle(tr("privacy.keepText"), isOn: $model.settings.retention.keepText).labelsHidden().toggleStyle(.switch) }
            if model.settings.retention.keepText {
                SettingRow(title: tr("privacy.textDays")) {
                    Picker(tr("privacy.textDays"), selection: $model.settings.retention.textDays) {
                        Text(tr("privacy.forever")).tag(Int?.none)
                        ForEach([7, 30, 90, 365], id: \.self) { Text(tr("privacy.days", $0)).tag(Optional($0)) }
                    }.labelsHidden().fixedSize()
                }
                SettingRow(title: tr("privacy.keepAudio"), detail: tr("privacy.keepAudioDetail")) { Toggle(tr("privacy.keepAudio"), isOn: $model.settings.retention.keepAudio).labelsHidden().toggleStyle(.switch) }
                if model.settings.retention.keepAudio {
                    SettingRow(title: tr("privacy.audioDays")) {
                        Picker(tr("privacy.audioDays"), selection: $model.settings.retention.audioDays) {
                            ForEach([1, 7, 30], id: \.self) { Text(tr("privacy.days", $0)).tag($0) }
                        }.labelsHidden().fixedSize()
                    }
                }
            }
        }
        SettingsGroup(title: tr("privacy.data")) {
            SettingRow(title: tr("privacy.export"), detail: tr("privacy.exportDetail")) { Button(tr("privacy.exportButton")) { exportHistory() }.buttonStyle(PillButtonStyle()) }
            SettingRow(title: tr("privacy.showFolder")) { Button(tr("settings.open")) { NSWorkspace.shared.open(Paths.root) }.buttonStyle(PillButtonStyle()) }
            SettingRow(title: tr("privacy.deleteAll"), detail: tr("privacy.deleteAllDetail")) {
                Button(tr("privacy.deleteButton"), role: .destructive) { confirmDelete = true }.buttonStyle(PillButtonStyle())
            }
        }
        .confirmationDialog(tr("privacy.deleteConfirm"), isPresented: $confirmDelete) {
            Button(tr("privacy.deleteButton"), role: .destructive) { model.deleteAllHistory() }
        } message: { Text(tr("privacy.deleteConfirmDetail")) }
    }

    private func routeRow(_ symbol: String, _ text: String) -> some View {
        Label { Text(text).font(DS.Font.body).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol).foregroundStyle(DS.Palette.secondaryText) }
    }

    private func exportHistory() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Saywell history.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data: Data
        if url.pathExtension.lowercased() == "json" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            data = (try? encoder.encode(model.history.records)) ?? Data()
        } else {
            data = Data(HistoryExport.markdown(model.history.records).utf8)
        }
        try? data.write(to: url, options: .atomic)
    }
}

enum HistoryExport {
    static func markdown(_ records: [DictationRecord]) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Localizer.shared.locale
        var out = "# Saywell\n\n"
        for r in records {
            out += "## \(formatter.string(from: r.date)) · \(r.modeName)\n\n\(r.output)\n\n"
            if r.edited != nil { out += "> \(tr("history.original")): \(r.raw)\n\n" }
        }
        return out
    }
}
