import SaidrightCore
import SwiftUI

/// The latest dictation: delivered text, what changed and why, and optional language help.
struct ResultView: View {
    @Environment(AppModel.self) private var model
    @State private var showComparison = false
    @State private var editingTranscript = false
    @State private var draft = ""

    var body: some View {
        if let r = model.result {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack(spacing: DS.Space.s) {
                    Text(tr("result.title")).sectionLabel()
                    Spacer()
                    if let outcome = r.outcome { DeliveryLabel(outcome: outcome) }
                }

                if editingTranscript {
                    TranscriptEditor(draft: $draft, onCancel: { editingTranscript = false }, onConfirm: {
                        model.confirmTranscript(draft)
                        editingTranscript = false
                    })
                } else if showComparison, r.edited != nil || r.output != r.raw {
                    ComparisonView(original: r.raw, edited: r.output)
                } else {
                    Text(r.output)
                        .font(DS.Font.reading)
                        .textSelection(.enabled)
                        .lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !r.editIssues.isEmpty, r.editFailure == nil {
                    Label(tr("result.checkNegation"), systemImage: "exclamationmark.circle").font(DS.Font.caption).foregroundStyle(DS.Palette.warning)
                }

                actions(r)

                if r.learningLevel != .off || r.feedback != nil || r.feedbackState != .none {
                    Divider()
                    FeedbackSection()
                }
            }
        }
    }

    @ViewBuilder private func actions(_ r: SessionResult) -> some View {
        HStack(spacing: DS.Space.s) {
            Button { model.copyResult() } label: { Label(tr("result.copy"), systemImage: "doc.on.doc") }
            if let destination = r.destination, !(r.outcome?.isInsertion ?? false) {
                Button { model.insertAgain() } label: { Label(tr("result.insertInto", Self.shortName(destination.appName)), systemImage: "text.insert") }
            }
            if r.edited != nil {
                Button { withAnimation(DS.Motion.quick) { showComparison.toggle() } } label: {
                    Label(showComparison ? tr("result.hideChanges") : tr("result.showChanges"), systemImage: "arrow.left.arrow.right")
                }
            }
            Spacer(minLength: 0)
            Menu {
                if r.edited != nil { Button(tr("result.useOriginal")) { model.useRawTranscript() } }
                Button(tr("result.editTranscript")) { draft = r.raw; editingTranscript = true }
                if let file = r.audioFile { Button(tr("result.playRecording")) { model.speech.play(Paths.recording(file)) } }
                if r.edited == nil { Button(tr("result.runEditor")) { model.retryEdit() } }
                if r.feedback == nil && r.feedbackState != .running { Button(tr("result.analyse")) { model.requestFeedback(automatic: false) } }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel(tr("result.more"))
        }
        .buttonStyle(PillButtonStyle())
    }
}

struct DeliveryLabel: View {
    var outcome: DeliveryOutcome

    var body: some View {
        Label(AppModel.describe(outcome), systemImage: icon)
            .font(DS.Font.caption)
            .foregroundStyle(color)
            .lineLimit(2)
            .multilineTextAlignment(.trailing)
    }

    private var icon: String {
        switch outcome {
        case .insertedVerified: "checkmark.circle.fill"
        case .insertedUnverified: "checkmark.circle"
        case .kept: "tray"
        case .copied(let reason): reason == .modeSetting || reason == .startedInApp ? "doc.on.clipboard" : "exclamationmark.circle"
        }
    }

    private var color: Color {
        switch outcome {
        case .insertedVerified: DS.Palette.success
        case .insertedUnverified, .kept: DS.Palette.secondaryText
        case .copied(let reason): reason == .modeSetting || reason == .startedInApp ? DS.Palette.secondaryText : DS.Palette.warning
        }
    }
}

/// Original transcript and edited text, with removed and added words marked by
/// strikethrough/underline as well as colour.
struct ComparisonView: View {
    var original: String
    var edited: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(tr("result.changes")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText)
            Text(attributed)
                .font(DS.Font.reading)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.m) {
                Label(tr("result.legendRemoved"), systemImage: "strikethrough").foregroundStyle(DS.Palette.removed)
                Label(tr("result.legendAdded"), systemImage: "underline").foregroundStyle(DS.Palette.added)
            }
            .font(.system(size: 10))
        }
        .padding(DS.Space.m)
        .background(DS.Palette.readingSurface, in: RoundedRectangle(cornerRadius: DS.Radius.control))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("result.accessibilityChanges", original, edited))
    }

    private var attributed: AttributedString {
        var out = AttributedString()
        var previousRemoved = false
        for segment in TextDiff.compare(original, edited) {
            // Keep a removed word and its replacement visually apart.
            if previousRemoved, case .added = segment { out += AttributedString(" ") }
            if case .removed = segment { previousRemoved = true } else { previousRemoved = false }
            switch segment {
            case .same(let s): out += AttributedString(s)
            case .removed(let s):
                var a = AttributedString(s)
                a.strikethroughStyle = .single
                a.foregroundColor = DS.Palette.removed
                out += a
            case .added(let s):
                var a = AttributedString(s)
                a.underlineStyle = .single
                a.foregroundColor = DS.Palette.added
                out += a
            }
        }
        return out
    }
}

struct TranscriptEditor: View {
    @Binding var draft: String
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(tr("result.editHint")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText)
            TextEditor(text: $draft)
                .font(DS.Font.reading)
                .frame(minHeight: 70, maxHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(DS.Palette.readingSurface, in: RoundedRectangle(cornerRadius: DS.Radius.small))
            HStack {
                Spacer()
                Button(tr("common.cancel"), action: onCancel).buttonStyle(PillButtonStyle())
                Button(tr("result.confirmTranscript"), action: onConfirm).buttonStyle(PillButtonStyle(prominent: true))
            }
        }
    }
}

extension ResultView {
    /// App names can be long ("UserNotificationCenter"); the buttons keep the window's width.
    static func shortName(_ name: String) -> String {
        name.count > 18 ? String(name.prefix(17)) + "…" : name
    }
}
