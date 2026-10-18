# Visual system

## Character

An instrument, not a dashboard. The product is mostly invisible: a small capsule while you speak, which can briefly grow into a learning card, and a compact window you look at when you want to know what happened. The signature idea is **voice → text at your cursor**: the mark is a light capsule whose rising voice bars end in a text cursor that breaks the capsule's edge.

## Directions considered

| Direction | Key surfaces | Verdict |
| --- | --- | --- |
| A. Instrument (chosen) | System window backgrounds in light and dark; glass only on floating controls (mode switcher); black capsule; one signal accent; hairline sections instead of nested cards | Calm, native, legible; the capsule carries the identity |
| B. Studio dark | Forced-dark translucent window (the Govori prototype) | Looked atmospheric on one wallpaper; failed contrast on bright wallpapers and ignored the system appearance |
| C. Paper | Warm off-white reading surfaces, serif examples for language feedback | Pleasant for learning, but a second visual language inside a utility app; kept only as the idea of a calm *reading surface* for feedback |

## Tokens (`Sources/Saidright/UI/DesignSystem.swift`)

| Group | Tokens |
| --- | --- |
| Colour | `signal` #4F9DFF (recording), `process` #FF4FA3 (processing), `success`/`warning`/`danger` (system), `added`/`removed` (diff), text levels and `hairline` from system label/separator colours, `readingSurface` = text background |
| Space | 2, 4, 8, 12, 16, 24, 32 |
| Radius | 6 small, 10 control, 14 surface; capsules are true capsules |
| Type | SF Pro: 17 semibold headline, 13 body, 14 reading, 11 caption, 11 semibold uppercase section labels; SF Mono 11 for timings and diagnostics |
| Size | main window 400 pt wide; record button 60 pt; minimum hit target 28 pt |
| Motion | quick = ease-out 0.15 s; standard = spring(response 0.32, damping 0.82) |

Colour is never the only signal: states also have text, glyphs (✓, –, !, ×) or strikethrough/underline (diff).

## Capsule

| Property | Value | Note |
| --- | --- | --- |
| Body | 78 × 34 pt (prototype: 164 × 66) | widens by 14 pt when a state glyph is shown; 168 pt when showing a mode name |
| Bars | 7 × 3 pt, 3.5 pt gap, 4–18 pt tall | recording = real input level history (newest in the centre); processing = travelling pulse (activity, not audio) |
| Material | near-black body, top sheen, 0.75 pt lit edge, internal radial light in the state colour (no outer halo), small drop shadow | Increase Contrast thickens the edge; Reduce Transparency removes the inner light |
| Placement | bottom centre of the visible frame (above the Dock), or below the menu bar | screen chosen once when it appears; it never follows the pointer while visible |
| Window | borderless non-activating `NSPanel`, `.statusBar` level, all Spaces + full-screen auxiliary, ignores mouse | never takes focus or blocks clicks |

Motion:

- Entrance: scale 0.62 → 1 with opacity, spring (response 0.34, damping 0.78) ≈ 0.35 s.
- State change: spring (0.3, 0.85); colour crossfades; glyph scales in.
- Exit: scale → 0.86 with fade; the panel is removed after 0.35 s.
- Terminal states linger: done 0.55 s, cancelled 0.35 s, no speech 1.3 s, error 2.2 s — errors never look like endless processing.
- Hold-to-talk shows the capsule only after 220 ms so an accidental ⌘ press leaves no flicker.
- Reduce Motion (system or app setting): opacity fades only; processing bars stand still.
- A press ignored while busy gives a short horizontal shake.

The capsule's timeline only runs while processing is visible; recording bars redraw only when a new level arrives.

## Record control

The main window's record button is the capsule itself: the same black body and bars, 84 × 44 pt, driven by the same state (resting voice shape → live level in blue → travelling pulse in pink), set in a Liquid Glass bezel. The window, the floating capsule and the app icon therefore share one object.

## Liquid Glass

Used only where it helps: the header (mode switcher and settings button share one `GlassEffectContainer`), the record control's bezel, and (`glassEffect(.regular.interactive())` on macOS 26+, `.regularMaterial` before that, an opaque control background with a hairline when Reduce Transparency is on). Reading surfaces (results, feedback, settings groups) are opaque.

## Capsule-centred learning (0.4)

Sequence: recording → processing → delivered (text already inserted) → optional learning hint → gone. The hint never delays insertion: feedback is requested after delivery and shown only if no newer session is visible.

| Element | Decision |
| --- | --- |
| Card | 372 pt wide, 20 pt continuous corners, grows upward from the bottom capsule (downward for top placement). The same surface morphs from capsule to card on a spring (response 0.42, damping 0.80; gentle 0.46/0.92; reduced = 0.18 s fade) |
| Content order | kind badge (“Grammar”, “Word choice”, “Style option · not an error”, “Maybe misheard”) → original struck through → correction in semibold → one friendly explanation → actions. Details (contrast pair, tip, example) open in place with “Why?” |
| Actions | Why?/Less, Practise later, **Got it** (primary); “Mine was right” / “I said it right” as a quieter link inside details |
| Persistence | 7 s / 15 s / until closed; hovering or clicking pins it; a new recording replaces it instantly |
| Window | non-activating panel, never key; accepts clicks (first mouse) only while a hint is shown, click-through otherwise; resized to the card and back after the collapse animation |
| What appears | important = one confirmed grammar/word-choice/slip error; broader = plus style options; mishearings and unsure points only when enabled; punctuation never; nothing at all for correct text |
| Presentation options | card, subtle marker (“Tip · 2”, click to open), or window only |

