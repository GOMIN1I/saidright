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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 5)
            .frame(minHeight: DS.Size.minTarget - 4)
            .background(prominent ? AnyShapeStyle(DS.Palette.signal) : AnyShapeStyle(DS.Palette.quietFill), in: Capsule())
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}
