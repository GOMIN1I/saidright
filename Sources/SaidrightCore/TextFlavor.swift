import Foundation

/// How smart formatting is written for the app that receives the text. Markdown only where it
/// is shown as formatting or is the native format (notes apps, code editors, terminals);
/// everywhere else lists are written as plain text, so a message never shows "- [ ]".
public enum TextFlavor: String, Sendable {
    case markdown
    case plain

    /// Bundle ids of apps that render Markdown or edit it as their native format.
    static let markdownApps: Set<String> = [
        "md.obsidian", "notion.id", "net.shinyfrog.bear", "abnerworks.Typora", "pro.writer.mac",
        "com.lukilabs.lukiapp", "com.electron.logseq", "com.github.marktext", "com.ulyssesapp.mac",
        "com.agiletortoise.Drafts-OSX", "com.uranusjr.macdown", "com.coteditor.CotEditor",
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed",
        "com.sublimetext.4", "com.panic.Nova", "com.barebones.bbedit", "com.apple.dt.Xcode", "com.github.GitHubClient",
        "com.hnc.Discord", "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
    ]
    static let markdownPrefixes = ["com.jetbrains."]

    /// The flavor for a destination app; unknown apps get plain text. No destination (copied,
    /// kept in Saidright) keeps Markdown.
    public static func forApp(bundleID: String?) -> TextFlavor {
        guard let id = bundleID else { return .markdown }
        return markdownApps.contains(id) || markdownPrefixes.contains(where: id.hasPrefix) ? .markdown : .plain
    }
}
