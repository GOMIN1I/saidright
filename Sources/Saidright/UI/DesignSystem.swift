import AppKit
import SaidrightCore
import SwiftUI

/// Semantic design tokens. Views use these names, never raw values, so the visual system
/// can be tuned in one place. See docs/DESIGN.md for rationale.
enum DS {
    enum Palette {
        /// Recording / live signal. Matches the capsule default.
        static let signal = Color(hex: 0x4F9DFF)
        /// Processing / AI work.
        static let process = Color(hex: 0xFF4FA3)
        static let success = Color(nsColor: .systemGreen)
        static let warning = Color(hex: 0xE89A00)
        static let danger = Color(nsColor: .systemRed)
        static let added = Color(nsColor: .systemGreen)
        static let removed = Color(nsColor: .systemRed)
        static let secondaryText = Color(nsColor: .secondaryLabelColor)
        static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
        static let hairline = Color(nsColor: .separatorColor)
        /// Calm reading surface for feedback and transcripts.
        static let readingSurface = Color(nsColor: .textBackgroundColor)
        static let quietFill = Color(nsColor: .quaternaryLabelColor).opacity(0.5)
    }

    /// Saidright's own colours, taken from the app icon: the deep indigo tile (lighter at the
    /// top, darker at the bottom), the voice-blue bars and the coral cursor. Each surface has a
    /// light and a dark shade and follows the window's appearance (docs/DESIGN.md → Brand colour).
    enum Brand {
        /// Icon tile, top and bottom.
        static let indigoTop = Color(hex: 0x2A3A78)
        static let indigoBottom = Color(hex: 0x111833)
        static let voice = Color(hex: 0x3D6BFF)
        static let coral = Color(hex: 0xFF5A4E)
        /// Coral-pink of the product page: warm accents next to the voice blue.
        static let rose = Color(hex: 0xFF5257)
        static let violet = Color(hex: 0x7B5CFF)
        static let paper = Color(hex: 0xF6F3EC)

        /// Window background: a whisper of indigo on white, deep indigo at night.
        static let canvas = Color.dynamic(light: 0xF2F4FB, dark: 0x0E1430)
        /// Sidebar and secondary areas.
        static let sidebar = Color.dynamic(light: 0xE8ECF8, dark: 0x0A0F26)
        /// Cards and grouped settings: slightly see-through, so the living background glows under them.
        static let card = Color.dynamic(light: 0xFFFFFF, dark: 0x161E3E, lightAlpha: 0.74, darkAlpha: 0.66)
        static let cardEdge = Color.dynamic(light: 0x2A3A78, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.08)
        /// Controls: voice blue, lifted in the dark so it keeps its contrast.
        static let accent = Color.dynamic(light: 0x3D6BFF, dark: 0x5E7DFF)
        /// The tile gradient, for hero surfaces (onboarding, the about mark).
        static let tile = LinearGradient(colors: [indigoTop, indigoBottom], startPoint: .top, endPoint: .bottom)
        /// Prominent controls: voice blue into violet, as on the product page.
        static let action = LinearGradient(colors: [Color(hex: 0x3D6BFF), Color(hex: 0x6A5CFF)], startPoint: .leading, endPoint: .trailing)
        /// Finishing moments (Finish, Got it): blue through violet into the rose.
        static let warm = LinearGradient(colors: [Color(hex: 0x5B6CFF), Color(hex: 0xB45CF0), Color(hex: 0xFF5257)], startPoint: .leading, endPoint: .trailing)
    }

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let small: CGFloat = 6
        static let control: CGFloat = 10
        static let surface: CGFloat = 14
    }

    enum Size {
        static let mainWidth: CGFloat = 400
        static let recordButton: CGFloat = 60
        static let minTarget: CGFloat = 28
    }

    enum Font {
        static let headline = SwiftUI.Font.system(size: 17, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13)
        static let reading = SwiftUI.Font.system(size: 14)
        static let caption = SwiftUI.Font.system(size: 11)
        static let mono = SwiftUI.Font.system(size: 11, design: .monospaced)
        static let sectionTitle = SwiftUI.Font.system(size: 11, weight: .semibold)
    }

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.15)
        static let standard = Animation.spring(response: 0.32, dampingFraction: 0.82)
    }
}

extension Color {
    /// A colour that resolves per appearance (light / dark), like the system's own colours.
    static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        func ns(_ hex: UInt32, _ alpha: CGFloat) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? ns(dark, darkAlpha) : ns(light, lightAlpha)
        })
    }
}

