import SaywellCore
import SwiftUI

/// One searchable setting. `anchor` is the localized row or group title, which is also the
/// scroll identifier that `SettingRow` and `SettingsGroup` attach to themselves.
struct SettingsEntry: Identifiable, Hashable {
    var section: SettingsSection
    var title: String
    var detail: String
    /// Extra words people might type, in the interface language and in English.
    var synonyms: String
    var id: String { section.rawValue + "|" + title }
    var anchor: String { title }
}

enum SettingsIndex {
    /// Built on demand so it always follows the current interface language.
    static var entries: [SettingsEntry] {
        func e(_ section: SettingsSection, _ title: String, _ detail: String = "", syn: String? = nil) -> SettingsEntry {
            var words = ""
            if let syn {
                words = Localizer.shared.string(syn)
                if let english = Localizer.shared.table(.en)[syn], english != words { words += " " + english }
                if words == syn { words = "" }
            }
            return SettingsEntry(section: section, title: title, detail: detail, synonyms: words)
        }
        return [
            e(.general, tr("settings.language"), tr("settings.interfaceLanguageFooter"), syn: "syn.uiLanguage"),
            e(.general, tr("settings.permissions"), tr("perm.footer"), syn: "syn.permissions"),
            e(.general, tr("perm.listen"), tr("perm.listenDetail"), syn: "syn.permissions"),
            e(.general, tr("perm.ax"), tr("perm.axDetail"), syn: "syn.permissions"),
            e(.general, tr("keytest.title"), tr("keytest.prompt"), syn: "syn.keytest"),
            e(.general, tr("settings.inputDevice"), syn: "syn.microphone"),
            e(.general, tr("settings.replayOnboarding"), tr("settings.replayOnboardingDetail"), syn: "syn.onboarding"),

            e(.modes, tr("modes.list"), tr("modes.listFooter"), syn: "syn.modes"),
            e(.modes, tr("modes.spoken"), tr("modes.spokenMany"), syn: "syn.spoken"),
            e(.modes, tr("modes.recognizer"), tr("modes.whisperDetail")),
            e(.modes, tr("modes.cleanup"), tr("cleanup.light.detail"), syn: "syn.cleanup"),
            e(.modes, tr("modes.learning"), tr("learning.hint.detail"), syn: "syn.learning"),
            e(.modes, tr("modes.learningLanguage")),
            e(.modes, tr("modes.output"), tr("output.insert.detail"), syn: "syn.output"),

            e(.shortcuts, tr("shortcut.singleKey"), tr("shortcut.singleKeyDetail"), syn: "syn.hotkey"),
            e(.shortcuts, tr("shortcut.combo"), tr("shortcut.comboDetail"), syn: "syn.hotkey"),
            e(.shortcuts, tr("shortcut.behavior"), tr("shortcut.holdDetail"), syn: "syn.hold"),
            e(.shortcuts, tr("shortcut.switch"), tr("shortcut.switchFooter"), syn: "syn.modes"),
            e(.shortcuts, tr("shortcut.lastTip"), tr("shortcut.lastTipDetail"), syn: "syn.hints"),
            e(.shortcuts, tr("shortcut.cancel"), tr("shortcut.cancelDetail")),

            e(.recognition, tr("models.speech"), tr("models.speechFooter"), syn: "syn.models"),
            e(.recognition, tr("engine.apple"), tr("engine.appleFooter"), syn: "syn.models"),
            e(.recognition, tr("engine.matrix"), tr("matrix.legend")),
            e(.recognition, tr("engine.vocabulary"), tr("engine.vocabularyFooter"), syn: "syn.vocabulary"),

            e(.text, tr("text.localOnlyToggle"), tr("text.localOnlyDetail"), syn: "syn.privacy"),
            e(.text, tr("text.service"), tr("text.costFooter"), syn: "syn.provider"),
            e(.text, tr("text.key"), tr("text.keyMissing"), syn: "syn.key"),
            e(.text, tr("text.model"), tr("text.modelDetail"), syn: "syn.models"),

            e(.learning, tr("learn.presentation"), tr("learn.presentationDetail"), syn: "syn.hints"),
            e(.learning, tr("learn.linger"), tr("learn.lingerDetail"), syn: "syn.hints"),
            e(.learning, tr("learn.depth"), tr("learn.depthDetail"), syn: "syn.explanations"),
            e(.learning, tr("learn.level"), tr("learn.levelDetail"), syn: "syn.explanations"),
            e(.learning, tr("modes.explanationLanguage"), tr("learn.explanationsFooter"), syn: "syn.explanations"),
            e(.learning, tr("learn.goal"), tr("learn.goalDetail")),
            e(.learning, tr("learn.voice"), tr("learn.voiceFooter"), syn: "syn.voice"),
            e(.learning, tr("learn.progress"), tr("learn.progressFooter")),

            e(.appearance, tr("look.theme"), tr("look.themeDetail"), syn: "syn.theme"),
            e(.appearance, tr("look.style"), tr("look.styleDetail"), syn: "syn.glass"),
            e(.appearance, tr("look.palette"), syn: "syn.colors"),
            e(.appearance, tr("look.size"), syn: "syn.size"),
            e(.appearance, tr("capsule.position"), syn: "syn.position"),
            e(.appearance, tr("look.motion"), tr("look.motionDetail"), syn: "syn.motion"),
            e(.appearance, tr("look.sounds"), tr("look.soundsDetail"), syn: "syn.sounds"),
            e(.appearance, tr("look.icon"), tr("look.iconFooter"), syn: "syn.icon"),
            e(.appearance, tr("capsule.show"), tr("look.showDetail")),
            e(.appearance, tr("capsule.modeBadge")),
            e(.appearance, tr("capsule.recordingColor"), syn: "syn.colors"),
            e(.appearance, tr("capsule.glow")),

            e(.privacy, tr("privacy.routes"), syn: "syn.privacy"),
            e(.privacy, tr("privacy.keepText"), tr("privacy.retentionFooter"), syn: "syn.history"),
            e(.privacy, tr("privacy.keepAudio"), tr("privacy.keepAudioDetail"), syn: "syn.history"),
            e(.privacy, tr("privacy.export"), tr("privacy.exportDetail"), syn: "syn.history"),
            e(.privacy, tr("privacy.deleteAll"), tr("privacy.deleteAllDetail"), syn: "syn.history"),

            e(.advanced, tr("adv.restoreClipboard"), tr("adv.restoreClipboardDetail"), syn: "syn.clipboard"),
            e(.advanced, tr("adv.automationToggle"), tr("adv.automationFooter"), syn: "syn.automation"),
            e(.advanced, tr("adv.diagnostics"), tr("adv.diagnosticsFooter"), syn: "syn.diagnostics"),
            e(.advanced, tr("adv.credits"), tr("adv.creditsFooter"), syn: "syn.credits"),
        ]
    }

