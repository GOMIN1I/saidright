import AppKit
import SaidrightCore
import SwiftUI

/// Short, skippable, resumable first run:
/// interface language → spoken languages → learning (optional) → recognizer → permissions → try it → modes.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.brandTint) private var brand
    @State private var step = 0
    /// Direction of the last step change, for the slide.
    @State private var forward = true
    @State private var appeared = false
    @State private var spoken: [String] = AppModel.defaultSpokenLanguages()
    @State private var learning = false
    @State private var learningLanguage = "en"
    @State private var explanationLanguage: String?
    @State private var installer = RuntimeInstaller()
    private let steps = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                if step == 0 {
                    OnboardingHero()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                }
                HStack {
                    ProgressDots(count: steps, current: step, onDark: step == 0 && brand)
                    Spacer()
                    Button(tr("onb.skip")) { finish() }.buttonStyle(.plain).font(DS.Font.caption)
                        .foregroundStyle(step == 0 && brand ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(DS.Palette.secondaryText))
                }
                // Clear of the window buttons, which sit over the hero.
                .padding(.horizontal, DS.Space.xl).padding(.top, DS.Space.l + 22)
            }
            .frame(height: step == 0 ? 200 : nil, alignment: .top)
            // The header runs up under the hidden title bar; the rest keeps the window's size.
            .ignoresSafeArea(edges: .top)
            ScrollView {
                Group {
                    switch step {
                    case 0: welcome
                    case 1: languages
                    case 2: learningStep
                    case 3: recognizer
                    case 4: permissions
                    case 5: tryIt
                    default: modesStep
                    }
                }
                .id(step)
                .transition(stepTransition)
                .padding(DS.Space.xl)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            HStack {
                if step > 0 { Button(tr("onb.back")) { go(step - 1) }.buttonStyle(PillButtonStyle()) }
                Spacer()
                if step == 2 && !learning { Button(tr("onb.learn.skip")) { next() }.buttonStyle(PillButtonStyle()) }
                Button(step == steps - 1 ? tr("onb.finish") : tr("onb.next")) { next() }
                    .buttonStyle(PillButtonStyle(prominent: true, warm: step == steps - 1))
                    .keyboardShortcut(.defaultAction)
                    .disabled(step == 1 && spoken.isEmpty)
            }
            .padding(DS.Space.l)
        }
        .frame(width: 580, height: 600)
        // Entrance: the card settles in while the window fades up (Reduce Motion: fade only).
        .scaleEffect(appeared || reduceMotion ? 1 : 0.965)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            WindowRouter.openWindow = openWindow
            // macOS may restore this window at launch; only keep it when it was asked for.
            if model.settings.onboardingCompleted, !WindowRouter.onboardingRequested {
                DispatchQueue.main.async {
                    NSApp.windows.filter { $0.identifier?.rawValue.hasPrefix("onboarding") == true }.forEach { $0.close() }
                }
                return
            }
            WindowFX.present("onboarding")
            withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.6, dampingFraction: 0.86).delay(0.08)) { appeared = true }
            // Resume where the person left off; a replay starts from the beginning.
            if !model.settings.onboardingCompleted { step = min(model.settings.onboardingStep, steps - 1) }
            if let qa = WindowRouter.qaOnboardingStep { step = qa }
            if let prompt = model.modes.modes.first(where: { $0.presetID == ModePresets.promptID }) {
                if !prompt.spokenLanguages.isEmpty { spoken = prompt.spokenLanguages }
                learning = prompt.learning != .off
                learningLanguage = prompt.learningLanguage
            }
            explanationLanguage = model.settings.explanationLanguage
        }
    }

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .offset(x: forward ? 36 : -36).combined(with: .opacity),
            removal: .offset(x: forward ? -24 : 24).combined(with: .opacity)
        )
    }

    private func go(_ target: Int) {
        forward = target > step
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.9)) { step = target }
        if !model.settings.onboardingCompleted, WindowRouter.qaOnboardingStep == nil { model.settings.onboardingStep = target }
    }

    private func next() {
        if step == 1 || step == 2 { applyLanguages() }
        if step < steps - 1 { go(step + 1) } else { finish() }
    }

    /// The introduction dissolves and the main window fades in where the person can start.
    private func finish() {
        model.settings.onboardingCompleted = true
        model.settings.onboardingStep = 0
        withAnimation(.easeIn(duration: 0.25)) { appeared = false }
        WindowFX.dismiss("onboarding") {
            dismissWindow(id: "onboarding")
            WindowFX.reveal("main")
        }
    }

    private func applyLanguages() {
        for var mode in model.modes.modes where mode.presetID != ModePresets.practiceID {
            mode.spokenLanguages = spoken
            if mode.presetID == ModePresets.promptID { mode.learning = learning ? .hint : .off; mode.learningLanguage = learningLanguage }
            model.modes.update(mode)
        }
        if var practice = model.modes.modes.first(where: { $0.presetID == ModePresets.practiceID }) {
            practice.spokenLanguages = [learningLanguage]
            practice.learningLanguage = learningLanguage
            model.modes.update(practice)
        }
        model.settings.explanationLanguage = explanationLanguage
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            Text(tr("onb.welcome.title")).font(.system(size: 26, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            Text(tr("onb.welcome.body")).font(DS.Font.reading).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text(tr("settings.interfaceLanguage")).font(DS.Font.body.weight(.semibold))
                @Bindable var model = model
                Picker(tr("settings.interfaceLanguage"), selection: $model.settings.uiLanguage) {
                    Text(tr("settings.systemLanguage")).tag(UILanguage.system)
                    ForEach(UILanguage.translated) { Text($0.nativeName).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).fixedSize()
                Text(tr("onb.uiLanguageNote")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Label(tr("onb.welcome.local"), systemImage: "lock").fixedSize(horizontal: false, vertical: true)
                Label(tr("onb.welcome.optional"), systemImage: "network").fixedSize(horizontal: false, vertical: true)
                Label(tr("onb.welcome.cost"), systemImage: "creditcard").fixedSize(horizontal: false, vertical: true)
            }
            .font(DS.Font.body)
            .foregroundStyle(DS.Palette.secondaryText)
        }
    }

    private var languages: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            Text(tr("onb.lang.title")).font(DS.Font.headline)
            Text(tr("onb.lang.body")).font(DS.Font.body).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
            FlowChips(items: LanguageCatalog.all.prefix(12).map { ($0.id, $0.nativeName) }, selection: $spoken)
            Text(spoken.count > 1 ? tr("onb.lang.mixed") : tr("onb.lang.single")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var learningStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            Text(tr("onb.learn.title")).font(DS.Font.headline)
            Text(tr("onb.learn.body")).font(DS.Font.body).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
            Toggle(tr("onb.lang.learning"), isOn: $learning).toggleStyle(.switch)
            if learning {
                Grid(alignment: .leading, horizontalSpacing: DS.Space.l, verticalSpacing: DS.Space.m) {
                    GridRow {
                        Text(tr("modes.learningLanguage"))
                        Picker(tr("modes.learningLanguage"), selection: $learningLanguage) { ForEach(LanguageCatalog.all) { Text($0.nativeName).tag($0.id) } }.labelsHidden().fixedSize()
                    }
                    GridRow {
                        Text(tr("modes.explanationLanguage"))
                        Picker(tr("modes.explanationLanguage"), selection: $explanationLanguage) {
                            Text(tr("modes.sameAsInterface")).tag(String?.none)
                            ForEach(LanguageCatalog.all) { Text($0.nativeName).tag(Optional($0.id)) }
                        }.labelsHidden().fixedSize()
                    }
                    GridRow {
                        Text(tr("learn.level"))
                        @Bindable var model = model
                        Picker(tr("learn.level"), selection: $model.settings.learningUI.level) {
                            ForEach(LearnerLevel.allCases, id: \.self) { Text(tr("level.\($0.rawValue)")).tag($0) }
                        }.labelsHidden().pickerStyle(.segmented).fixedSize()
                    }
                }
                .font(DS.Font.body)
                Text(tr("onb.lang.learningNote")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
                Text(tr("onb.learn.provider")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var recognizer: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            Text(tr("onb.asr.title")).font(DS.Font.headline)
            if model.whisperInstallation != nil {
                // Assets shared with another app are described as found, never as installed by Saidright.
                Label(model.whisperInstallation?.isLegacy == true ? tr("onb.asr.foundShared") : tr("onb.asr.ready"), systemImage: "checkmark.circle.fill").foregroundStyle(DS.Palette.success).fixedSize(horizontal: false, vertical: true)
                Text(tr("engine.whisperFacts")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
                if model.whisperInstallation?.isLegacy == true {
                    Text(tr("onb.asr.sharedNote")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(tr("onb.asr.recommend")).font(DS.Font.body).fixedSize(horizontal: false, vertical: true)
                Text(tr("install.sizeNote", ByteCountFormatter.string(fromByteCount: RuntimeInstaller.runtimeBytes + RuntimeInstaller.modelBytes, countStyle: .file), ByteCountFormatter.string(fromByteCount: RuntimeInstaller.freeSpace(), countStyle: .file)))
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText)
                Text(tr("onb.asr.network")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
                if installer.isRunning {
                    ProgressView(value: { if case .downloadingModel(let f) = installer.stage { return f } else { return nil } }())
                    Button(tr("common.cancel")) { installer.cancel() }.buttonStyle(PillButtonStyle())
                } else {
                    Button(tr("install.button")) { installer.install(model: model) }.buttonStyle(PillButtonStyle(prominent: true))
                    if case .failed(let m) = installer.stage {
                        Text(m).font(DS.Font.caption).foregroundStyle(DS.Palette.warning)
                        Button(tr("install.retry")) { installer.install(model: model) }.buttonStyle(PillButtonStyle())
                    }
                }
                if AppleDictation.isAvailable {
                    Divider()
                    Text(tr("onb.asr.appleAlternative")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(tr("onb.asr.more")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissions: some View {
        let p = model.permissions
        return VStack(alignment: .leading, spacing: DS.Space.m) {
            Text(tr("onb.perm.title")).font(DS.Font.headline)
            Text(tr("onb.perm.body")).font(DS.Font.body).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
            PermissionRow(title: tr("perm.mic"), detail: tr("perm.micDetail"), granted: p.microphone == .granted) {
                if p.microphone == .notDetermined { Task { _ = await p.requestMicrophone() } } else { p.openSettings(.microphone) }
            }
            PermissionRow(title: tr("perm.listen"), detail: tr("perm.listenDetail"), granted: p.listenEvents) { p.requestListen() }
            PermissionRow(title: tr("perm.ax"), detail: tr("perm.axDetail"), granted: p.accessibility) { p.requestAccessibility() }
            Text(tr("onb.perm.limited")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            Text(tr("onb.try.title")).font(DS.Font.headline)
            Text(tr("onb.try.body", shortcutText(model.settings.hotkeys, switching: false))).font(DS.Font.body).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.l) {
                RecordButton()
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.statusLine).font(DS.Font.body)
                    if model.keyTestPassed { Label(tr("keytest.passed"), systemImage: "checkmark.circle.fill").font(DS.Font.caption).foregroundStyle(DS.Palette.success) }
                }
            }
            if let r = model.result {
                Text(r.output).font(DS.Font.reading).textSelection(.enabled).padding(DS.Space.m).frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Palette.readingSurface, in: RoundedRectangle(cornerRadius: DS.Radius.control))
            }
            Text(tr("onb.try.elsewhere")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
            if learning {
                Divider()
                HStack {
                    Text(tr("onb.try.hint")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(tr("learn.tryHint")) { model.capsule.previewing = false; model.capsule.previewHint() }.buttonStyle(PillButtonStyle())
                }
            }
        }
        .onAppear { model.startKeyTest() }
    }

    private var modesStep: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            Text(tr("onb.modes.title")).font(DS.Font.headline)
            Text(tr("onb.modes.body", ShortcutFormatter.combo(code: model.settings.hotkeys.switchKeyCode, modifiers: model.settings.hotkeys.switchModifiers))).font(DS.Font.body).fixedSize(horizontal: false, vertical: true)
            ForEach(model.modes.modes) { mode in
                HStack(alignment: .top, spacing: DS.Space.m) {
                    Image(systemName: mode.symbol).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.name).font(DS.Font.body.weight(.semibold))
                        ModeSummary(mode: mode)
                    }
                }
            }
        }
    }
}

struct ProgressDots: View {
    var count: Int
    var current: Int
    var onDark = false
    @Environment(\.brandTint) private var brand
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? (onDark ? AnyShapeStyle(Color.white) : brand ? AnyShapeStyle(DS.Brand.warm) : AnyShapeStyle(Surface.accent(brand))) : AnyShapeStyle(onDark ? Color.white.opacity(0.28) : Color.primary.opacity(0.16)))
                    .frame(width: i == current ? 18 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("onb.stepOf", current + 1, count))
    }
}

/// Toggleable chips in a wrapping layout.
struct FlowChips: View {
    var items: [(String, String)]
    @Binding var selection: [String]

    var body: some View {
        WrapLayout(spacing: 6) {
            ForEach(items, id: \.0) { id, name in
                let on = selection.contains(id)
                Button {
                    if let i = selection.firstIndex(of: id) { selection.remove(at: i) } else { selection.append(id) }
                } label: {
                    HStack(spacing: 4) {
                        if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                        Text(name)
                    }
                }
                .buttonStyle(PillButtonStyle(prominent: on))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    /// Items wider than the row (a long correction) wrap inside themselves instead of overflowing.
    private func size(_ s: LayoutSubview, width: CGFloat) -> CGSize {
        let ideal = s.sizeThatFits(.unspecified)
        return ideal.width > width ? s.sizeThatFits(ProposedViewSize(width: width, height: nil)) : ideal
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 500
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let size = size(s, width: width)
            if x + size.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = size(s, width: bounds.width)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

/// The first thing a new person sees: the icon's indigo, the mark floating in it, and two soft
/// lights (voice blue and the cursor's coral) drifting slowly behind it. Still with Reduce Motion.
struct OnboardingHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.brandTint) private var brand

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                if brand { DS.Brand.tile } else { LinearGradient(colors: [Color(white: 0.24), Color(white: 0.1)], startPoint: .top, endPoint: .bottom) }
                RadialGradient(colors: [DS.Brand.voice.opacity(0.55), .clear], center: UnitPoint(x: 0.3 + 0.12 * sin(t * 0.35), y: 0.65 + 0.1 * cos(t * 0.27)), startRadius: 0, endRadius: 260)
                    .blendMode(.screen)
                RadialGradient(colors: [DS.Brand.rose.opacity(0.34), .clear], center: UnitPoint(x: 0.78 + 0.08 * cos(t * 0.31), y: 0.3 + 0.1 * sin(t * 0.23)), startRadius: 0, endRadius: 200)
                    .blendMode(.screen)
                AppIconArt.Glyph(variant: .standard, size: 150)
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
                    .scaleEffect(1 + 0.012 * sin(t * 1.1))
                    .offset(y: 14 + 3 * sin(t * 0.8))
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

/// Window entrances and exits that SwiftUI scenes do not animate on their own.
@MainActor enum WindowFX {
    static func window(_ id: String) -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(id) == true }
    }

    /// Centres the window and fades it up.
    static func present(_ id: String) {
        DispatchQueue.main.async {
            guard let window = window(id) else { return }
            window.center()
            window.alphaValue = 0
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.45
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }
        }
    }

    /// Fades the window out, then runs `completion`.
    static func dismiss(_ id: String, completion: @escaping @MainActor () -> Void) {
        guard let window = window(id) else { completion(); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { completion() }
        }
    }

    /// Opens (or brings forward) a window and fades it in.
    static func reveal(_ id: String) {
        WindowRouter.show(id)
        DispatchQueue.main.async {
            guard let window = window(id) else { return }
            window.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }
        }
    }
}