private struct BrandTintKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    /// True when windows use Saidright's colours (Settings → Appearance → Window colour).
    var brandTint: Bool {
        get { self[BrandTintKey.self] }
        set { self[BrandTintKey.self] = newValue }
    }
}

/// Surfaces that follow the window colour setting.
enum Surface {
    static func canvas(_ brand: Bool) -> Color { brand ? DS.Brand.canvas : Color(nsColor: .windowBackgroundColor) }
    static func card(_ brand: Bool) -> Color { brand ? DS.Brand.card : Color(nsColor: .controlBackgroundColor) }
    static func cardEdge(_ brand: Bool) -> Color { brand ? DS.Brand.cardEdge : DS.Palette.hairline.opacity(0.5) }
    static func accent(_ brand: Bool) -> Color { brand ? DS.Brand.accent : DS.Palette.signal }
}

/// Root of every window: the window colour, the accent for controls, and the setting in the
/// environment for nested surfaces.
struct BrandWindow: ViewModifier {
    var tint: WindowTint
    /// Split-view windows (Settings) need the colour as the window's container background so the
    /// detail column shows it. Elsewhere it is a plain background layer: as a container
    /// background it is drawn over the close / minimise / zoom buttons of a hidden title bar.
    var container = false
    func body(content: Content) -> some View {
        let brand = tint == .saidright
        let styled = content
            .environment(\.brandTint, brand)
            .tint(Surface.accent(brand))
        if container, #available(macOS 15.0, *) {
            styled.containerBackground(for: .window) { WindowBackdrop(brand: brand) }
        } else {
            styled.background(WindowBackdrop(brand: brand).ignoresSafeArea())
        }
    }
}

/// The window colour: plain for System, the living aurora for Saidright.
struct WindowBackdrop: View {
    var brand: Bool
    var body: some View {
        Group {
            if brand { AuroraBackground() } else { Color(nsColor: .windowBackgroundColor) }
        }
        // Windows whose content is pulled into the hidden title bar (the main window) are laid
        // out below it; reaching up keeps the title-bar band in the window colour instead of the
        // system's grey backdrop. The window clips what lies above its top edge.
        .padding(.top, -60)
    }
}

/// Saidright's living background, the product page's hero brought into the app: deep night
/// indigo (light: airy mist) with soft lights — voice blue, the icon's indigo and a faint coral
/// low on the right — drifting slowly like breath. Core Animation moves the lights in the render server, so the app itself does no
/// per-frame work; still with Reduce Motion, plain with Reduce Transparency.
struct AuroraBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        AuroraLayers(dark: scheme == .dark, moving: !reduceMotion, lights: !reduceTransparency)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

private struct AuroraLayers: NSViewRepresentable {
    var dark: Bool
    var moving: Bool
    var lights: Bool

    func makeNSView(context: Context) -> AuroraView { AuroraView() }
    func updateNSView(_ view: AuroraView, context: Context) { view.configure(dark: dark, moving: moving, lights: lights) }
}

final class AuroraView: NSView {
    private let base = CAGradientLayer()
    private var blobs: [CAGradientLayer] = []
    private var state: (Bool, Bool, Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(base)
        for _ in 0..<3 {
            let blob = CAGradientLayer()
            blob.type = .radial
            blob.startPoint = CGPoint(x: 0.5, y: 0.5)
            blob.endPoint = CGPoint(x: 1, y: 1)
            layer?.addSublayer(blob)
            blobs.append(blob)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(dark: Bool, moving: Bool, lights: Bool) {
        guard state.map({ $0 != (dark, moving, lights) }) ?? true else { return }
        state = (dark, moving, lights)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        // Dark: the site hero (#19245A → #0E1430 night) with the voice blue, the icon's indigo
        // and a faint coral. Normal blending keeps it deep; screen blending washed it out.
        let baseHexes: [UInt32] = dark ? [0x19245A, 0x111A44, 0x0E1430] : [0xF6F7FE, 0xEEF1FB, 0xE7EBF9]
        base.colors = baseHexes.map { Self.cg($0, 1) }
        base.startPoint = CGPoint(x: 0, y: 1); base.endPoint = CGPoint(x: 0.3, y: 0)
        let palette: [(UInt32, CGFloat)] = dark ? [(0x3D6BFF, 0.34), (0x2A3A78, 0.75), (0xFF5A4E, 0.12)] : [(0x8FB0FF, 0.42), (0xC4B5FF, 0.34), (0xFF8E92, 0.24)]
        for (blob, (hex, alpha)) in zip(blobs, palette) {
            blob.colors = [Self.cg(hex, alpha), Self.cg(hex, 0)]
            blob.compositingFilter = nil
            blob.isHidden = !lights
        }
        CATransaction.commit()
        layoutBlobs()
        startMotion(moving)
    }

    override func layout() {
        super.layout()
        layoutBlobs()
    }

    /// Lights sit where the product page has them: blue right of centre, indigo top-left, a small
    /// coral glow bottom-right (light mode keeps its original three spots).
    private func layoutBlobs() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        base.frame = bounds
        let side = max(bounds.width, bounds.height)
        let dark = state?.0 ?? true
        let spots: [CGPoint] = dark ? [CGPoint(x: 0.72, y: 0.62), CGPoint(x: 0.08, y: 0.90), CGPoint(x: 0.90, y: 0.15)] : [CGPoint(x: 0.22, y: 0.72), CGPoint(x: 0.80, y: 0.76), CGPoint(x: 0.80, y: 0.10)]
        let sizes: [CGFloat] = dark ? [0.62, 0.70, 0.40] : [0.78, 0.78, 0.78]
        for (i, blob) in blobs.enumerated() {
            let r = side * sizes[i]
            blob.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 2)
            blob.position = CGPoint(x: bounds.width * spots[i].x, y: bounds.height * spots[i].y)
        }
        CATransaction.commit()
    }

