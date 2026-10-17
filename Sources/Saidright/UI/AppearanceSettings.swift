import SaidrightCore
import SwiftUI

/// Window theme, capsule look and motion, sounds and icon — presets first, details under Advanced.
struct AppearanceSettings: View {
    @Environment(AppModel.self) private var model
    @State private var preview = CapsuleModel()
    @State private var previewState: CapsuleModel.Display = .recording
    @State private var showAdvanced = false
    @State private var levelTask: Task<Void, Never>?

    static let customColors: [(String, UInt32)] = [("blue", 0x4F9DFF), ("pink", 0xFF4FA3), ("teal", 0x2FD3C1), ("violet", 0xA58BFF), ("amber", 0xFFB23F), ("lime", 0xB8F04A), ("white", 0xE9EEF7)]

    var body: some View {
        @Bindable var model = model
        SettingsGroup(title: tr("capsule.preview")) {
            CapsuleStage(preview: preview, theme: model.settings.theme, tall: previewState == .hint)
            Picker(tr("capsule.preview"), selection: $previewState) {
                Text(tr("capsule.stateRecording")).tag(CapsuleModel.Display.recording)
                Text(tr("capsule.stateProcessing")).tag(CapsuleModel.Display.processing)
                Text(tr("capsule.stateDone")).tag(CapsuleModel.Display.done)
                Text(tr("capsule.stateHint")).tag(CapsuleModel.Display.hint)
                Text(tr("capsule.stateError")).tag(CapsuleModel.Display.error)
            }
            .labelsHidden().pickerStyle(.segmented)
            .accessibilityLabel(tr("capsule.preview"))
        }

        SettingsGroup(title: tr("look.windows")) {
            SettingRow(title: tr("look.theme"), detail: tr("look.themeDetail")) {
                Picker(tr("look.theme"), selection: $model.settings.theme) {
                    ForEach(ThemePreference.allCases, id: \.self) { Text(tr("theme.\($0.rawValue)")).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).fixedSize()
            }
        }

        SettingsGroup(title: tr("look.capsule")) {
            SettingRow(title: tr("look.style"), detail: tr("look.styleDetail")) {
                Picker(tr("look.style"), selection: $model.settings.capsule.style) {
                    ForEach(CapsuleStyle.allCases, id: \.self) { Text(tr("style.\($0.rawValue)")).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            SettingRow(title: tr("look.palette")) {
                PaletteChooser(selection: $model.settings.capsule.palette)
            }
            SettingRow(title: tr("look.size")) {
                Picker(tr("look.size"), selection: $model.settings.capsule.size) {
                    ForEach(CapsuleSize.allCases, id: \.self) { Text(tr("size.\($0.rawValue)")).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            SettingRow(title: tr("capsule.position")) {
                Picker(tr("capsule.position"), selection: $model.settings.capsule.placement) {
                    Text(tr("capsule.bottom")).tag(CapsulePlacement.bottom)
                    Text(tr("capsule.top")).tag(CapsulePlacement.top)
                }.labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            SettingRow(title: tr("look.motion"), detail: tr("look.motionDetail")) {
                Picker(tr("look.motion"), selection: $model.settings.capsule.motion) {
                    ForEach(MotionPreference.allCases, id: \.self) { Text(tr("motion.\($0.rawValue)")).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            SettingRow(title: tr("look.sounds"), detail: tr("look.soundsDetail")) {
                Toggle(tr("look.sounds"), isOn: $model.settings.playSounds).labelsHidden().toggleStyle(.switch)
            }
            DisclosureGroup(tr("look.advanced"), isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    SettingRow(title: tr("capsule.show"), detail: tr("look.showDetail")) { Toggle(tr("capsule.show"), isOn: $model.settings.capsule.enabled).labelsHidden().toggleStyle(.switch) }
                    SettingRow(title: tr("capsule.modeBadge")) { Toggle(tr("capsule.modeBadge"), isOn: $model.settings.capsule.showModeBadge).labelsHidden().toggleStyle(.switch) }
                    colorRow(tr("capsule.recordingColor"), $model.settings.capsule.recordingColor)
                    colorRow(tr("capsule.processingColor"), $model.settings.capsule.processingColor)
                    SettingRow(title: tr("capsule.glow")) {
                        Slider(value: $model.settings.capsule.glow, in: 0...1).frame(width: 180).accessibilityLabel(tr("capsule.glow"))
                    }
                }
                .padding(.top, DS.Space.s)
            }
            .font(DS.Font.body)
        }

        SettingsGroup(title: tr("look.icon"), footer: tr("look.iconFooter")) {
            HStack(alignment: .top, spacing: DS.Space.l) {
                ForEach(AppIconVariant.allCases, id: \.self) { variant in
                    IconChoice(variant: variant, selected: model.settings.appIcon == variant) { model.settings.appIcon = variant }
                }
            }
            IconSizes(variant: model.settings.appIcon)
        }

        HStack {
            Spacer()
            Button(tr("settings.resetSection")) {
                model.settings.capsule = CapsuleSettings()
                model.settings.theme = .system
                model.settings.appIcon = .standard
                model.settings.playSounds = false
            }.buttonStyle(PillButtonStyle())
        }
        .onAppear { sync() }
        .onDisappear { levelTask?.cancel() }
        .onChange(of: model.settings.capsule) { sync() }
        .onChange(of: previewState) { sync() }
    }

    private func sync() {
        preview.previewing = true
        preview.apply(model.settings.capsule)
        preview.enabled = true
        if previewState == .hint { preview.previewHint() } else { preview.show(previewState) }
        levelTask?.cancel()
        guard previewState == .recording else { return }
        levelTask = Task { @MainActor in
            var i = 0
            while !Task.isCancelled {
                preview.push(level: Float(0.35 + 0.35 * sin(Double(i) / 2.3) * sin(Double(i) / 7)))
                i += 1
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    private func colorRow(_ title: String, _ value: Binding<UInt32>) -> some View {
        SettingRow(title: title, detail: model.settings.capsule.palette == .custom ? nil : tr("look.customHint")) {
            HStack(spacing: 8) {
                ForEach(Self.customColors, id: \.1) { name, hex in
                    Button {
                        value.wrappedValue = hex
                        model.settings.capsule.palette = .custom
                    } label: {
                        Circle().fill(Color(hex: hex)).frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.primary.opacity(value.wrappedValue == hex && model.settings.capsule.palette == .custom ? 0.9 : 0), lineWidth: 2).padding(-3))
                    }
                    .buttonStyle(.plain)
                    .help(tr("color.\(name)"))
                    .accessibilityLabel(tr("color.\(name)"))
                    .accessibilityAddTraits(value.wrappedValue == hex ? .isSelected : [])
                }
            }
        }
    }
}

/// The capsule on a small desktop-like backdrop that follows the chosen window theme.
struct CapsuleStage: View {
    let preview: CapsuleModel
    var theme: ThemePreference
    var tall = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = theme == .dark || (theme == .system && scheme == .dark)
        ZStack(alignment: .bottom) {
            LinearGradient(colors: dark ? [Color(hex: 0x1B2338), Color(hex: 0x3A3550)] : [Color(hex: 0xD9E4F2), Color(hex: 0xF3E9DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
            // A stand-in text field, so the capsule is judged against something you type into.
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(.primary.opacity(0.12)).frame(width: 180, height: 7)
                RoundedRectangle(cornerRadius: 3).fill(.primary.opacity(0.08)).frame(width: 240, height: 7)
                RoundedRectangle(cornerRadius: 3).fill(.primary.opacity(0.08)).frame(width: 130, height: 7)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            CapsuleView(model: preview)
        }
        .environment(\.colorScheme, dark ? .dark : .light)
        .frame(height: tall ? 290 : 150)
        .animation(DS.Motion.standard, value: tall)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control).stroke(DS.Palette.hairline.opacity(0.6), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("capsule.preview"))
    }
}

struct PaletteChooser: View {
    @Binding var selection: CapsulePalette

    var body: some View {
        HStack(spacing: 10) {
            ForEach(CapsulePalette.allCases.filter { $0 != .custom }, id: \.self) { palette in
                let c = palette.colors!
                Button { selection = palette } label: {
                    HStack(spacing: 2) {
                        Circle().fill(Color(hex: c.recording)).frame(width: 10, height: 10)
                        Circle().fill(Color(hex: c.processing)).frame(width: 10, height: 10)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 5)
                    .background(Capsule().fill(Color(white: 0.08)))
                    .overlay(Capsule().stroke(Color.accentColor, lineWidth: selection == palette ? 2 : 0).padding(-2))
                }
                .buttonStyle(.plain)
                .help(tr("palette.\(palette.rawValue)"))
                .accessibilityLabel(tr("palette.\(palette.rawValue)"))
                .accessibilityAddTraits(selection == palette ? .isSelected : [])
            }
            if selection == .custom { Text(tr("palette.custom")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText) }
        }
    }
}

struct IconChoice: View {
    var variant: AppIconVariant
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                AppIconArt(variant: variant).frame(width: 72, height: 72)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 16).stroke(Color.accentColor, lineWidth: selected ? 2 : 0))
                Text(tr("icon.\(variant.rawValue)")).font(DS.Font.caption)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("icon.\(variant.rawValue)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The chosen icon at real Dock/Finder sizes, on light and dark, plus the menu bar glyph.
struct IconSizes: View {
    var variant: AppIconVariant

    var body: some View {
        HStack(spacing: DS.Space.m) {
            ForEach([false, true], id: \.self) { dark in
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach([64, 32, 16] as [CGFloat], id: \.self) { size in
                        AppIconArt(variant: variant).frame(width: size, height: size)
                    }
                    Image(nsImage: MenuBarIcon.image(recording: false)).renderingMode(.template).foregroundStyle(dark ? .white : .black)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: DS.Radius.small).fill(dark ? Color(white: 0.12) : Color(white: 0.96)))
            }
        }
        .accessibilityHidden(true)
    }
}
