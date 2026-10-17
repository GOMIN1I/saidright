import SaidrightCore
import SwiftUI
import UniformTypeIdentifiers

struct ModesSettings: View {
    @Environment(AppModel.self) private var model
    @State private var selection: UUID?
    @State private var showAdvanced = false
    @State private var importError = false

    var body: some View {
        @Bindable var model = model
        SettingsGroup(title: tr("modes.list"), footer: tr("modes.listFooter")) {
            ForEach(model.modes.modes) { mode in
                HStack(spacing: DS.Space.s) {
                    Image(systemName: mode.symbol).frame(width: 18)
                    Text(mode.name).font(DS.Font.body)
                    if mode.id == model.activeMode.id { Text(tr("modes.active")).font(.system(size: 10)).foregroundStyle(DS.Palette.secondaryText) }
                    Spacer()
                    ModeSummary(mode: mode)
                }
                .padding(.vertical, 4).padding(.horizontal, 6)
                .background(selection == mode.id ? DS.Palette.signal.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.small))
                .contentShape(Rectangle())
                .onTapGesture { selection = mode.id }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { selection = mode.id }
            }
            HStack {
                Button(tr("modes.duplicate")) { if let id = selection ?? model.modes.activeModeID, let copy = model.modes.duplicate(id, suffix: tr("modes.copySuffix")) { selection = copy.id } }
                Button(tr("modes.delete"), role: .destructive) { if let id = selection, model.modes.delete(id) { selection = model.modes.activeModeID } }
                    .disabled(selection == nil || model.modes.modes.count < 2)
                Spacer()
                Button(tr("modes.export")) { export() }
                Button(tr("modes.import")) { importModes() }
            }
            .buttonStyle(PillButtonStyle())
            if importError { Text(tr("modes.importFailed")).font(DS.Font.caption).foregroundStyle(DS.Palette.warning) }
        }
        .onAppear { if selection == nil { selection = model.modes.activeModeID } }

        if let id = selection, let index = model.modes.modes.firstIndex(where: { $0.id == id }) {
            ModeEditor(mode: Binding(get: { model.modes.modes[index] }, set: { model.modes.update($0) }), showAdvanced: $showAdvanced)
                .id(id)
        }
    }

    private func export() {
        guard let id = selection, let data = try? model.modes.export([id]) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (model.modes.modes.first { $0.id == id }?.name ?? "mode") + ".saidright-mode.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url { try? data.write(to: url, options: .atomic) }
    }

    private func importModes() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        do { let added = try model.modes.importModes(from: data); selection = added.first?.id; importError = false } catch { importError = true }
    }
}

struct ModeEditor: View {
    @Binding var mode: Mode
    @Binding var showAdvanced: Bool
    @Environment(AppModel.self) private var model

    static let symbols = ["bubble.left", "text.cursor", "waveform", "graduationcap", "envelope", "briefcase", "doc.text", "terminal", "list.bullet", "pencil"]

