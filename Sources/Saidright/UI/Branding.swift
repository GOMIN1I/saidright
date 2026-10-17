import AppKit
import SaidrightCore
import SwiftUI

/// The Saidright mark: a light capsule (the on-screen capsule) holding two voice bars that end in
/// a text cursor breaking out of the capsule — speech becoming text where you type.
/// One parametric drawing feeds the app icon, Dock variants, onboarding and settings previews,
/// so every size is rendered from the same geometry (see `IconRenderer`).
struct AppIconArt: View {
    var variant: AppIconVariant = .standard
    /// Draw the squircle tile. Off for the glyph alone (e.g. on a coloured surface).
    var tile = true

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                if tile {
                    // macOS icon grid: 824 pt body on a 1024 canvas, continuous corners.
                    let body = RoundedRectangle(cornerRadius: s * 0.1816, style: .continuous)
                    body.fill(background)
                        .overlay(body.strokeBorder(rim, lineWidth: max(0.5, s * 0.004)))
                        .frame(width: s * 0.805, height: s * 0.805)
                        .shadow(color: .black.opacity(variant == .light ? 0.18 : 0.32), radius: s * 0.022, y: s * 0.012)
                }
                Glyph(variant: variant, size: s * (tile ? 1 : 1.25))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }

    private var background: LinearGradient {
        switch variant {
        case .standard: LinearGradient(colors: [Color(hex: 0x2A3A78), Color(hex: 0x111833)], startPoint: .top, endPoint: .bottom)
        case .light: LinearGradient(colors: [Color(hex: 0xFBF9F5), Color(hex: 0xE6E1D6)], startPoint: .top, endPoint: .bottom)
        case .mono: LinearGradient(colors: [Color(hex: 0x3A3A3D), Color(hex: 0x1B1B1D)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var rim: Color { variant == .light ? .black.opacity(0.08) : .white.opacity(0.12) }

    struct Glyph: View {
        /// Separate layers for Icon Composer, which tints and lights each one (dark/tinted icons).
        enum Layer { case all, capsule, marks }
        var variant: AppIconVariant
        var size: CGFloat
        var layer: Layer = .all

        var body: some View {
            let s = size
            let pillW = s * 0.58, pillH = s * 0.25
            let barW = s * 0.046
            let marks = layer != .capsule
            let cursor = Cursor(width: barW, height: s * 0.37, serif: s * 0.13, serifHeight: barW * 0.82)
            ZStack {
                if layer != .marks {
                    Capsule()
                        .fill(pill)
                        .frame(width: pillW, height: pillH)
                        .shadow(color: .black.opacity(variant == .light || layer == .capsule ? 0.10 : 0.25), radius: s * 0.012, y: s * 0.006)
                }
                // A rising voice that ends in the text cursor; the cursor alone breaks the capsule's edge.
                HStack(alignment: .center, spacing: s * 0.04) {
                    Capsule().fill(marks ? voice.opacity(0.75) : .clear).frame(width: barW, height: s * 0.05)
                    Capsule().fill(marks ? voice : .clear).frame(width: barW, height: s * 0.095)
                    Capsule().fill(marks ? voice : .clear).frame(width: barW, height: s * 0.145)
                    Group {
                        switch layer {
                        case .all:
                            // A thin cut where the cursor crosses the capsule keeps both shapes crisp.
                            cursor.fill(accent).background { cursor.stroke(gap, lineWidth: barW * 0.9) }
                        case .marks:
                            cursor.fill(accent)
                        case .capsule:
                            // The cut is a real hole in the capsule layer, so it works in any tint.
                            ZStack { cursor.fill(.black); cursor.stroke(.black, lineWidth: barW * 0.9) }.blendMode(.destinationOut)
                        }
                    }
                    .padding(.leading, s * 0.012)
                }
                .offset(x: s * 0.035)
            }
            .compositingGroup()

            .frame(width: s, height: s)
        }

        private var pill: Color {
            switch variant {
            case .standard: Color(hex: 0xF6F3EC)
            case .light: Color(hex: 0x182352)
            case .mono: Color(white: 0.96)
            }
        }

        private var voice: Color {
            switch variant {
            case .standard: Color(hex: 0x3D6BFF)
            case .light: Color(hex: 0x8FB0FF)
            case .mono: Color(white: 0.22)
            }
        }

        private var accent: Color {
            switch variant {
            case .standard: Color(hex: 0xFF5A4E)
            case .light: Color(hex: 0xFF6A57)
            case .mono: Color(white: 0.96)
            }
        }

        /// Colour of the cut around the cursor: the tile colour where it crosses the capsule.
        private var gap: Color {
            switch variant {
            case .standard: Color(hex: 0x1D2852)
            case .light: Color(hex: 0xEFEBE3)
            case .mono: Color(hex: 0x2A2A2D)
            }
        }
    }

    /// An I-beam: a rounded stem with short rounded serifs at both ends.
    struct Cursor: Shape {
        var width: CGFloat
        var height: CGFloat
        var serif: CGFloat
        var serifHeight: CGFloat

        func path(in rect: CGRect) -> Path {
            var p = Path()
            let midX = rect.midX, midY = rect.midY
            let stem = CGRect(x: midX - width / 2, y: midY - height / 2, width: width, height: height)
            p.addRoundedRect(in: stem, cornerSize: CGSize(width: width / 2, height: width / 2))
            for y in [stem.minY, stem.maxY - serifHeight] {
                p.addRoundedRect(in: CGRect(x: midX - serif / 2, y: y, width: serif, height: serifHeight), cornerSize: CGSize(width: serifHeight / 2, height: serifHeight / 2))
            }
            return p
        }

        func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize { CGSize(width: serif, height: height) }
    }
}

/// Small mark used in windows (onboarding, about).
struct AppMark: View {
    var body: some View { AppIconArt(variant: .standard) }
}

@MainActor enum IconRenderer {
    static func image(_ variant: AppIconVariant, pixels: CGFloat) -> NSImage? {
        let renderer = ImageRenderer(content: AppIconArt(variant: variant).frame(width: pixels, height: pixels))
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer.nsImage
    }

    /// Applies the chosen Dock icon while Saidright runs. Finder, Launchpad and the app switcher
    /// before launch always show the bundle icon; macOS offers no supported API to change that.
    static func applyDockIcon(_ variant: AppIconVariant) {
        NSApp.applicationIconImage = variant == .standard ? nil : image(variant, pixels: 512)
    }

    /// Writes the Icon Composer layers (1024 px, transparent) used by Resources/AppIcon.icon.
    static func writeIconLayers(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, layer) in [("capsule", AppIconArt.Glyph.Layer.capsule), ("marks", .marks)] {
            let view = AppIconArt.Glyph(variant: .standard, size: 1024 * 1.25, layer: layer).frame(width: 1024, height: 1024)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            renderer.isOpaque = false
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { continue }
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }

    /// Writes an .iconset (all macOS sizes) for `iconutil`. Used by scripts/make-icon.sh.
    static func writeIconset(to directory: URL, variant: AppIconVariant) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = CGFloat(base * scale)
                guard let image = image(variant, pixels: px), let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { continue }
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try png.write(to: directory.appendingPathComponent(name))
            }
        }
    }
}

