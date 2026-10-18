import AppKit
import Observation
import SaidrightCore
import SwiftUI

/// What the capsule may teach after a dictation: the selected items of one record.
struct CapsuleHint: Equatable {
    var recordID: UUID
    var items: [FeedbackItem]
    var index = 0
    var expanded = false
    /// The inserted text can be replaced with the tip's fixes (card button).
    var fixable = false
    var current: FeedbackItem? { items.indices.contains(index) ? items[index] : nil }
}

/// State of the floating capsule. Kept separate from AppModel so level updates at 30 Hz
/// only invalidate the capsule, not the rest of the interface.
///
/// Sequence: recording → processing → delivered → (optional) learning hint → gone.
/// Text is delivered before any hint exists; a hint never delays insertion, and starting a new
/// recording replaces whatever the capsule shows at once.
@MainActor @Observable final class CapsuleModel {
    enum Display: Equatable {
        case hidden
        case recording
        case processing
        case done
        /// Finished, but the text was copied or kept rather than inserted.
        case doneElsewhere
        case noSpeech
        case error
        case cancelled
        case mode
        /// A small marker that feedback is ready; click to open the card.
        case hintMarker
        /// The learning card with the correction.
        case hint
    }

    private(set) var display: Display = .hidden
    /// Recent input levels, newest last (one per bar).
    private(set) var levels: [Float] = Array(repeating: 0, count: CapsuleMetrics.barCount)
    var recordingColor = Color(hex: 0x4F9DFF)
    var processingColor = Color(hex: 0xFF5FA8)
    var doneColor = Color(hex: 0x3FD08A)
    var glow: Double = 0.6
    var reduceMotionSetting = false
    var motion: MotionPreference = .standard
    var style: CapsuleStyle = .glass
    var scale: CGFloat = 1
    var enabled = true
    var placement: CapsulePlacement = .bottom
    var showModeBadge = true
    var modeName = ""
    var modeSymbol = "waveform"
    private(set) var hint: CapsuleHint?
    /// How long a hint stays; nil = until dismissed or the next dictation.
    var hintLinger: Double? = 7
    /// The person hovered or clicked: keep the hint until they dismiss it.
    private(set) var pinned = false
    /// Increments to trigger a small shake when a press is ignored while busy.
    private(set) var nudgeCount = 0
    /// Set by the controller; called when visibility or interactivity should change.
    var onVisibilityChange: ((Bool) -> Void)?
    var onInteractivityChange: ((Bool) -> Void)?
    var previewing = false

    // Hint actions, wired by AppModel.
    var onSaveItem: ((UUID, UUID) -> Void)?
    var onVerdict: ((UUID, UUID, UserVerdict) -> Void)?
    var onOpenApp: ((UUID) -> Void)?
    var onApplyCorrection: ((UUID) -> Void)?

    /// The tip's fixes were applied (or could not be): the card's Replace button goes away.
    func markCorrectionHandled(_ recordID: UUID) {
        if hint?.recordID == recordID { hint?.fixable = false }
    }

    private var hideTask: Task<Void, Never>?

    var isInteractive: Bool { display == .hint || display == .hintMarker }

    func apply(_ settings: CapsuleSettings) {
        let colors = settings.resolvedColors
        recordingColor = Color(hex: colors.recording)
        processingColor = Color(hex: colors.processing)
        doneColor = Color(hex: colors.done)
        glow = settings.glow
        reduceMotionSetting = settings.reduceMotion || settings.motion == .minimal
        motion = settings.motion
        // QA: SAIDRIGHT_QA_STYLE=ink|glass overrides the material for screenshots without saving.
        style = ProcessInfo.processInfo.environment["SAIDRIGHT_QA_STYLE"].flatMap(CapsuleStyle.init(rawValue:)) ?? settings.style
        scale = settings.size.scale
        enabled = settings.enabled
        placement = settings.placement
        showModeBadge = settings.showModeBadge
    }

    func push(level: Float) {
        levels.removeFirst()
        levels.append(level)
    }