    var body: some View {
        SettingsGroup(title: tr("modes.edit")) {
            SettingRow(title: tr("modes.name")) {
                HStack {
                    Menu {
                        ForEach(Self.symbols, id: \.self) { s in Button { mode.symbol = s } label: { Image(systemName: s) } }
                    } label: { Image(systemName: mode.symbol) }.fixedSize().accessibilityLabel(tr("modes.symbol"))
                    TextField(tr("modes.name"), text: $mode.name).textFieldStyle(.roundedBorder).frame(width: 200)
                }
            }
            Divider()
            SettingRow(title: tr("modes.spoken"), detail: spokenDetail) { LanguageMultiPicker(selection: $mode.spokenLanguages) }
            SettingRow(title: tr("modes.recognizer"), detail: recognizerDetail) {
                Picker(tr("modes.recognizer"), selection: $mode.recognizer) {
                    Text(tr("engine.auto")).tag(RecognizerChoice.auto)
                    Divider()
                    Text(tr("engine.whisper")).tag(RecognizerChoice.whisper)
                    Text(tr("engine.parakeet")).tag(RecognizerChoice.parakeet)
                    Text(tr("engine.apple")).tag(RecognizerChoice.appleDictation).disabled(!AppleDictation.isAvailable)
                }.labelsHidden().fixedSize()
            }
            if mode.recognizer == .parakeet {
                switch ModelCatalog.parakeetFit(spokenLanguages: mode.spokenLanguages) {
                case .good: EmptyView()
                case .switchesRisky:
                    Label(tr("modes.parakeetSwitches"), systemImage: "exclamationmark.triangle").font(DS.Font.caption).foregroundStyle(DS.Palette.warning).fixedSize(horizontal: false, vertical: true)
                case .unsupported:
                    Label(tr("modes.parakeetUnsupported"), systemImage: "exclamationmark.triangle").font(DS.Font.caption).foregroundStyle(DS.Palette.warning).fixedSize(horizontal: false, vertical: true)
                }
                if ParakeetInstallation.current() == nil {
                    Label(tr("notice.installParakeet"), systemImage: "arrow.down.circle").font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText)
                }
            }
            if mode.recognizer == .appleDictation && mode.spokenLanguages.count != 1 {
                Label(tr("notice.appleOneLanguage"), systemImage: "exclamationmark.triangle").font(DS.Font.caption).foregroundStyle(DS.Palette.warning)
            }
            Divider()
            CleanupPicker(level: $mode.cleanup)
            if mode.cleanup == .rewrite {
                SettingRow(title: tr("modes.tone")) {
                    Picker(tr("modes.tone"), selection: $mode.tone) { ForEach(Tone.allCases, id: \.self) { Text(tr("tone.\($0.rawValue)")).tag($0) } }.labelsHidden().fixedSize()
                }
            }
            if mode.cleanup != .off {
                SettingRow(title: tr("modes.smartStructure"), detail: tr("modes.smartStructureDetail")) {
                    Toggle(tr("modes.smartStructure"), isOn: $mode.rules.smartStructure).labelsHidden().toggleStyle(.switch)
                }
                DisclosureGroup(tr("modes.rules")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(tr("rules.fillers"), isOn: $mode.rules.removeFillers)
                        Toggle(tr("rules.repetitions"), isOn: $mode.rules.removeRepetitions)
                        Toggle(tr("rules.profanity"), isOn: $mode.rules.keepProfanity)
                        Toggle(tr("rules.slang"), isOn: $mode.rules.keepSlang)
                        Toggle(tr("rules.paragraphs"), isOn: $mode.rules.allowParagraphs)
                        Toggle(tr("rules.spokenFormatting"), isOn: $mode.rules.spokenFormatting)
                    }
                    .toggleStyle(.checkbox).padding(.top, 4)
                }
                .font(DS.Font.body)
            }
            Divider()
            SettingRow(title: tr("modes.learning"), detail: tr("learning.\(mode.learning.rawValue).detail")) {
                Picker(tr("modes.learning"), selection: $mode.learning) { ForEach(LearningLevel.allCases, id: \.self) { Text(tr("learning.\($0.rawValue)")).tag($0) } }.labelsHidden().fixedSize()
            }
            if mode.learning != .off {
                SettingRow(title: tr("modes.learningLanguage"), detail: learningCoverage) {
                    Picker(tr("modes.learningLanguage"), selection: $mode.learningLanguage) { ForEach(LanguageCatalog.all) { Text($0.nativeName).tag($0.id) } }.labelsHidden().fixedSize()
                }
                SettingRow(title: tr("modes.explanationLanguage")) {
                    Picker(tr("modes.explanationLanguage"), selection: $mode.explanationLanguage) {
                        Text(tr("modes.sameAsInterface")).tag(String?.none)
                        ForEach(LanguageCatalog.all) { Text($0.nativeName).tag(Optional($0.id)) }
                    }.labelsHidden().fixedSize()
                }
            }
            Divider()
            SettingRow(title: tr("modes.output"), detail: tr("output.\(mode.output.rawValue).detail")) {
                Picker(tr("modes.output"), selection: $mode.output) { ForEach(OutputAction.allCases, id: \.self) { Text(tr("output.\($0.rawValue)")).tag($0) } }.labelsHidden().fixedSize()
            }
            if mode.needsProviderAutomatically {
                Label(model.settings.provider.localOnly && !model.settings.provider.isOnDevice ? tr("modes.blockedLocalOnly") : tr("modes.usesProvider", model.settings.provider.endpointHost ?? "—"), systemImage: "network")
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText)
            } else {
                Label(tr("modes.fullyLocal"), systemImage: "lock").font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText)
            }
            DisclosureGroup(tr("modes.advanced"), isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("modes.extraDetail")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
                    TextEditor(text: $mode.extraInstructions).font(DS.Font.mono).frame(height: 80).scrollContentBackground(.hidden).padding(4).background(DS.Palette.readingSurface, in: RoundedRectangle(cornerRadius: DS.Radius.small))
                    if mode.cleanup != .off {
                        DisclosureGroup(tr("modes.viewInstructions")) {
                            Text(EditorPrompt.system(for: mode)).font(DS.Font.mono).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }.font(DS.Font.caption)
                    }
                }
            }
            .font(DS.Font.body)
            HStack {
                Spacer()
                if mode.presetID != nil { Button(tr("modes.resetPreset")) { mode = ModePresets.reset(mode) }.buttonStyle(PillButtonStyle()) }
            }
        }
    }

    private var recognizerDetail: String {
        switch mode.recognizer {
        case .auto: tr("modes.autoDetail", model.engine(for: mode) == .parakeet ? tr("engine.parakeetShort") : tr("engine.whisperShort"))
        case .whisper: tr("modes.whisperDetail")
        case .parakeet: tr("modes.parakeetDetail")
        case .appleDictation: tr("modes.appleDetail")
        }
    }

    private var spokenDetail: String {
        switch mode.spokenLanguages.count {
        case 0: tr("modes.spokenAny")
        case 1: tr("modes.spokenOne")
        default: tr("modes.spokenMany")
        }
    }

    private var learningCoverage: String {
        switch LanguageCatalog.info(mode.learningLanguage)?.learningStatus {
        case .tested: tr("coverage.tested")
        case .modelSupported: tr("coverage.modelSupported")
        default: tr("coverage.experimental")
        }
    }
}

