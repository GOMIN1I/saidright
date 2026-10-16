import AppKit
import AVFoundation
import Observation
import Security

/// Tracks each macOS permission separately and re-checks while any is missing, so a grant
/// made in System Settings takes effect without restarting or visiting a settings page.
@MainActor @Observable final class Permissions {
    enum State: Equatable { case granted, denied, notDetermined }

    private(set) var microphone: State = .notDetermined
    /// Input Monitoring: required to observe a bare modifier key.
    private(set) var listenEvents = false
    /// Accessibility / event posting: required to paste into other apps and read the focused field.
    private(set) var accessibility = false
    private(set) var postEvents = false
    /// How this build is signed; ad hoc builds lose permissions on every rebuild.
    let signing: SigningInfo = SigningInfo.current()

    /// Called whenever a permission flips, so services can (re)install themselves.
    var onChange: (() -> Void)?
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    var allGranted: Bool { microphone == .granted && listenEvents && accessibility }

    func refresh() {
        let mic: State
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: mic = .granted
        case .notDetermined: mic = .notDetermined
        default: mic = .denied
        }
        let listen = CGPreflightListenEventAccess()
        let ax = AXIsProcessTrusted()
        let post = CGPreflightPostEventAccess()
        let changed = mic != microphone || listen != listenEvents || ax != accessibility || post != postEvents
        microphone = mic
        listenEvents = listen
        accessibility = ax
        postEvents = post
        if changed { onChange?() }
    }

    func requestMicrophone() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        refresh()
        return granted
    }

    /// Shows the system prompt once; afterwards macOS only allows enabling it in System Settings.
    func requestListen() {
        if !CGRequestListenEventAccess() { openSettings(.inputMonitoring) }
        refresh()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) { _ = CGRequestPostEventAccess() }
        refresh()
    }

    enum Pane: String {
        case microphone = "Privacy_Microphone"
        case inputMonitoring = "Privacy_ListenEvent"
        case accessibility = "Privacy_Accessibility"
    }

    func openSettings(_ pane: Pane) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Reads this app's own code signature to explain permission behaviour honestly.
struct SigningInfo: Equatable {
    var isAdHoc: Bool
    var teamID: String?
    var identifier: String?

    static func current() -> SigningInfo {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return SigningInfo(isAdHoc: true) }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return SigningInfo(isAdHoc: true) }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess, let dict = info as? [String: Any] else { return SigningInfo(isAdHoc: true) }
        let team = dict[kSecCodeInfoTeamIdentifier as String] as? String
        let flags = (dict[kSecCodeInfoFlags as String] as? UInt32) ?? 0
        let adHoc = flags & 0x0002 != 0 || team == nil // kSecCodeSignatureAdhoc
        return SigningInfo(isAdHoc: adHoc, teamID: team, identifier: dict[kSecCodeInfoIdentifier as String] as? String)
    }

    init(isAdHoc: Bool, teamID: String? = nil, identifier: String? = nil) {
        self.isAdHoc = isAdHoc
        self.teamID = teamID
        self.identifier = identifier
    }
}
