import SaywellCore
import SwiftUI

struct RecognitionSettings: View {
    @Environment(AppModel.self) private var model
    @State private var installer = RuntimeInstaller()
    @State private var appleStatus: [String: Bool] = [:]
    @State private var appleInstalling: String?
    @State private var confirmRemove = false

    var body: some View {
        SpeechModelsGroup(installer: installer)
        if let installation = model.whisperInstallation {
            SettingsGroup(title: tr("engine.whisper"), footer: tr("engine.whisperFooter")) {
                HStack(alignment: .top) {
                    Text(installation.isLegacy ? tr("engine.usingLegacy") : tr("engine.usingOwn", ByteCountFormatter.string(fromByteCount: RuntimeInstaller.ownInstallationSize(), countStyle: .file)))
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    stateLabel
                }
                installerControls(installed: true)
            }
        }
        SettingsGroup(title: tr("engine.apple"), footer: tr("engine.appleFooter")) {
            if AppleDictation.isAvailable {
                ForEach(["ru", "en", "de", "zh-Hans"], id: \.self) { id in
                    SettingRow(title: LanguageCatalog.info(id)?.nativeName ?? id) {
                        if appleInstalling == id { ProgressView().controlSize(.small) }
                        else if appleStatus[id] == true { Label(tr("engine.appleReady"), systemImage: "checkmark.circle").font(DS.Font.caption).foregroundStyle(DS.Palette.success) }
                        else {
                            Button(tr("engine.appleDownload")) { installApple(id) }.buttonStyle(PillButtonStyle())
                        }
                    }
                }
            } else {
                Text(tr("notice.appleUnavailable")).font(DS.Font.caption)
            }
        }
        .task { await refreshApple() }
        SettingsGroup(title: tr("engine.matrix")) { CapabilityMatrix() }
        SettingsGroup(title: tr("engine.vocabulary"), footer: tr("engine.vocabularyFooter")) { VocabularyEditor() }
    }

    @ViewBuilder private var stateLabel: some View {
        switch model.recognizer {
        case .ready: Label(tr("recognizer.readyLocal"), systemImage: "checkmark.circle.fill").foregroundStyle(DS.Palette.success).font(DS.Font.caption)
        case .loading: HStack(spacing: 4) { ProgressView().controlSize(.mini); Text(tr("status.loading")) }.font(DS.Font.caption)
        case .installing: Text(tr("status.installing")).font(DS.Font.caption)
        case .notInstalled: Label(tr("recognizer.notInstalled"), systemImage: "arrow.down.circle").font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText)
        case .failed(let m): Label(m, systemImage: "exclamationmark.triangle").font(DS.Font.caption).foregroundStyle(DS.Palette.warning).lineLimit(3)
        }
    }

    @ViewBuilder private func installerControls(installed: Bool) -> some View {
        switch installer.stage {
        case .idle, .done, .cancelled, .failed:
            HStack {
                if !installed {
                    Text(tr("install.sizeNote", ByteCountFormatter.string(fromByteCount: RuntimeInstaller.runtimeBytes + RuntimeInstaller.modelBytes, countStyle: .file), ByteCountFormatter.string(fromByteCount: RuntimeInstaller.freeSpace(), countStyle: .file)))
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(tr("install.button")) { installer.install(model: model) }.buttonStyle(PillButtonStyle(prominent: true))
                } else {
                    Spacer()
                    Button(tr("engine.restart")) { model.restartRecognizer() }.buttonStyle(PillButtonStyle())
                    if !(model.whisperInstallation?.isLegacy ?? true) {
                        Button(tr("engine.repair")) { RuntimeInstaller.removeOwnInstallation(); installer.install(model: model) }.buttonStyle(PillButtonStyle())
                        Button(tr("engine.remove"), role: .destructive) { confirmRemove = true }.buttonStyle(PillButtonStyle())
                    }
                }
            }
            if case .failed(let message) = installer.stage { Label(message, systemImage: "exclamationmark.triangle").font(DS.Font.caption).foregroundStyle(DS.Palette.warning) }
            if case .cancelled = installer.stage { Text(tr("install.cancelled")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText) }
        default:
            HStack {
                ProgressView(value: fraction).frame(maxWidth: .infinity)
                Button(tr("common.cancel")) { installer.cancel() }.buttonStyle(PillButtonStyle())
            }
            Text(stageText).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText)
        }
        EmptyView()
            .confirmationDialog(tr("engine.removeConfirm"), isPresented: $confirmRemove) {
                Button(tr("engine.remove"), role: .destructive) { RuntimeInstaller.removeOwnInstallation(); model.restartRecognizer() }
            }
    }

    private var fraction: Double? {
        switch installer.stage {
        case .downloadingModel(let f), .downloadingTool(let f): f
        default: nil
        }
    }

    private var stageText: String {
        switch installer.stage {
        case .checkingSpace: tr("install.stage.space")
        case .downloadingTool: tr("install.stage.tool")
        case .installingPython: tr("install.stage.python")
        case .installingPackages: tr("install.stage.packages")
        case .downloadingModel(let f): tr("install.stage.model", Int((f ?? 0) * 100))
        case .verifying: tr("install.stage.verify")
        case .loading: tr("status.loading")
        default: ""
        }
    }

    private func refreshApple() async {
        for id in ["ru", "en", "de", "zh-Hans"] { appleStatus[id] = (try? await AppleDictation.ensureAsset(id, install: false)) ?? false }
    }

    private func installApple(_ id: String) {
        appleInstalling = id
        Task {
            appleStatus[id] = (try? await AppleDictation.ensureAsset(id, install: true)) ?? false
            appleInstalling = nil
        }
    }
}

