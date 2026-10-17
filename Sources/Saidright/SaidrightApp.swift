import AppKit
import SaidrightCore
import SwiftUI

/// Remembers SwiftUI's window-opening action so AppKit code (hotkeys, menu bar, dock) can
/// bring windows forward even after they were closed.
@MainActor enum WindowRouter {
    static var openWindow: OpenWindowAction?
    /// Set when the introduction is opened on purpose; restored copies close themselves.
    static var onboardingRequested = false
    /// QA only: step to show when the introduction opens.
    static var qaOnboardingStep: Int? = {
        guard let qa = ProcessInfo.processInfo.environment["SAIDRIGHT_QA_OPEN"], qa.hasPrefix("onboarding:") else { return nil }
        return Int(qa.dropFirst("onboarding:".count))
    }()

    static func show(_ id: String) {
        if id == "onboarding" { onboardingRequested = true }
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == id && $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow?(id: id)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var model: AppModel?
    nonisolated(unsafe) static var qaActivity: NSObjectProtocol?

    /// saidright://toggle, start, stop, cancel, next-mode, mode?name=… — only when enabled in Advanced.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            guard let model = Self.model else { return }
            for url in urls { model.handleAutomation(url) }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Screenshot/QA hook: SAIDRIGHT_APPEARANCE=light|dark overrides the system appearance for this process only.
        switch ProcessInfo.processInfo.environment["SAIDRIGHT_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        // QA hook for screenshots: SAIDRIGHT_QA_OPEN=settings:<section> | search:<query> | onboarding:<step> | hint | hint-expanded.
        // Opens windows only; it never changes stored settings.
        if let qa = ProcessInfo.processInfo.environment["SAIDRIGHT_QA_OPEN"] {
            // QA timings must not be stretched by App Nap while the instance runs in the background.
            Self.qaActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "QA run")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { MainActor.assumeIsolated { Self.qaOpen(qa) } }
        }
        // QA: SAIDRIGHT_QA_SNAPSHOT=<dir> writes PNGs of Saidright's own visible windows, then quits.
        if let dir = ProcessInfo.processInfo.environment["SAIDRIGHT_QA_SNAPSHOT"] {
            let delay = ProcessInfo.processInfo.environment["SAIDRIGHT_QA_SNAPSHOT_DELAY"].flatMap(Double.init) ?? 3.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { Self.qaSnapshot(to: dir) } }
        }
    }

    /// QA: captures the capsule panel every 40 ms (contents as AppKit last drew them).
    @MainActor static func qaFrames(to dir: String, seconds: Double) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var frame = 0
        let start = Date()
        Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { timer in
            MainActor.assumeIsolated {
                guard Date().timeIntervalSince(start) < seconds else { timer.invalidate(); return }
                if let panel = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible }), let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    let t = Int(Date().timeIntervalSince(start) * 1000)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "f%03d-%04dms-%.0fx%.0f.png", frame, t, panel.frame.width, panel.frame.height)))
                }
                frame += 1
            }
        }
    }

    @MainActor static func qaSnapshot(to dir: String) {
        if let model { Log.info("qa snapshot: capsule \(model.capsule.display) folding=\(model.capsule.folding)") }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (i, window) in NSApp.windows.enumerated() where window.isVisible && window.frame.width > 60 {
            guard let view = window.contentView?.superview ?? window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let name = (window.identifier?.rawValue ?? "window").replacingOccurrences(of: "/", with: "-")
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(i)-\(name).png"))
        }
        NSApp.terminate(nil)
    }

    @MainActor static func qaOpen(_ command: String) {
        // Several steps: "dictate:3;hide@20;last-tip@22" (seconds after launch).
        if command.contains(";") || command.contains("@") && !command.hasPrefix("dictate") {
            for step in command.split(separator: ";").map(String.init) {
                let bits = step.split(separator: "@").map(String.init)
                let delay = bits.count > 1 ? Double(bits[1]) ?? 0 : 0
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { qaOpen(bits[0]) } }
            }
            return
        }
        let parts = command.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        switch parts.first {
        case "settings": SettingsRouter.open(SettingsSection(rawValue: arg) ?? .general)
        case "search": SettingsRouter.qaQuery = arg; SettingsRouter.open()
        case "reveal": SettingsRouter.qaQuery = arg; SettingsRouter.qaReveal = true; SettingsRouter.open()
        case "onboarding": WindowRouter.qaOnboardingStep = Int(arg) ?? 0; WindowRouter.show("onboarding")
        case "window": WindowRouter.show(arg) // e.g. "window:practice", "window:history"
        case "dictate":
            // Same path as the hotkey: captures the focused field, records (SAIDRIGHT_TEST_AUDIO), inserts.
            // "3" = one 3 s session; "3@25" = and a second one 25 s later (interrupting a hint).
            guard let model else { return }
            let bits = arg.split(separator: "@").map { Double($0) ?? 0 }
            model.qaDictate(seconds: bits.first ?? 2)
            if bits.count > 1 { DispatchQueue.main.asyncAfter(deadline: .now() + bits[1]) { MainActor.assumeIsolated { model.qaDictate(seconds: bits[0]) } } }
        case "install-whisper":
            // Fresh-install check: the same installer as onboarding, for the model in settings.
            guard let model else { return }
            let installer = RuntimeInstaller()
            installer.install(model: model)
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                MainActor.assumeIsolated {
                    if case .downloadingModel(let f) = installer.stage, let f, Int(f * 100) % 20 == 0 { Log.info("qa install-whisper: model \(Int(f * 100))%") }
                    guard !installer.isRunning else { return }
                    timer.invalidate()
                    Log.info("qa install-whisper: \(installer.stage)")
                }
            }
        case "install-parakeet":
            // Runs the same installer as Settings → Recognition, logs the outcome and quits.
            guard let model else { return }
            let installer = RuntimeInstaller()
            installer.installParakeet(model: model)
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                MainActor.assumeIsolated {
                    guard !installer.isRunning else { return }
                    timer.invalidate()
                    Log.info("qa install-parakeet: \(installer.stage)")
                    NSApp.terminate(nil)
                }
            }
        case "hide": model?.capsule.hide()
        case "last-tip": model?.toggleLastTip()
        case "sample-feedback": model?.qaSampleFeedback()
        case "snapshot": if let dir = ProcessInfo.processInfo.environment["SAIDRIGHT_QA_SNAPSHOT_DIR"] { qaSnapshot(to: dir) }
        case "frames": if let dir = ProcessInfo.processInfo.environment["SAIDRIGHT_QA_FRAMES"] { qaFrames(to: dir, seconds: Double(arg) ?? 3) }
        case "hint-arrive":
            // The real arrival path from nothing, then expand, then close; frames via SAIDRIGHT_QA_FRAMES.
            guard let model else { return }
            model.capsule.offerSampleHint()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { MainActor.assumeIsolated { model.capsule.expandHint() } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { MainActor.assumeIsolated { model.capsule.hide() } }
            if let dir = ProcessInfo.processInfo.environment["SAIDRIGHT_QA_FRAMES"] { qaFrames(to: dir, seconds: 3.6) }
        case "hint", "hint-expanded":
            guard let model else { return }
            model.capsule.previewHint()
            if parts.first == "hint-expanded" { model.capsule.expandHint() }
            model.capsule.pin()
        default: break
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainActor.assumeIsolated { WindowRouter.show("main") } }
        return true
    }

    @objc func showMainWindow() { MainActor.assumeIsolated { WindowRouter.show("main") } }
}