    func show(_ next: Display) {
        hideTask?.cancel()
        folding = false
        if next != .hint { stageTask?.cancel() }
        if next == .recording { levels = Array(repeating: 0, count: CapsuleMetrics.barCount) }
        if next != .hint && next != .hintMarker { hint = nil; pinned = false }
        let wasHidden = display == .hidden
        let wasInteractive = isInteractive
        display = next
        announce(next)
        if wasHidden { onVisibilityChange?(enabled || previewing) }
        if wasInteractive != isInteractive { onInteractivityChange?(isInteractive) }
        // Terminal states linger briefly, then leave. Errors stay longer so they can be read.
        let linger: Double? = switch next {
        case .done, .doneElsewhere: 0.55
        case .noSpeech: 1.3
        case .error: 2.2
        case .cancelled: 0.35
        case .mode: 1.2
        case .hint, .hintMarker: pinned ? nil : hintLinger
        default: nil
        }
        if let linger, !previewing { scheduleHide(after: linger) }
    }

    func hide() {
        hideTask?.cancel()
        stageTask?.cancel()
        guard display != .hidden else { return }
        // An open card folds back into the capsule before it leaves, mirroring how it appeared:
        // its text fades first, then the body shrinks to a plain capsule, then it goes.
        if display == .hint, !reducedMotion, !previewing {
            folding = true
            stageTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled, let self, self.display == .hint else { return }
                self.display = .hintMarker
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, self.display == .hintMarker else { return }
                self.finishHide()
            }
            return
        }
        finishHide()
    }

    private func finishHide() {
        folding = false
        guard display != .hidden else { return }
        let wasInteractive = isInteractive
        display = .hidden
        hint = nil
        pinned = false
        if wasInteractive { onInteractivityChange?(false) }
        onVisibilityChange?(false)
    }

    /// Offers a learning hint for a finished dictation. Ignored while a new session is visible,
    /// so feedback that arrives late never covers a recording.
    func offerHint(_ hint: CapsuleHint, asMarker: Bool) {
        guard !hint.items.isEmpty, enabled else { return }
        switch display {
        case .hidden, .done, .doneElsewhere, .hint, .hintMarker: break
        default: return
        }
        let wasCompact = display != .hint
        self.hint = hint
        stageTask?.cancel()
        // The card emerges from the capsule: the compact tip capsule appears (or the delivered
        // capsule turns into it), then the same body stretches into the card.
        if asMarker || reducedMotion || !wasCompact {
            show(asMarker ? .hintMarker : .hint)
            return
        }
        let fromHidden = display == .hidden
        show(.hintMarker)
        let id = hint.recordID
        stageTask = Task { [weak self] in
            // From nothing, let the small capsule land first; from a visible capsule, stretch sooner.
            try? await Task.sleep(for: .milliseconds(fromHidden ? 320 : 180))
            guard !Task.isCancelled, let self, self.display == .hintMarker, self.hint?.recordID == id else { return }
            self.show(.hint)
        }
    }

    private var stageTask: Task<Void, Never>?
    /// True while an open card folds away; its text and the tip label stay hidden.
    private(set) var folding = false
    /// Measured size of the visible surface; the controller fits the panel to it.
    var surfaceSize: CGSize = .zero { didSet { if surfaceSize != oldValue { onSurfaceSizeChange?(surfaceSize) } } }
    var onSurfaceSizeChange: ((CGSize) -> Void)?

    private var reducedMotion: Bool { reduceMotionSetting || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func expandHint() {
        guard var h = hint else { return }
        pin()
        if display == .hintMarker { show(.hint); return }
        h.expanded.toggle()
        hint = h
    }

    func pageHint(_ delta: Int) {
        guard var h = hint else { return }
        pin()
        h.index = max(0, min(h.items.count - 1, h.index + delta))
        h.expanded = false
        hint = h
    }

    /// Marks the shown item as handled and moves on, or closes when it was the last one.
    func resolveCurrentHint() {
        guard var h = hint else { return }
        h.items.remove(at: h.index)
        if h.items.isEmpty { hide(); return }
        h.index = min(h.index, h.items.count - 1)
        h.expanded = false
        hint = h
    }

    /// Hover or click keeps the hint until the person closes it.
    func pin() {
        guard !pinned, display == .hint || display == .hintMarker else { return }
        pinned = true
        hideTask?.cancel()
    }

    /// The sample tip as the real arrival path delivers it (used by previews and QA).
    func offerSampleHint() {
        offerHint(Self.sampleHint(), asMarker: false)
    }

    static func sampleHint() -> CapsuleHint {
        let sample = FeedbackItem(original: "I am agree", suggestion: "I agree", kind: .grammar, explanation: tr("capsule.sampleExplanation"), details: tr("capsule.sampleDetails"), rule: "", example: "I agree with you.", uncertain: false, topic: "")
        return CapsuleHint(recordID: UUID(), items: [sample])
    }

    func previewHint() {
        let sample = FeedbackItem(original: "I am agree", suggestion: "I agree", kind: .grammar, explanation: tr("capsule.sampleExplanation"), details: tr("capsule.sampleDetails"), rule: "", example: "I agree with you.", uncertain: false, topic: "")
        hint = CapsuleHint(recordID: UUID(), items: [sample])
        show(.hint)
    }

    func flashMode(_ name: String, symbol: String) {
        modeName = name
        modeSymbol = symbol
        guard showModeBadge else { return }
        show(.mode)
    }

    func nudge() { nudgeCount += 1 }

    /// A short message in the capsule regardless of the mode-badge setting.
    func flash(_ text: String, symbol: String) {
        modeName = text
        modeSymbol = symbol
        show(.mode)
    }

    private func scheduleHide(after seconds: Double) {
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func announce(_ display: Display) {
        let text: String? = switch display {
        case .recording: tr("capsule.recording")
        case .processing: tr("capsule.processing")
        case .done: tr("capsule.done")
        case .doneElsewhere: tr("capsule.doneElsewhere")
        case .noSpeech: tr("capsule.noSpeech")
        case .error: tr("capsule.error")
        case .cancelled: tr("capsule.cancelled")
        case .mode: modeName
        case .hint, .hintMarker: hint?.current.map { tr("capsule.hintAnnouncement", $0.original, $0.suggestion) }
        case .hidden: nil
        }
        guard let text, !previewing else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

enum CapsuleMetrics {
    static let barCount = 7
    static let height: CGFloat = 34
    static let width: CGFloat = 78
    static let modeWidth: CGFloat = 168
    static let barWidth: CGFloat = 3
    static let barSpacing: CGFloat = 3.5
    static let minBar: CGFloat = 4
    static let maxBar: CGFloat = 18
    static let cardWidth: CGFloat = 372
    static let cardRadius: CGFloat = 20
    /// Panel for plain capsule states: larger than the capsule so the entrance can scale.
    static let panelSize = CGSize(width: 240, height: 76)
    /// Panel while the learning card is visible (the card itself sizes to its content).
    static let cardPanelSize = CGSize(width: cardWidth + 40, height: 300)
}

/// Spring choices per motion preference. Reduce Motion (system or app) always means fades only.
struct CapsuleMotion {
    var preference: MotionPreference
    var reduced: Bool

    var entrance: Animation { reduced ? .easeOut(duration: 0.15) : preference == .gentle ? .spring(response: 0.42, dampingFraction: 0.9) : .spring(response: 0.36, dampingFraction: 0.74) }
    var change: Animation? { reduced ? .easeInOut(duration: 0.15) : preference == .gentle ? .spring(response: 0.38, dampingFraction: 0.92) : .spring(response: 0.32, dampingFraction: 0.8) }
    /// Capsule → card: a slightly softer spring so the body visibly stretches, without bouncing.
    var morph: Animation { reduced ? .easeInOut(duration: 0.18) : preference == .gentle ? .spring(response: 0.46, dampingFraction: 0.92) : .spring(response: 0.42, dampingFraction: 0.8) }
}

struct CapsuleView: View {
    let model: CapsuleModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var reduceMotion: Bool { systemReduceMotion || model.reduceMotionSetting }
    private var motion: CapsuleMotion { CapsuleMotion(preference: model.motion, reduced: reduceMotion) }
    private var visible: Bool { model.display != .hidden }
    private var isCard: Bool { model.display == .hint && model.hint != nil }

    var body: some View {
        ZStack(alignment: model.placement == .top ? .top : .bottom) {
            if visible {
                surface
                    .padding(model.placement == .top ? .top : .bottom, 14)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .scale(scale: 0.6, anchor: model.placement == .top ? .top : .bottom).combined(with: .opacity),
                        removal: .scale(scale: 0.88, anchor: model.placement == .top ? .top : .bottom).combined(with: .opacity)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.placement == .top ? .top : .bottom)
        .animation(motion.entrance, value: visible)
        .animation(motion.change, value: model.display)
        .animation(motion.morph, value: isCard)
        .animation(motion.morph, value: model.hint)
    }

    private var tint: Color {
        switch model.display {
        case .recording: model.recordingColor
        case .processing, .mode: model.processingColor
        case .done, .doneElsewhere, .hint, .hintMarker: model.doneColor
        case .error: Color(hex: 0xFFB020)
        case .noSpeech, .cancelled, .hidden: Color(white: 0.6)
        }
    }

    /// One body that morphs between capsule and card, so expansion reads as the same object growing.
    private var surface: some View {
        let s = model.scale
        let radius = isCard ? CapsuleMetrics.cardRadius : CapsuleMetrics.height * s / 2
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            if isCard, let hint = model.hint {
                // The body stretches first; the text settles in once there is room for it, so
                // nothing is seen clipped or overlapping during the morph.
                HintCard(model: model, hint: hint, ink: inkText)
                    .opacity(model.folding ? 0 : 1)
                    .animation(.easeIn(duration: 0.09), value: model.folding)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 6)).animation(.easeOut(duration: 0.22).delay(0.16)),
                        removal: .opacity.animation(.easeIn(duration: 0.09))))
            } else {
                compactContent
                    .frame(width: compactWidth, height: CapsuleMetrics.height * s)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.12)),
                        removal: .opacity.animation(.easeIn(duration: 0.08))))
            }
        }
        .background {
            CapsuleSurface(shape: shape, tint: tint, glow: model.glow, style: model.style, opaque: reduceTransparency, highContrast: contrast == .increased, card: isCard)
        }
        .clipShape(shape)
        .contentShape(shape)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { model.surfaceSize = $0 }
        .shadow(color: .black.opacity(model.style == .ink || reduceTransparency ? 0.4 : 0.22), radius: isCard ? 14 : 6, y: isCard ? 6 : 3)
        .modifier(Shake(count: model.nudgeCount, enabled: !reduceMotion))
        .onHover { if $0 { model.pin() } }
        .accessibilityElement(children: isCard ? .contain : .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(model.display == .hintMarker ? .isButton : [])
        .accessibilityAction { if model.display == .hintMarker { model.expandHint() } }
    }

    /// Ink is always dark; glass follows the window theme (set on the hosting view).
    private var inkText: Bool { model.style == .ink || reduceTransparency == false && model.style == .ink }

    private var compactWidth: CGFloat? {
        let s = model.scale
        switch model.display {
        case .mode: return CapsuleMetrics.modeWidth * s
        case .hintMarker: return nil // sized by its label, which differs a lot between languages
        default: return (CapsuleMetrics.width + (glyph == nil ? 0 : 14)) * s
        }
    }

    @ViewBuilder private var compactContent: some View {
        let s = model.scale
        let foreground: Color = model.style == .ink ? .white.opacity(0.92) : .primary
        switch model.display {
        case .mode:
            HStack(spacing: 7) {
                Image(systemName: model.modeSymbol).font(.system(size: 12 * s, weight: .semibold))
                Text(model.modeName).font(.system(size: 12 * s, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
        case .hintMarker where model.folding:
            Color.clear.frame(width: CapsuleMetrics.width * s)
        case .hintMarker:
            Button { model.expandHint() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "character.book.closed").font(.system(size: 11 * s, weight: .semibold)).foregroundStyle(tint)
                    Text(tr("capsule.hintMarker", model.hint?.items.count ?? 0)).font(.system(size: 11 * s, weight: .semibold)).foregroundStyle(foreground).lineLimit(1)
                }
                .padding(.horizontal, 15 * s)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .help(tr("capsule.hintMarkerHelp"))
        default:
            HStack(spacing: 6) {
                CapsuleBars(model: model, tint: tint, reduceMotion: reduceMotion, scale: s)
                if let glyph {
                    Image(systemName: glyph)
                        .font(.system(size: 10 * s, weight: .bold))
                        .foregroundStyle(tint)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    /// Non-colour cue for every state that is not plain recording/processing.
    private var glyph: String? {
        switch model.display {
        case .done: "checkmark"
        case .doneElsewhere: "doc.on.clipboard"
        case .noSpeech: "minus"
        case .error: "exclamationmark"
        case .cancelled: "xmark"
        default: nil
        }
    }

    private var accessibilityText: String {
        switch model.display {
        case .recording: tr("capsule.recording")
        case .processing: tr("capsule.processing")
        case .done: tr("capsule.done")
        case .doneElsewhere: tr("capsule.doneElsewhere")
        case .noSpeech: tr("capsule.noSpeech")
        case .error: tr("capsule.error")
        case .cancelled: tr("capsule.cancelled")
        case .mode: model.modeName
        case .hintMarker: tr("capsule.hintMarker", model.hint?.items.count ?? 0)
        case .hint: tr("capsule.hintTitle")
        case .hidden: ""
        }
    }
}

/// The capsule material. Glass: native Liquid Glass (macOS 26+) with a faint state tint.
/// Ink: the restrained near-black body with a lit edge and soft internal light.
struct CapsuleSurface<S: InsettableShape>: View {
    var shape: S
    var tint: Color
    var glow: Double
    var style: CapsuleStyle
    var opaque: Bool
    var highContrast: Bool
    var card = false

    var body: some View {
        if opaque {
            shape.fill(style == .ink ? Color(white: 0.06) : Color(nsColor: .windowBackgroundColor))
                .overlay(shape.stroke(highContrast ? Color.primary.opacity(0.7) : Color.primary.opacity(0.25), lineWidth: 1))
        } else if style == .glass, #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(tint.opacity(card ? 0.06 : 0.16 * max(0.4, glow))), in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(highContrast ? 0.55 : 0), lineWidth: 1))
        } else if style == .glass {
            shape.fill(.regularMaterial)
                .overlay(shape.fill(tint.opacity(card ? 0.04 : 0.12 * glow)))
                .overlay(shape.strokeBorder(Color.primary.opacity(highContrast ? 0.5 : 0.12), lineWidth: highContrast ? 1 : 0.5))
        } else {
            ZStack {
                shape.fill(Color(white: card ? 0.07 : 0.035))
                // Internal light: confined to the body, no external halo.
                shape.fill(RadialGradient(colors: [tint.opacity((card ? 0.08 : 0.22) * glow), .clear], center: card ? .top : .center, startRadius: 2, endRadius: card ? 220 : 46))
                    .blendMode(.screen)
                if !card { LivingLight(shape: shape, tint: tint, glow: glow) }
                shape.fill(LinearGradient(colors: [.white.opacity(0.07), .clear], startPoint: .top, endPoint: .center)).padding(1)
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(highContrast ? 0.6 : 0.22), .white.opacity(highContrast ? 0.35 : 0.04)], startPoint: .top, endPoint: .bottom), lineWidth: highContrast ? 1 : 0.75)
            }
            .compositingGroup()
        }
    }
}

/// The capsule breathes: a second light in the state colour drifts slowly inside the body and
/// a faint sheen passes over it, so the capsule never looks frozen. Confined to the shape;
/// still with Reduce Motion.
struct LivingLight<S: InsettableShape>: View {
    var shape: S
    var tint: Color
    var glow: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSince(start)
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    shape.fill(RadialGradient(colors: [tint.opacity(0.46 * glow * (0.7 + 0.3 * sin(t * 1.3))), .clear],
                                              center: UnitPoint(x: 0.5 + 0.32 * sin(t * 0.7), y: 0.65 + 0.15 * cos(t * 0.9)), startRadius: 1, endRadius: max(w, h) * 0.55))
                    shape.fill(LinearGradient(colors: [.clear, .white.opacity(0.09), .clear], startPoint: UnitPoint(x: -0.6 + (t * 0.18).truncatingRemainder(dividingBy: 2.2), y: 0), endPoint: UnitPoint(x: -0.2 + (t * 0.18).truncatingRemainder(dividingBy: 2.2), y: 1)))
                }
                .blendMode(.screen)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Kept for the main window's record control: the ink body as a plain capsule.
struct CapsuleBody: View {
    var tint: Color
    var glow: Double
    var opaque: Bool
    var highContrast: Bool

    var body: some View {
        CapsuleSurface(shape: Capsule(), tint: tint, glow: glow, style: .ink, opaque: opaque, highContrast: highContrast)
            .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
    }
}

/// Correction first, the friendly reason under it, details on request.
struct HintCard: View {
    let model: CapsuleModel
    var hint: CapsuleHint
    var ink: Bool

    var body: some View {
        let item = hint.current
        VStack(alignment: .leading, spacing: 10) {
            header(item)
            if let item {
                CorrectionLine(original: item.original, suggestion: item.suggestion, kind: item.kind, ink: ink)
                Text(item.explanation)
                    .font(.system(size: 13))
                    .foregroundStyle(primary)
                    .fixedSize(horizontal: false, vertical: true)
                if hint.expanded {
                    // Details fade in under the explanation while the card grows; they never slide over it.
                    details(item).transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.16)),
                        removal: .opacity.animation(.easeIn(duration: 0.08))))
                }
                actions(item)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(width: CapsuleMetrics.cardWidth, alignment: .leading)
        .environment(\.colorScheme, ink ? .dark : .light)
        .modifier(InheritScheme(enabled: !ink))
    }

    private var primary: Color { ink ? .white.opacity(0.92) : .primary }
    private var secondary: Color { ink ? .white.opacity(0.62) : .secondary }

    private func header(_ item: FeedbackItem?) -> some View {
        HStack(spacing: 8) {
            if let item { KindBadge(kind: item.kind, uncertain: item.uncertain) }
            Spacer(minLength: 4)
            if hint.items.count > 1 {
                Button { model.pageHint(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(hint.index == 0).accessibilityLabel(tr("capsule.previousHint"))
                Text(tr("capsule.hintCount", hint.index + 1, hint.items.count)).font(.system(size: 11).monospacedDigit()).foregroundStyle(secondary)
                Button { model.pageHint(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(hint.index >= hint.items.count - 1).accessibilityLabel(tr("capsule.nextHint"))
            }
            Button { model.hide() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .accessibilityLabel(tr("common.dismiss"))
                .help(tr("common.dismiss"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(secondary)
        .font(.system(size: 11, weight: .semibold))
    }

    @ViewBuilder private func details(_ item: FeedbackItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !item.details.isEmpty {
                Text(item.details).font(.system(size: 12.5)).foregroundStyle(primary).fixedSize(horizontal: false, vertical: true)
            } else if !item.rule.isEmpty {
                Text(item.rule).font(.system(size: 12.5)).foregroundStyle(primary).fixedSize(horizontal: false, vertical: true)
            }
            if !item.example.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "text.quote").font(.system(size: 10, weight: .semibold)).foregroundStyle(secondary).padding(.top, 2)
                    Text(item.example).font(.system(size: 12.5).italic()).foregroundStyle(primary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if item.kind == .possibleRecognitionError {
                Text(tr("capsule.misheardNote")).font(.system(size: 11)).foregroundStyle(secondary).fixedSize(horizontal: false, vertical: true)
            }
            // Disagreeing is always possible, but quieter than the main actions.
            Button(item.kind == .possibleRecognitionError ? tr("capsule.misheard") : tr("capsule.keepMine")) {
                model.onVerdict?(hint.recordID, item.id, item.kind == .possibleRecognitionError ? .recognitionError : .keepOriginal)
                model.resolveCurrentHint()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(secondary)
            .underline()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill((ink ? Color.white : Color.primary).opacity(0.06)))
    }

    private func actions(_ item: FeedbackItem) -> some View {
        HStack(spacing: 6) {
            Button(hint.expanded ? tr("capsule.less") : tr("capsule.more")) { model.expandHint() }
                .buttonStyle(CardButtonStyle(ink: ink))
                // Swap the label in place; a crossfade would leave a ghost while the row moves.
                .contentTransition(.identity)
                .help(tr("capsule.moreHelp"))
            Spacer(minLength: 4)
            if hint.fixable {
                Button(tr("capsule.replace")) { model.onApplyCorrection?(hint.recordID) }
                    .buttonStyle(CardButtonStyle(ink: ink, prominent: true))
                    .help(tr("capsule.replaceHelp"))
            }
            if item.kind.isLearnerError {
                Button(item.savedForReview ? tr("capsule.saved") : tr("capsule.save")) { model.onSaveItem?(hint.recordID, item.id); model.resolveCurrentHint() }
                    .buttonStyle(CardButtonStyle(ink: ink)).disabled(item.savedForReview)
            }
            Button(tr("capsule.gotIt")) { model.onVerdict?(hint.recordID, item.id, .understood); model.resolveCurrentHint() }
                .buttonStyle(CardButtonStyle(ink: ink, prominent: true))
        }
    }
}

/// Glass cards follow the window theme set on the hosting view rather than forcing light.
private struct InheritScheme: ViewModifier {
    var enabled: Bool
    @Environment(\.capsuleScheme) private var scheme
    func body(content: Content) -> some View {
        if enabled { content.environment(\.colorScheme, scheme) } else { content }
    }
}

private struct CapsuleSchemeKey: EnvironmentKey { static let defaultValue: ColorScheme = .dark }
extension EnvironmentValues {
    var capsuleScheme: ColorScheme {
        get { self[CapsuleSchemeKey.self] }
        set { self[CapsuleSchemeKey.self] = newValue }
    }
}

/// Original struck through, correction emphasised; never colour alone.
struct CorrectionLine: View {
    var original: String
    var suggestion: String
    var kind: FeedbackKind
    var ink: Bool

    var body: some View {
        let primary: Color = ink ? .white : .primary
        WrapLayout(spacing: 6) {
            Text(original)
                .strikethrough(kind != .style, color: (ink ? Color.white : Color.primary).opacity(0.55))
                .foregroundStyle(primary.opacity(0.6))
            Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(primary.opacity(0.5)).padding(.top, 3)
            Text(suggestion).fontWeight(.semibold).foregroundStyle(primary)
                .underline(kind == .style, pattern: .dot)
        }
        .font(.system(size: 15))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("capsule.hintAnnouncement", original, suggestion))
    }
}

/// Says what kind of note this is, so a style option never looks like a mistake.
struct KindBadge: View {
    var kind: FeedbackKind
    var uncertain: Bool

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 10.5, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
    }

    private var text: String {
        if kind.isLearnerError && uncertain { return tr("hintkind.unsure") }
        return tr("hintkind.\(kind.rawValue)")
    }

    private var symbol: String {
        switch kind {
        case .grammar: "textformat"
        case .vocabulary: "character.book.closed"
        case .slip: "arrow.uturn.backward"
        case .punctuation: "ellipsis"
        case .style: "sparkle"
        case .possibleRecognitionError: "ear"
        }
    }

    private var color: Color {
        switch kind {
        case .grammar, .vocabulary, .slip: uncertain ? Color(hex: 0xB0B8C8) : Color(hex: 0xFF8A65)
        case .style: Color(hex: 0x8FB4FF)
        case .possibleRecognitionError, .punctuation: Color(hex: 0xB0B8C8)
        }
    }
}

struct CardButtonStyle: ButtonStyle {
    var ink: Bool
    var prominent = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle((ink ? Color.white : Color.primary).opacity(configuration.isPressed ? 0.18 : 0.1))))
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(ink ? Color.white.opacity(0.9) : Color.primary))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Capsule())
    }
}