    static func search(_ query: String) -> [SettingsEntry] {
        let scored: [(SettingsEntry, Int)] = entries.compactMap { entry in
            let fields = [
                SearchMatcher.Field(entry.title, weight: 4),
                SearchMatcher.Field(entry.synonyms, weight: 3),
                SearchMatcher.Field(tr("settings.\(entry.section.rawValue)"), weight: 2),
                SearchMatcher.Field(entry.detail, weight: 1),
            ]
            return SearchMatcher.score(query: query, fields: fields).map { (entry, $0) }
        }
        var seen = Set<String>()
        return scored.sorted { $0.1 > $1.1 }.map(\.0).filter { seen.insert($0.id).inserted }
    }
}

// MARK: - Reveal and highlight

private struct SettingsHighlightKey: EnvironmentKey { static let defaultValue: String? = nil }

extension EnvironmentValues {
    /// Anchor of the setting a search result just revealed; it is tinted briefly.
    var settingsHighlight: String? {
        get { self[SettingsHighlightKey.self] }
        set { self[SettingsHighlightKey.self] = newValue }
    }
}

/// Makes a view a scroll target for search and tints it while it is the revealed result.
struct SettingAnchor: ViewModifier {
    var anchor: String
    @Environment(\.settingsHighlight) private var highlight

    func body(content: Content) -> some View {
        let on = highlight == anchor
        content
            .id(anchor)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.small)
                    .fill(Color.accentColor.opacity(on ? 0.16 : 0))
                    .padding(-6)
            }
            .animation(.easeOut(duration: 0.35), value: on)
    }
}

extension View {
    func settingAnchor(_ anchor: String) -> some View { modifier(SettingAnchor(anchor: anchor)) }
}

/// Sidebar list of search results, grouped by section, with an empty state.
struct SettingsSearchResults: View {
    var results: [SettingsEntry]
    var query: String
    @Binding var selection: SettingsEntry.ID?

    var body: some View {
        if results.isEmpty {
            ContentUnavailableView {
                Label(tr("search.noResults"), systemImage: "magnifyingglass")
            } description: {
                Text(tr("search.noResultsDetail", query))
            }
        } else {
            List(selection: $selection) {
                ForEach(SettingsSection.allCases.filter { s in results.contains { $0.section == s } }) { section in
                    Section(tr("settings.\(section.rawValue)")) {
                        ForEach(results.filter { $0.section == section }) { entry in
                            Label {
                                Text(entry.title).lineLimit(2)
                            } icon: {
                                Image(systemName: section.symbol)
                            }
                            .tag(entry.id)
                        }
                    }
                }
            }
        }
    }
}