/// Honest coverage per language and capability.
struct CapabilityMatrix: View {
    let languages = ["ru", "en", "de", "zh-Hans", "es", "fr", "uk", "ja", "ar"]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text(tr("matrix.language")); Text("Whisper"); Text("Parakeet"); Text(tr("engine.appleShort")); Text(tr("matrix.learning")); Text(tr("matrix.tts"))
            }
            .font(DS.Font.sectionTitle).foregroundStyle(DS.Palette.secondaryText)
            ForEach(languages, id: \.self) { id in
                let info = LanguageCatalog.info(id)!
                GridRow {
                    Text(info.nativeName)
                    coverage(info.recognitionStatus)
                    Text(ModelCatalog.parakeet.languages?.contains(id) == true ? (["ru", "en", "de"].contains(id) ? tr("coverage.tested") : tr("coverage.modelSupported")) : "—").foregroundStyle(["ru", "en", "de"].contains(id) ? DS.Palette.success : DS.Palette.secondaryText)
                    Text(["ru", "en", "de", "zh-Hans", "es", "fr", "ja"].contains(id) ? tr("coverage.system") : "—").foregroundStyle(DS.Palette.secondaryText)
                    coverage(info.learningStatus)
                    Text(SpeechService.hasVoice(for: id) ? tr("coverage.installed") : tr("coverage.noVoice")).foregroundStyle(DS.Palette.secondaryText)
                }
            }
        }
        .font(DS.Font.caption)
        Text(tr("matrix.legend")).font(.system(size: 10)).foregroundStyle(DS.Palette.tertiaryText).fixedSize(horizontal: false, vertical: true)
    }

    private func coverage(_ status: CoverageStatus) -> some View {
        Text(tr("coverage.\(status.rawValue)")).foregroundStyle(status == .tested ? DS.Palette.success : DS.Palette.secondaryText)
    }
}

/// Personal terms. Each entry says explicitly what it affects.
struct VocabularyEditor: View {
    @Environment(AppModel.self) private var model
    @State private var term = ""