struct CapsuleBars: View {
    let model: CapsuleModel
    var tint: Color
    var reduceMotion: Bool
    var scale: CGFloat = 1

    var body: some View {
        let animating = model.display == .processing && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: CapsuleMetrics.barSpacing * scale) {
                ForEach(0..<CapsuleMetrics.barCount, id: \.self) { i in
                    Capsule()
                        .fill(tint)
                        .frame(width: CapsuleMetrics.barWidth * scale, height: height(i, t: t) * scale)
                        .shadow(color: tint.opacity(0.6 * model.glow), radius: 2.5)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: model.levels)
        }
        .frame(height: CapsuleMetrics.maxBar * scale)
    }

    private func height(_ i: Int, t: TimeInterval) -> CGFloat {
        let minH = CapsuleMetrics.minBar, maxH = CapsuleMetrics.maxBar
        switch model.display {
        case .recording:
            // Real input level: newest sample in the middle, older ones spreading outwards.
            let center = CapsuleMetrics.barCount / 2
            let age = abs(i - center)
            let level = CGFloat(model.levels[model.levels.count - 1 - min(age * 2, model.levels.count - 1)])
            let shape: CGFloat = 1 - CGFloat(age) * 0.12
            return minH + (maxH - minH) * min(1, level * shape * 1.15)
        case .processing:
            if reduceMotion { return minH + 4 }
            // A pulse travelling left to right: activity, not audio.
            let phase = t * 5.2 - Double(i) * 0.62
            let wave = (sin(phase) + 1) / 2
            return minH + (maxH - minH) * 0.55 * CGFloat(wave * wave)
        case .done, .doneElsewhere:
            return minH + 2
        default:
            return minH
        }
    }
}