    private func startMotion(_ moving: Bool) {
        for (i, blob) in blobs.enumerated() {
            blob.removeAllAnimations()
            guard moving else { continue }
            let drift = CABasicAnimation(keyPath: "transform")
            let dx = CGFloat([0.14, -0.10, -0.12][i]) * max(bounds.width, 400)
            let dy = CGFloat([-0.10, 0.12, 0.08][i]) * max(bounds.height, 300)
            drift.fromValue = CATransform3DIdentity
            drift.toValue = CATransform3DScale(CATransform3DMakeTranslation(dx, dy, 0), 1.12, 1.12, 1)
            drift.duration = [17, 23, 19][i]
            drift.autoreverses = true
            drift.repeatCount = .infinity
            drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            drift.beginTime = CACurrentMediaTime() - Double(i) * 5
            blob.add(drift, forKey: "drift")
        }
    }

    private static func cg(_ hex: UInt32, _ alpha: CGFloat) -> CGColor {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        return CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

extension View {
    func brandWindow(_ tint: WindowTint, container: Bool = false) -> some View { modifier(BrandWindow(tint: tint, container: container)) }
}

/// Glass on macOS 26+ for floating controls only; a quiet material elsewhere and when
/// Reduce Transparency is on.
struct GlassBackground<S: Shape>: ViewModifier {
    var shape: S
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .controlBackgroundColor), in: shape).overlay(shape.stroke(DS.Palette.hairline, lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape).overlay(shape.stroke(DS.Palette.hairline.opacity(0.6), lineWidth: 0.5))
        }
    }
}

/// Groups neighbouring glass elements so they sample one another consistently (macOS 26+).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

extension View {
    func glass<S: Shape>(_ shape: S, interactive: Bool = false) -> some View { modifier(GlassBackground(shape: shape, interactive: interactive)) }

    /// Section label in small caps style, used instead of nested cards.
    func sectionLabel() -> some View { font(DS.Font.sectionTitle).foregroundStyle(DS.Palette.secondaryText).textCase(.uppercase) }
}

/// Small coloured dot plus text; colour is never the only signal (text always present).
/// The pulsing variant is a separate view so its repeating animation is torn down when it stops.
struct StatusDot: View {
    var color: Color
    var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if pulsing && !reduceMotion { PulsingDot(color: color) } else { Circle().fill(color) }
        }
        .frame(width: 7, height: 7)
        .accessibilityHidden(true)
    }
}

private struct PulsingDot: View {
    var color: Color
    @State private var on = false
    var body: some View {
        Circle().fill(color)
            .opacity(on ? 1 : 0.35)
            .animation(.easeInOut(duration: 0.8).repeatForever(), value: on)
            .onAppear { on = true }
    }
}

struct PillButtonStyle: ButtonStyle {
    var prominent = false
    /// The finishing action of a flow: blue through violet into rose.
    var warm = false
    @Environment(\.brandTint) private var brand
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 5)
            .frame(minHeight: DS.Size.minTarget - 4)
            .background(prominent ? (brand ? (warm ? AnyShapeStyle(DS.Brand.warm) : AnyShapeStyle(DS.Brand.action)) : AnyShapeStyle(DS.Palette.signal)) : AnyShapeStyle(DS.Palette.quietFill), in: Capsule())
            .shadow(color: prominent && brand ? Color(hex: 0x4F63FF).opacity(configuration.isPressed ? 0.2 : 0.38) : .clear, radius: 8, y: 3)
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}