/// Template image for the menu bar: the capsule outline with two bars and the cursor,
/// drawn on whole points so it stays crisp at 16–18 pt.
enum MenuBarIcon {
    static func image(recording: Bool) -> NSImage {
        let size = NSSize(width: 24, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let pillRect = NSRect(x: 1.5, y: 3.5, width: 21, height: 9)
            let pill = NSBezierPath(roundedRect: pillRect, xRadius: 4.5, yRadius: 4.5)
            pill.lineWidth = 1.3
            NSColor.black.setStroke()
            NSColor.black.setFill()
            if recording { pill.fill() } else { pill.stroke() }
            func shape(_ r: NSRect) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: min(r.width, r.height) / 2, yRadius: min(r.width, r.height) / 2) }
            let bars = [shape(NSRect(x: 6.6, y: 6.75, width: 1.6, height: 2.5)), shape(NSRect(x: 10.0, y: 5.75, width: 1.6, height: 4.5))]
            // The cursor crosses the outline, top and bottom, as in the app icon.
            let cursor = [shape(NSRect(x: 14.4, y: 1, width: 1.6, height: 14)), shape(NSRect(x: 12.9, y: 1, width: 4.6, height: 1.6)), shape(NSRect(x: 12.9, y: 13.4, width: 4.6, height: 1.6))]
            if recording {
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                bars.forEach { $0.fill() }
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                // Knock a gap around the cursor so it reads against the filled pill.
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                shape(NSRect(x: 13.4, y: 2, width: 3.6, height: 12)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                cursor.forEach { $0.fill() }
            } else {
                bars.forEach { $0.fill() }
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                shape(NSRect(x: 13.4, y: 2.6, width: 3.6, height: 10.8)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                cursor.forEach { $0.fill() }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