private struct Shake: GeometryEffect {
    var count: Int
    var enabled: Bool
    var animatableData: CGFloat
    init(count: Int, enabled: Bool) { self.count = count; self.enabled = enabled; animatableData = CGFloat(count) }
    func effectValue(size: CGSize) -> ProjectionTransform {
        guard enabled else { return ProjectionTransform(.identity) }
        return ProjectionTransform(CGAffineTransform(translationX: 3 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// Clicks on the card work without first activating Saidright, so typing focus stays put.
final class CapsuleHostingView<Content: View>: NSHostingView<Content> {
    var onPointerInside: (() -> Void)?
    private var area: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// SwiftUI hover tracking only runs in the key window; this panel is never key, so track
    /// the pointer at the AppKit level to keep a tip open while it is being read.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(next)
        area = next
    }

    override func mouseEntered(with event: NSEvent) { super.mouseEntered(with: event); onPointerInside?() }
    override func mouseMoved(with event: NSEvent) { super.mouseMoved(with: event); onPointerInside?() }
}

/// Non-activating panel. Click-through while recording/processing; accepts clicks only while a
/// learning hint is shown, and never becomes key, so the text field keeps focus. Placement is
/// decided once per appearance, so the capsule never follows the pointer between displays.
@MainActor final class CapsuleController {
    private let panel: NSPanel
    private let model: CapsuleModel
    private let host: CapsuleHostingView<AnyView>
    private var hideWork: DispatchWorkItem?
    private var resizeWork: DispatchWorkItem?
    private var screenFrame: NSRect?
    /// Saidright usually runs in the background while you type elsewhere; macOS App Nap would
    /// then delay the capsule's timers and animations. Held only while the capsule is visible.
    private var activity: NSObjectProtocol?
    var scheme: ColorScheme = .dark { didSet { render() } }

    init(model: CapsuleModel) {
        self.model = model
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: CapsuleMetrics.panelSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        host = CapsuleHostingView(rootView: AnyView(EmptyView()))
        host.frame = NSRect(origin: .zero, size: CapsuleMetrics.panelSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        render()
        model.onVisibilityChange = { [weak self] visible in self?.setVisible(visible) }
        model.onInteractivityChange = { [weak self] interactive in self?.setInteractive(interactive) }
        model.onSurfaceSizeChange = { [weak self] size in self?.fit(size) }
        host.onPointerInside = { [weak self, weak model] in
            // Only a visible card counts; the transparent margin around it is ignored.
            guard let self, let model, model.isInteractive, let window = self.panelWindow else { return }
            let point = window.mouseLocationOutsideOfEventStream
            let size = model.surfaceSize
            let frame = window.contentView?.bounds ?? .zero
            let card = NSRect(x: (frame.width - size.width) / 2, y: model.placement == .top ? frame.height - 14 - size.height : 14, width: size.width, height: size.height)
            if card.contains(point) { model.pin() }
        }
    }

    private func render() {
        host.rootView = AnyView(CapsuleView(model: model).environment(\.capsuleScheme, scheme))
        panel.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
    }

    private func setVisible(_ visible: Bool) {
        hideWork?.cancel()
        if visible {
            if activity == nil { activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Capsule visible") }
            place(size: model.isInteractive ? CapsuleMetrics.cardPanelSize : CapsuleMetrics.panelSize, choosingScreen: true)
            panel.orderFrontRegardless()
        } else {
            // Let the exit transition play before removing the window.
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.model.display == .hidden else { return }
                self.panel.orderOut(nil)
                if let activity = self.activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
                self.panel.ignoresMouseEvents = true
                self.place(size: CapsuleMetrics.panelSize, choosingScreen: false)
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
    }

    /// Grows the panel at once for the card; shrinks it after the collapse animation.
    private var panelWindow: NSPanel? { panel }

    /// Card height follows its content (longer explanations, expanded details): grow at once,
    /// shrink after the collapse animation so nothing is clipped mid-motion.
    private func fit(_ surface: CGSize) {
        guard model.isInteractive else { return }
        let height = max(CapsuleMetrics.panelSize.height, ceil(surface.height) + 14 + 34)
        let current = panel.frame.height
        if height > current {
            resizeWork?.cancel()
            place(size: CGSize(width: CapsuleMetrics.cardPanelSize.width, height: height), choosingScreen: false)
        } else if height < current - 1 {
            resizeWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.model.isInteractive else { return }
                self.place(size: CGSize(width: CapsuleMetrics.cardPanelSize.width, height: max(height, ceil(self.model.surfaceSize.height) + 48)), choosingScreen: false)
            }
            resizeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    private func setInteractive(_ interactive: Bool) {
        resizeWork?.cancel()
        panel.ignoresMouseEvents = !interactive
        if interactive {
            place(size: CapsuleMetrics.cardPanelSize, choosingScreen: false)
        } else {
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.model.isInteractive else { return }
                self.place(size: CapsuleMetrics.panelSize, choosingScreen: false)
            }
            resizeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }
    }

    private func place(size: CGSize, choosingScreen: Bool) {
        if choosingScreen || screenFrame == nil {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
            screenFrame = screen?.visibleFrame
        }
        guard let frame = screenFrame else { return }
        let width = min(size.width, frame.width - 16)
        let x = frame.midX - width / 2
        // Bottom: the panel's bottom edge stays fixed, so a card grows upward from the capsule.
        let y = model.placement == .top ? frame.maxY - size.height : frame.minY
        panel.setFrame(NSRect(x: x, y: y, width: width, height: size.height), display: true)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