    var body: some View {
        HStack {
            TextField(tr("vocab.placeholder"), text: $term).textFieldStyle(.roundedBorder).onSubmit(add)
            Button(tr("vocab.add"), action: add).buttonStyle(PillButtonStyle()).disabled(term.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        ForEach(model.history.vocabulary) { entry in
            HStack {
                Text(entry.term).font(DS.Font.body)
                Spacer()
                Toggle(tr("vocab.hint"), isOn: binding(entry, .recognitionHint)).toggleStyle(.checkbox).font(DS.Font.caption)
                Toggle(tr("vocab.learning"), isOn: binding(entry, .learning)).toggleStyle(.checkbox).font(DS.Font.caption)
                Button { model.removeVocabulary(entry.id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).accessibilityLabel(tr("vocab.remove"))
            }
        }
    }

    private func add() {
        let value = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !model.history.vocabulary.contains(where: { $0.term == value }) else { return }
        model.addVocabulary(VocabularyEntry(term: String(value.prefix(60)), uses: [.recognitionHint]))
        term = ""
    }

    private func binding(_ entry: VocabularyEntry, _ use: VocabularyUse) -> Binding<Bool> {
        Binding(get: { entry.uses.contains(use) }, set: { on in
            var e = entry
            if on { e.uses.insert(use) } else { e.uses.remove(use) }
            model.updateVocabulary(e)
        })
    }
}

// MARK: - Text processing

struct TextSettings: View {
    @Environment(AppModel.self) private var model
    @State private var keyDraft = ""
    @State private var testState: String?
    @State private var models: [String] = []
    @State private var testing = false

    var body: some View {
        @Bindable var model = model
        SettingsGroup(title: tr("text.localOnly"), footer: tr("text.localOnlyFooter")) {
            SettingRow(title: tr("text.localOnlyToggle"), detail: tr("text.localOnlyDetail")) {
                Toggle(tr("text.localOnlyToggle"), isOn: $model.settings.provider.localOnly).labelsHidden().toggleStyle(.switch)
            }
        }
        LocalTextModelsGroup()
        SettingsGroup(title: tr("text.provider"), footer: tr("text.costFooter")) {
            SettingRow(title: tr("text.service")) {
                Picker(tr("text.service"), selection: $model.settings.provider.kind) {
                    Text("OpenAI").tag(ProviderKind.openAI)
                    Text(tr("text.compatible")).tag(ProviderKind.compatible)
                }.labelsHidden().fixedSize()
            }
            if model.settings.provider.kind == .openAI {
                SettingRow(title: tr("text.model"), detail: tr("text.modelDetail")) {
                    HStack {
                        TextField(tr("text.model"), text: $model.settings.provider.openAIModel).textFieldStyle(.roundedBorder).frame(width: 160)
                        if !models.isEmpty {
                            Menu("") { ForEach(models, id: \.self) { m in Button(m) { model.settings.provider.openAIModel = m } } }.fixedSize()
                        }
                    }
                }
            } else {
                SettingRow(title: tr("text.baseURL"), detail: tr("text.baseURLDetail")) {
                    TextField("http://localhost:11434/v1", text: $model.settings.provider.compatibleBaseURL).textFieldStyle(.roundedBorder).frame(width: 240).accessibilityLabel(tr("text.baseURL"))
                }
                SettingRow(title: tr("text.model")) {
                    TextField(tr("text.model"), text: $model.settings.provider.compatibleModel).textFieldStyle(.roundedBorder).frame(width: 200)
                }
                SettingRow(title: tr("text.noReasoning"), detail: tr("text.noReasoningDetail")) {
                    Toggle(tr("text.noReasoning"), isOn: $model.settings.provider.compatibleNoReasoning).labelsHidden().toggleStyle(.switch)
                }
            }
            Divider()
            SettingRow(title: tr("text.key"), detail: model.hasCredential ? tr("text.keySaved") : tr("text.keyMissing")) {
                if model.hasCredential {
                    Button(tr("text.keyRemove"), role: .destructive) { model.removeCredential() }.buttonStyle(PillButtonStyle())
                } else {
                    HStack {
                        SecureField(tr("text.keyPlaceholder"), text: $keyDraft).textFieldStyle(.roundedBorder).frame(width: 200).accessibilityLabel(tr("text.key"))
                        Button(tr("text.keySave")) { if model.saveCredential(keyDraft) { keyDraft = "" } }.buttonStyle(PillButtonStyle(prominent: true)).disabled(keyDraft.isEmpty)
                    }
                }
            }
            if !model.hasCredential && model.settings.provider.kind == .openAI && FileManager.default.fileExists(atPath: Paths.legacyRoot.path) {
                SettingRow(title: tr("text.importLegacy"), detail: tr("text.importLegacyDetail")) {
                    Button(tr("text.importButton")) { testState = model.importLegacyCredential() ? tr("text.importOK") : tr("text.importNone") }.buttonStyle(PillButtonStyle())
                }
            }
            HStack {
                Button(tr("text.listModels")) { listModels() }.buttonStyle(PillButtonStyle()).disabled(testing)
                Button(tr("text.test")) { test() }.buttonStyle(PillButtonStyle()).disabled(testing)
                if testing { ProgressView().controlSize(.small) }
                Spacer()
            }
            if let testState { Text(testState).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func listModels() {
        testing = true
        Task {
            do { models = try await model.makeProvider().listModels(); testState = tr("text.modelsFound", models.count) }
            catch let e as ProviderError { testState = AppModel.message(for: EditFailure.provider(e)) }
            catch { testState = tr("error.generic") }
            testing = false
        }
    }

    /// One small, explicit request; the person starts it and it costs a fraction of a cent.
    private func test() {
        testing = true
        Task {
            var mode = ModePresets.starter(names: [:], spoken: ["en"])[1]
            mode.cleanup = .correct
            let result = await TextPipeline.edit(raw: "she go to school every day and dont like it", mode: mode, provider: { try model.makeProvider() })
            if let failure = result.failure { testState = AppModel.message(for: failure) } else { testState = tr("text.testOK", result.output) }
            testing = false
        }
    }
}

// MARK: - Learning

struct LearningSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        SettingsGroup(title: tr("learn.capsule"), footer: tr("learn.capsuleFooter")) {
            SettingRow(title: tr("learn.presentation"), detail: tr("learn.presentationDetail")) {
                Picker(tr("learn.presentation"), selection: $model.settings.learningUI.presentation) {
                    ForEach(HintPresentation.allCases, id: \.self) { Text(tr("presentation.\($0.rawValue)")).tag($0) }
                }.labelsHidden().fixedSize()
            }
            if model.settings.learningUI.presentation != .window {
                SettingRow(title: tr("learn.linger"), detail: tr("learn.lingerDetail")) {
                    Picker(tr("learn.linger"), selection: $model.settings.learningUI.linger) {
                        ForEach(HintLinger.allCases, id: \.self) { Text(tr("linger.\($0.rawValue)")).tag($0) }
                    }.labelsHidden().fixedSize()
                }
                SettingRow(title: tr("learn.uncertain"), detail: tr("learn.uncertainDetail")) {
                    Toggle(tr("learn.uncertain"), isOn: $model.settings.learningUI.showUncertainInCapsule).labelsHidden().toggleStyle(.switch)
                }
            }
            HStack {
                Spacer()
                Button(tr("learn.tryHint")) { model.capsule.previewing = false; model.capsule.previewHint() }.buttonStyle(PillButtonStyle())
            }
        }
        SettingsGroup(title: tr("learn.explanations"), footer: tr("learn.explanationsFooter")) {
            SettingRow(title: tr("learn.depth"), detail: tr("learn.depthDetail")) {
                Picker(tr("learn.depth"), selection: $model.settings.learningUI.depth) {
                    ForEach(ExplanationDepth.allCases, id: \.self) { Text(tr("depth.\($0.rawValue)")).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            SettingRow(title: tr("learn.level"), detail: tr("learn.levelDetail")) {
                Picker(tr("learn.level"), selection: $model.settings.learningUI.level) {
                    ForEach(LearnerLevel.allCases, id: \.self) { Text(tr("level.\($0.rawValue)")).tag($0) }
                }.labelsHidden().fixedSize()
            }
            SettingRow(title: tr("modes.explanationLanguage")) {
                Picker(tr("modes.explanationLanguage"), selection: $model.settings.explanationLanguage) {
                    Text(tr("modes.sameAsInterface")).tag(String?.none)
                    ForEach(LanguageCatalog.all) { Text($0.nativeName).tag(Optional($0.id)) }
                }.labelsHidden().fixedSize()
            }
            SettingRow(title: tr("learn.goal"), detail: tr("learn.goalDetail")) {
                TextField(tr("learn.goalPlaceholder"), text: $model.settings.learningGoal).textFieldStyle(.roundedBorder).frame(width: 240).accessibilityLabel(tr("learn.goal"))
            }
        }
        SettingsGroup(title: tr("learn.voice"), footer: tr("learn.voiceFooter")) {
            ForEach(Set(model.modes.modes.filter { $0.learning != .off }.map(\.learningLanguage)).sorted(), id: \.self) { lang in
                SettingRow(title: LanguageCatalog.info(lang)?.nativeName ?? lang) {
                    Picker(LanguageCatalog.info(lang)?.nativeName ?? lang, selection: Binding(get: { model.settings.speech.voices[lang] }, set: { model.settings.speech.voices[lang] = $0 })) {
                        Text(tr("learn.defaultVoice")).tag(String?.none)
                        ForEach(SpeechService.voices(for: lang), id: \.identifier) { v in Text(v.name).tag(Optional(v.identifier)) }
                    }.labelsHidden().frame(width: 200)
                }
            }
            SettingRow(title: tr("learn.rate")) { Slider(value: $model.settings.speech.rate, in: 0.3...0.6).frame(width: 180).accessibilityLabel(tr("learn.rate")) }
        }
        SettingsGroup(title: tr("learn.progress"), footer: tr("learn.progressFooter")) {
            let topics = model.history.confirmedTopics()
            Text(tr("learn.analysed", topics.analysedSessions, model.history.cards.count)).font(DS.Font.body)
            ForEach(topics.topics.prefix(6), id: \.topic) { t in
                HStack { Text(t.topic); Spacer(); Text("\(t.count)").font(DS.Font.mono) }.font(DS.Font.caption)
            }
        }
    }
}

// MARK: - Advanced

struct AdvancedSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        SettingsGroup(title: tr("adv.delivery")) {
            SettingRow(title: tr("adv.restoreClipboard"), detail: tr("adv.restoreClipboardDetail")) { Toggle(tr("adv.restoreClipboard"), isOn: $model.settings.restoreClipboard).labelsHidden().toggleStyle(.switch) }
        }
        SettingsGroup(title: tr("adv.automation"), footer: tr("adv.automationFooter")) {
            SettingRow(title: tr("adv.automationToggle")) { Toggle(tr("adv.automationToggle"), isOn: $model.settings.allowAutomationLinks).labelsHidden().toggleStyle(.switch) }
        }
        SettingsGroup(title: tr("adv.credits"), footer: tr("adv.creditsFooter")) {
            ForEach(Credits.all, id: \.name) { credit in
                VStack(alignment: .leading, spacing: 1) {
                    Text(credit.name).font(DS.Font.body.weight(.medium))
                    Text(credit.detail).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        SettingsGroup(title: tr("adv.diagnostics"), footer: tr("adv.diagnosticsFooter")) {
            let s = model.hotkeyStatus
            let p = model.permissions
            Text(diagnostics(s, p)).font(DS.Font.mono).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(tr("adv.copyDiagnostics")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(diagnostics(s, p) + "\n\n" + model.recognizerDiagnostics, forType: .string)
                }.buttonStyle(PillButtonStyle())
                Button(tr("adv.openLogs")) { NSWorkspace.shared.open(Paths.logs) }.buttonStyle(PillButtonStyle())
            }
        }
    }

    private func diagnostics(_ s: HotkeyService.Status, _ p: Permissions) -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let lines = [
            "Saywell \(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "signing: \(p.signing.isAdHoc ? "ad hoc" : "team \(p.signing.teamID ?? "?")")",
            "microphone: \(p.microphone)  input-monitoring: \(p.listenEvents)  accessibility: \(p.accessibility)  post-events: \(p.postEvents)",
            "tap installed: \(s.tapInstalled)  tap events seen: \(s.tapReceivedEvents)  secure input: \(s.secureInput)",
            "combo registered: \(s.comboRegistered) conflict: \(s.comboConflict)  switch registered: \(s.switchRegistered)",
            "recognizer: \(model.recognizer)  installation: \(model.whisperInstallation.map { $0.isLegacy ? "legacy (Govori, in place)" : "own" } ?? "none")",
            "provider: \(model.settings.provider.kind.rawValue) model=\(model.settings.provider.model) localOnly=\(model.settings.provider.localOnly) key=\(model.hasCredential ? "present" : "absent")",
        ]
        return lines.joined(separator: "\n")
    }
}


/// The recognizers Saywell can run, with honest facts and one-click install per model.
struct SpeechModelsGroup: View {
    @Environment(AppModel.self) private var model
    var installer: RuntimeInstaller
    @State private var confirm: SpeechModel?

    var body: some View {
        let recommended = ModelCatalog.recommendedWhisper(spokenLanguages: Array(Set(model.modes.modes.flatMap(\.spokenLanguages))).sorted(), physicalMemory: ProcessInfo.processInfo.physicalMemory)
        SettingsGroup(title: tr("models.speech"), footer: tr("models.speechFooter")) {
            ForEach(ModelCatalog.all) { entry in
                ModelRow(entry: entry, recommended: entry.id == recommended.id, installer: installer, confirm: $confirm)
                if entry.id != ModelCatalog.all.last?.id { Divider() }
            }
        }
        .confirmationDialog(confirm.map { tr("models.confirmTitle", tr("model.\($0.id).name")) } ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), presenting: confirm) { entry in
            Button(tr("install.button")) {
                if entry.engine == .parakeetMLX {
                    installer.installParakeet(model: model)
                } else {
                    model.settings.whisperModel = entry.id
                    installer.install(model: model)
                }
            }
        } message: { entry in
            Text(tr("models.confirmDetail", ByteCountFormatter.string(fromByteCount: Self.downloadSize(entry), countStyle: .file), ByteCountFormatter.string(fromByteCount: RuntimeInstaller.freeSpace(), countStyle: .file)))
        }
    }

    /// What will actually be downloaded: parts already on this Mac are not counted.
    static func downloadSize(_ entry: SpeechModel) -> Int64 {
        if entry.engine == .parakeetMLX {
            return (ParakeetInstallation.modelPresent() ? 0 : entry.downloadBytes) + (ParakeetInstallation.runtimeReady() ? 0 : RuntimeInstaller.parakeetRuntimeBytes)
        }
        return entry.downloadBytes + (WhisperInstallation.runtime() == nil ? RuntimeInstaller.runtimeBytes : 0)
    }
}

private struct ModelRow: View {
    @Environment(AppModel.self) private var model
    var entry: SpeechModel
    var recommended: Bool
    var installer: RuntimeInstaller
    @Binding var confirm: SpeechModel?

    var body: some View {
        let installedAt = entry.engine == .whisperMLX ? WhisperInstallation.installedModel(entry) : nil
        let selected = entry.engine == .whisperMLX && model.settings.whisperModel == entry.id
        let installing = installer.isRunning && installer.target == entry.id
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(tr("model.\(entry.id).name")).font(DS.Font.body.weight(.semibold))
                if recommended && entry.engine == .whisperMLX { Tag(text: tr("models.recommended"), color: DS.Palette.signal) }
                if entry.engine == .parakeetMLX { Tag(text: tr("models.fastest"), color: DS.Palette.success) }
                if entry.quality < 2 { Tag(text: tr("models.notTested"), color: DS.Palette.warning) }
                Spacer()
                status(installedAt: installedAt, selected: selected)
            }
            Text(tr("model.\(entry.id).detail")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.m) {
                if entry.engine != .appleOnDevice {
                    Fact(symbol: "arrow.down.circle", text: ByteCountFormatter.string(fromByteCount: entry.downloadBytes, countStyle: .file))
                    Fact(symbol: "memorychip", text: tr("models.memory", ByteCountFormatter.string(fromByteCount: entry.memoryEstimateBytes, countStyle: .memory)))
                } else {
                    Fact(symbol: "arrow.down.circle", text: tr("models.systemAsset"))
                }
                Fact(symbol: "gauge.with.dots.needle.67percent", text: tr("models.speed", Meter.text(entry.speed)))
                Fact(symbol: "checkmark.seal", text: tr("models.quality", Meter.text(entry.quality)))
                Fact(symbol: entry.handlesMixedLanguages ? "character.bubble" : "1.circle", text: entry.handlesMixedLanguages ? tr("models.mixed") : tr("models.oneLanguage"))
            }
            .font(.system(size: 10.5))
            .foregroundStyle(DS.Palette.secondaryText)
            .help(tr("models.estimatesHelp"))
            if installing { progress }
            if entry.engine == .parakeetMLX, case .failed(let message) = installer.stage, installer.target == entry.id {
                Label(message, systemImage: "exclamationmark.triangle").font(DS.Font.caption).foregroundStyle(DS.Palette.warning)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func status(installedAt: URL?, selected: Bool) -> some View {
        switch entry.engine {
        case .parakeetMLX:
            if ParakeetInstallation.current() != nil {
                let candidates = model.modes.modes.filter { $0.recognizer == .whisper }
                HStack(spacing: 6) {
                    let users = model.modes.modes.filter { model.engine(for: $0) == .parakeet }.count
                    Text(users > 0 ? tr("models.parakeetModes", users) : tr("models.perMode")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText)
                    if !candidates.isEmpty {
                        Button(tr("models.useAuto")) {
                            for var m in candidates { m.recognizer = .auto; model.modes.update(m) }
                        }
                        .buttonStyle(PillButtonStyle(prominent: true)).disabled(model.isBusy)
                        .help(tr("models.useAutoHelp"))
                    }
                    Button(tr("engine.remove"), role: .destructive) {
                        for var m in model.modes.modes where m.recognizer == .parakeet { m.recognizer = .auto; model.modes.update(m) }
                        model.stopParakeet()
                        RuntimeInstaller.removeParakeet()
                    }.buttonStyle(PillButtonStyle()).disabled(model.isBusy || installer.isRunning)
                }
            } else if !installer.isRunning {
                Button(tr("models.download")) { confirm = entry }.buttonStyle(PillButtonStyle()).disabled(model.isBusy)
            }
        case .appleOnDevice:
            Text(AppleDictation.isAvailable ? tr("models.perMode") : tr("notice.appleUnavailable")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText)
        case .whisperMLX:
            if selected && installedAt != nil {
                Label(tr("models.inUse"), systemImage: "checkmark.circle.fill").font(DS.Font.caption).foregroundStyle(DS.Palette.success)
            } else if installedAt != nil {
                HStack(spacing: 6) {
                    Button(tr("models.use")) { model.settings.whisperModel = entry.id }.buttonStyle(PillButtonStyle()).disabled(model.isBusy || installer.isRunning)
                    if installedAt?.path.hasPrefix(Paths.legacyRoot.path) == false {
                        Button(tr("engine.remove"), role: .destructive) { RuntimeInstaller.removeOwnModel(entry); model.restartRecognizer() }.buttonStyle(PillButtonStyle()).disabled(model.isBusy || installer.isRunning)
                    }
                }
            } else if !installer.isRunning {
                Button(tr("models.download")) { confirm = entry }.buttonStyle(PillButtonStyle(prominent: recommended)).disabled(model.isBusy)
            }
        }
    }

    @ViewBuilder private var progress: some View {
        let fraction: Double? = if case .downloadingModel(let f) = installer.stage { f } else { nil }
        HStack {
            ProgressView(value: fraction).frame(maxWidth: .infinity)
            Button(tr("common.cancel")) { installer.cancel() }.buttonStyle(PillButtonStyle())
        }
    }
}

private struct Tag: View {
    var text: String
    var color: Color
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15))).foregroundStyle(color)
    }
}

private struct Fact: View {
    var symbol: String
    var text: String
    var body: some View { Label(text, systemImage: symbol).labelStyle(.titleAndIcon).lineLimit(1) }
}

/// Relative speed/quality in words, never a fake score.
enum Meter {
    static func text(_ level: Int) -> String { level >= 3 ? tr("meter.high") : level == 2 ? tr("meter.medium") : tr("meter.low") }
}


/// Free local editing and learning through Ollama, with sizes before download.
struct LocalTextModelsGroup: View {
    @Environment(AppModel.self) private var model
    @State private var ollama = OllamaService()
    @State private var confirm: LocalTextModel?

    var body: some View {
        SettingsGroup(title: tr("ollama.title"), footer: tr("ollama.footer")) {
            switch ollama.status {
            case .unknown:
                ProgressView().controlSize(.small)
            case .notRunning:
                Text(tr("ollama.notRunning")).font(DS.Font.body).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(tr("ollama.getIt")) { NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!) }.buttonStyle(PillButtonStyle())
                    Button(tr("ollama.checkAgain")) { Task { await ollama.refresh() } }.buttonStyle(PillButtonStyle())
                    Spacer()
                }
            case .running(let version):
                Label(tr("ollama.running", version), systemImage: "checkmark.circle.fill").font(DS.Font.caption).foregroundStyle(DS.Palette.success)
                ForEach(LocalTextModel.recommended) { entry in
                    row(entry)
                }
                if let error = ollama.error { Label(error, systemImage: "exclamationmark.triangle").font(DS.Font.caption).foregroundStyle(DS.Palette.warning) }
            }
        }
        .task { await ollama.refresh() }
        .confirmationDialog(confirm.map { tr("ollama.confirmTitle", $0.id) } ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), presenting: confirm) { entry in
            Button(tr("models.download")) { ollama.pull(entry.id) }
        } message: { entry in
            Text(tr("ollama.confirmDetail", ByteCountFormatter.string(fromByteCount: entry.downloadBytes, countStyle: .file), ByteCountFormatter.string(fromByteCount: RuntimeInstaller.freeSpace(), countStyle: .file)))
        }
    }

    private func row(_ entry: LocalTextModel) -> some View {
        let inUse = model.settings.provider.kind == .compatible && model.settings.provider.compatibleModel == entry.id && model.settings.provider.isOnDevice
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(entry.id).font(DS.Font.body.weight(.semibold))
                if entry.testedHere { Text(tr("ollama.tested")).font(.system(size: 10, weight: .semibold)).foregroundStyle(DS.Palette.success) }
                Spacer()
                if inUse {
                    Label(tr("models.inUse"), systemImage: "checkmark.circle.fill").font(DS.Font.caption).foregroundStyle(DS.Palette.success)
                } else if ollama.isInstalled(entry.id) {
                    Button(tr("models.use")) { model.settings.provider = OllamaService.providerSettings(for: entry, keeping: model.settings.provider) }.buttonStyle(PillButtonStyle())
                } else if ollama.pulling == entry.id {
                    Button(tr("common.cancel")) { ollama.cancel() }.buttonStyle(PillButtonStyle())
                } else {
                    Button(tr("models.download")) { confirm = entry }.buttonStyle(PillButtonStyle()).disabled(ollama.pulling != nil)
                }
            }
            Text(tr(entry.noteKey) + " · " + ByteCountFormatter.string(fromByteCount: entry.downloadBytes, countStyle: .file))
                .font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
            if ollama.pulling == entry.id { ProgressView(value: ollama.fraction) }
        }
    }
}