## Materials and appearance

- **Glass** (default on macOS 26+): native `glassEffect(.regular.tint(state colour))`; the card uses a fainter tint and follows the window theme. Before macOS 26: `.regularMaterial`.
- **Ink**: the restrained near-black body with lit edge and internal light; the card is a dark reading surface. Reduce Transparency always gives an opaque body with a visible border.
- Palettes are coordinated triples (recording / processing / done): Signal, Ember, Aurora, Graphite; earlier custom colours are kept as “Custom”. States also differ by glyph and motion, never by colour alone.
- Size presets scale the capsule metrics (0.88 / 1 / 1.18), not the card text.
- Motion presets: Lively, Gentle (no overshoot), Minimal (fades). System Reduce Motion overrides all.

## Identity

The mark (`Sources/Saidright/UI/Branding.swift`, `AppIconArt`) is drawn once in SwiftUI and rendered to every size by `scripts/make-icon.sh`: a deep-indigo squircle, a warm-white capsule, three rising blue bars, and a coral I-beam cursor that crosses the capsule's edge with a thin cut so both shapes stay crisp. Variants: Standard, Light (indigo capsule on warm paper), Graphite (monochrome). At 16 px it reads as a capsule with a vertical stroke. The menu bar template repeats the outline, two bars and the cursor.

macOS limits: a signed app cannot switch its Finder/Launchpad icon by theme through a supported API. Saidright changes only the Dock icon while running (`NSApp.applicationIconImage`). Automatic light/dark/tinted icons need an Icon Composer `.icon` compiled by Xcode's `actool`; the SwiftPM build here produces `.icns`, so that is a follow-up.

## Brand colour (0.7)

The windows carry the icon's colours instead of plain greys (`DS.Brand`, `Surface`, `.brandWindow(_:)` in `DesignSystem.swift`). Settings → Appearance → Window colour: **Saidright** (default) or **System**.

| Token | Light | Dark | Source |
| --- | --- | --- | --- |
| canvas (window) | #F2F4FB | #0E1430 | icon tile, lightened / deepened |
| sidebar | #E8ECF8 | #0A0F26 | |
| card (settings groups) | #FFFFFF | #171F40 | |
| card edge | indigo 8 % | white 8 % | |
| accent (controls, prominent buttons) | #3D6BFF | #5E7DFF | voice bars |
| tile gradient (hero surfaces) | #2A3A78 → #111833 | same | icon tile, top → bottom |
| coral | #FF5A4E | same | cursor; used only in the onboarding hero light and the learning card's primary button |

The theme picker (System / Light / Dark) still chooses the appearance; the brand colours resolve per appearance, so “System” means airy indigo-white by day and deep indigo by night. Capsule palettes are independent of the window colour.

**Living surfaces (0.7).** `AuroraBackground` (DesignSystem.swift) is the window background with the Saidright colour: a three-stop base (dark #18225A → #0E1430 → #0B1028; light #F6F7FE → #E7EBF9) and three radial lights — voice blue #3D6BFF, violet #7B5CFF, rose #FF5257 (light mode: #8FB0FF, #C4B5FF, #FF8E92) — screen-blended at night, drifting and swelling on 17–23 s Core Animation loops. `LivingHalo` (MainView.swift) is a conic gradient of the same lights turning every 9 s (faster while busy) behind the record control, masked to a soft ring; brightness 0.45 idle, 0.65 hover, 0.8 busy, 1 recording. The Ink capsule has `LivingLight`: its state colour drifts inside the body with a faint passing sheen. Measured: the same CPU with the aurora on and off (QA instance, Settings + main window). Reduce Motion stops everything; Reduce Transparency removes the lights. QA snapshots (`cacheDisplay`) do not apply SwiftUI masks to AppKit layers: check the halo on a real screen.

**Introduction.** First launch opens only the introduction (macOS 15+: `defaultLaunchBehavior`; macOS 14: the main window hides itself), centred, fading up while the card settles from 96.5 % scale. The welcome step has a 200 pt hero in the tile gradient with two slow screen-blended lights (voice blue, coral) and the floating mark; steps slide 36 pt in the direction of travel; Finish fades the introduction out (0.3 s) and the main window in (0.4 s). Reduce Motion: fades only, still hero.

## Product page (0.7)

`site/index.html`, no dependencies. Onest (OFL) served from the site. Sections alternate night indigo and mist white; the capsule on the page reproduces the app's bars (7 × 3 px, 4–18 px, same recording/processing formulas) and the done state (low bars plus the bold check mark to their right, never a centred tick). Screenshots: dark appearance, Saidright window colour, one set per page language (`site/assets/shots/{en,ru}`), produced with the QA snapshot hooks.

## Verification still to do

Real-window review on bright/dark wallpapers, inactive windows, larger text, German long strings and Chinese glyphs in every screen, VoiceOver pass, and a screen recording of the capsule. See `docs/TESTING.md` for what has been checked so far.