/// The four cleanup levels with a concrete before/after so the effect is clear before speaking.
struct CleanupPicker: View {
    @Binding var level: CleanupLevel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(tr("modes.cleanup")).font(DS.Font.body).settingAnchor(tr("modes.cleanup"))
            Picker(tr("modes.cleanup"), selection: $level) { ForEach(CleanupLevel.allCases, id: \.self) { Text(tr("cleanup.\($0.rawValue)")).tag($0) } }
                .labelsHidden().pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("cleanup.\(level.rawValue).detail")).font(DS.Font.caption).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 6) {
                    Text(tr("cleanup.exampleSaid")).font(.system(size: 10, weight: .semibold)).foregroundStyle(DS.Palette.secondaryText).frame(width: 64, alignment: .leading)
                    Text(tr("cleanup.example.input")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText)
                }
                HStack(alignment: .top, spacing: 6) {
                    Text(tr("cleanup.exampleResult")).font(.system(size: 10, weight: .semibold)).foregroundStyle(DS.Palette.secondaryText).frame(width: 64, alignment: .leading)
                    Text(tr("cleanup.example.\(level.rawValue)")).font(DS.Font.caption)
                }
            }
            .padding(DS.Space.s)
            .background(DS.Palette.quietFill, in: RoundedRectangle(cornerRadius: DS.Radius.small))
        }
    }
}

/// Picks zero (auto), one (fixed) or several (restricted detection) spoken languages.
struct LanguageMultiPicker: View {
    @Binding var selection: [String]

    var body: some View {
        Menu {
            Button { selection = [] } label: { Label(tr("lang.auto"), systemImage: selection.isEmpty ? "checkmark" : "") }
            Divider()
            ForEach(LanguageCatalog.all) { lang in
                Button {
                    if let i = selection.firstIndex(of: lang.id) { selection.remove(at: i) } else { selection.append(lang.id) }
                } label: {
                    Label(lang.nativeName + (lang.recognitionStatus == .tested ? "" : lang.recognitionStatus == .modelSupported ? " ·" : " ··"), systemImage: selection.contains(lang.id) ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection.isEmpty ? tr("lang.auto") : selection.compactMap { LanguageCatalog.info($0)?.nativeName }.joined(separator: ", ")).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
            }
        }
        .fixedSize()
        .help(tr("lang.coverageHelp"))
    }
}