/// Third-party work Saywell uses, with the attribution its licence asks for. Names and licence
/// identifiers are not translated.
enum Credits {
    struct Credit { var name: String; var detail: String }
    static let all = [
        Credit(name: "NVIDIA Parakeet TDT 0.6B v3", detail: "© NVIDIA Corporation. Licensed under CC BY 4.0 (creativecommons.org/licenses/by/4.0). MLX conversion: mlx-community/parakeet-tdt-0.6b-v3. Used unmodified; downloaded on request."),
        Credit(name: "parakeet-mlx", detail: "senstella/parakeet-mlx · Apache License 2.0"),
        Credit(name: "OpenAI Whisper (large-v3-turbo, small)", detail: "© OpenAI · MIT License. MLX conversions by mlx-community. Downloaded on request."),
        Credit(name: "mlx-whisper", detail: "ml-explore/mlx-examples · MIT License"),
        Credit(name: "MLX", detail: "© Apple Inc. · MIT License"),
        Credit(name: "NumPy, SciPy, Numba, librosa, soundfile, tiktoken, Hugging Face Hub", detail: "BSD / MIT / Apache 2.0 licences; libsndfile LGPL 2.1 (loaded dynamically). Installed from PyPI with pinned hashes."),
        Credit(name: "uv · Python", detail: "Astral uv (MIT / Apache 2.0); CPython via python-build-standalone (PSF License)."),
        Credit(name: "FLEURS (evaluation only)", detail: "Google · CC BY 4.0. Used to measure accuracy; not shipped."),
        Credit(name: "Ollama models (optional)", detail: "Gemma: Gemma Terms of Use (Google). Qwen3: see its model card. Downloaded by Ollama only when you choose one."),
    ]
}