@main struct SaidrightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        // Build-time hook: `Saidright --render-icon <dir.iconset> [standard|light|mono]` writes the icon and exits.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
            let variant = args.count > i + 2 ? AppIconVariant(rawValue: args[i + 2]) ?? .standard : .standard
            do { try IconRenderer.writeIconset(to: URL(fileURLWithPath: args[i + 1]), variant: variant); exit(0) } catch { print(error); exit(1) }
        }
        if let i = args.firstIndex(of: "--render-icon-layers"), i + 1 < args.count {
            do { try IconRenderer.writeIconLayers(to: URL(fileURLWithPath: args[i + 1])); exit(0) } catch { print(error); exit(1) }
        }
        let model = AppModel()
        _model = State(initialValue: model)
        AppDelegate.model = model
    }

    var body: some Scene {
        Window("Saidright", id: "main") {
            MainView()
                .environment(model)
                .environment(\.locale, Localizer.shared.locale)
                .id(model.settings.uiLanguage)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands { AppCommands(model: model) }

        Window(tr("window.history"), id: "history") {
            HistoryView().environment(model).id(model.settings.uiLanguage)
        }
        .defaultSize(width: 760, height: 560)
        .keyboardShortcut("y", modifiers: .command)

        Window(tr("window.practice"), id: "practice") {
            PracticeView().environment(model).id(model.settings.uiLanguage)
        }
        .defaultSize(width: 560, height: 560)
        .keyboardShortcut("p", modifiers: [.command, .shift])

        Window(tr("window.onboarding"), id: "onboarding") {
            OnboardingView().environment(model).id(model.settings.uiLanguage)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
        .commandsRemoved()
        .onboardingRestorationDisabled()

        // A regular window rather than the Settings scene: it gets a full-height sidebar with
        // search, like System Settings, instead of a preferences toolbar and a stray sidebar toggle.
        Window(tr("window.settings"), id: "settings") {
            SettingsView().environment(model).id(model.settings.uiLanguage)
        }
        .defaultSize(width: 860, height: 640)
        .windowToolbarStyle(.unified)
        .defaultPosition(.center)

        MenuBarExtra {
            MenuBarContent().environment(model)
        } label: {
            Image(nsImage: MenuBarIcon.image(recording: model.isRecording))
                .accessibilityLabel("Saidright")
        }
    }
}

extension Scene {
    /// The introduction should open only when asked, never through window restoration.
    func onboardingRestorationDisabled() -> some Scene {
        if #available(macOS 15.0, *) { return self.restorationBehavior(.disabled) }
        return self
    }
}

struct AppCommands: Commands {
    let model: AppModel
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(tr("menu.settings")) { SettingsRouter.open() }.keyboardShortcut(",")
        }
        CommandGroup(replacing: .newItem) {
            Button(tr("menu.startStop")) { model.isRecording ? model.stopRecording() : model.startRecording(trigger: .button) }
                .keyboardShortcut("d")
            Button(tr("menu.cancel")) { model.cancel() }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(!model.isBusy)
        }
    }
}

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(model.isRecording ? tr("menu.stop") : tr("menu.start")) {
            model.isRecording ? model.stopRecording() : model.startRecording(trigger: .button)
        }
        .disabled(model.isBusy && !model.isRecording)
        Divider()
        Text(tr("menu.mode", model.activeMode.name))
        ForEach(model.modes.modes) { mode in
            Button {
                model.modes.setActive(mode.id)
            } label: {
                if mode.id == model.activeMode.id { Label(mode.name, systemImage: "checkmark") } else { Text(mode.name) }
            }
            .disabled(model.isBusy)
        }
        Divider()
        Text(model.statusLine)
        Button(tr("menu.open")) { WindowRouter.show("main") }
        Button(tr("window.history")) { NSApp.activate(); openWindow(id: "history") }
        Button(tr("menu.settings")) { SettingsRouter.open() }
        Divider()
        Button(tr("menu.quit")) { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
