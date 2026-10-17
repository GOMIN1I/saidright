import SaidrightCore
import SwiftUI

/// Language help for the latest dictation. Shown only in the app, never inserted anywhere.
struct FeedbackSection: View {
    @Environment(AppModel.self) private var model
    @State private var expanded = false

    var body: some View {
        if let r = model.result {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack {
                    Label(tr("feedback.title", LanguageCatalog.info(r.learningLanguage)?.nativeName ?? r.learningLanguage), systemImage: "graduationcap")
                        .sectionLabel()
                        .lineLimit(1)
                    Spacer()
                }
                if !r.transcriptConfirmed && r.feedback != nil {
                    Text(tr("feedback.unconfirmed")).font(.system(size: 10)).foregroundStyle(DS.Palette.tertiaryText)
                        .help(tr("feedback.unconfirmedHelp"))
                }
                switch r.feedbackState {
                case .none:
                    Button(tr("result.analyse")) { model.requestFeedback(automatic: false) }.buttonStyle(PillButtonStyle())
                case .running:
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text(tr("feedback.running")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText) }
                case .skippedNoProvider:
                    Text(tr("feedback.noProvider")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText)
                case .failed(let message):
                    HStack {
                        Text(message).font(DS.Font.caption).foregroundStyle(DS.Palette.warning)
                        Button(tr("notice.action.retry")) { model.requestFeedback(automatic: false) }.buttonStyle(PillButtonStyle())
                    }
                case .ready:
                    if let feedback = r.feedback { content(feedback, r) }
                }
            }
        }
    }

    @ViewBuilder private func content(_ feedback: Feedback, _ r: SessionResult) -> some View {
        let errors = feedback.items.filter { $0.kind != .style }
        let styles = feedback.items.filter { $0.kind == .style }
        if feedback.items.isEmpty {
            Text(tr("feedback.noIssues")).font(DS.Font.body).foregroundStyle(DS.Palette.secondaryText)
        }
        let visible = expanded ? errors : Array(errors.prefix(1))
        ForEach(visible) { item in FeedbackItemView(item: item, language: feedback.learningLanguage) }
        if errors.count > 1 || !styles.isEmpty || !feedback.alternative.isEmpty {
            let hidden = errors.count - 1 + styles.count
            Button(expanded ? tr("feedback.less") : hidden > 0 ? tr("feedback.more", hidden) : tr("feedback.details")) {
                withAnimation(DS.Motion.quick) { expanded.toggle() }
            }
            .buttonStyle(.plain).font(DS.Font.caption).foregroundStyle(DS.Palette.signal)
        }
        if expanded {
            ForEach(styles) { item in FeedbackItemView(item: item, language: feedback.learningLanguage) }
            if !feedback.alternative.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("feedback.alternative")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText)
                    HStack(alignment: .top) {
                        Text(feedback.alternative).font(DS.Font.reading).textSelection(.enabled)
                        Spacer()
                        SpeakButton(text: feedback.alternative, language: feedback.learningLanguage)
                    }
                }
            }
            if let practice = feedback.practice { PracticeExercise(practice: practice, language: feedback.learningLanguage) }
        }
        if feedback.discarded > 0 {
            Text(tr("feedback.discarded", feedback.discarded)).font(.system(size: 10)).foregroundStyle(DS.Palette.tertiaryText)
        }
    }
}

struct FeedbackItemView: View {
    var item: FeedbackItem
    var language: String
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(tr("kind.\(item.kind.rawValue)"))
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(kindColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(kindColor)
                if item.uncertain {
                    Label(tr("feedback.uncertain"), systemImage: "questionmark.circle").font(.system(size: 10)).foregroundStyle(DS.Palette.secondaryText)
                }
                if !item.topic.isEmpty { Text(item.topic).font(.system(size: 10)).foregroundStyle(DS.Palette.tertiaryText) }
                Spacer()
                SpeakButton(text: item.suggestion, language: language)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.original).strikethrough().foregroundStyle(DS.Palette.removed)
                    Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(DS.Palette.tertiaryText).accessibilityLabel(tr("feedback.becomes"))
                    Text(item.suggestion).underline().foregroundStyle(DS.Palette.added)
                }
                .fixedSize()
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.original).strikethrough().foregroundStyle(DS.Palette.removed)
                    Label { Text(item.suggestion).underline().foregroundStyle(DS.Palette.added) } icon: {
                        Image(systemName: "arrow.turn.down.right").font(.system(size: 9)).foregroundStyle(DS.Palette.tertiaryText).accessibilityLabel(tr("feedback.becomes"))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .font(DS.Font.reading)
            .textSelection(.enabled)
            Text(item.explanation).font(DS.Font.body).fixedSize(horizontal: false, vertical: true)
            if !item.rule.isEmpty { Text(item.rule).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true) }
            if !item.example.isEmpty { Text("“\(item.example)”").font(DS.Font.caption.italic()).foregroundStyle(DS.Palette.secondaryText) }
            verdicts
        }
        .padding(DS.Space.m)
        .background(DS.Palette.readingSurface, in: RoundedRectangle(cornerRadius: DS.Radius.control))
        .accessibilityElement(children: .contain)
    }

    private var kindColor: Color {
        switch item.kind {
        case .grammar, .vocabulary, .slip: DS.Palette.process
        case .punctuation: DS.Palette.signal
        case .possibleRecognitionError: DS.Palette.warning
        case .style: DS.Palette.secondaryText
        }
    }

    private var verdicts: some View {
        WrapLayout(spacing: 6) {
            if item.savedForReview {
                Label(tr("feedback.saved"), systemImage: "checkmark").font(.system(size: 10)).foregroundStyle(DS.Palette.success)
            } else if item.kind != .possibleRecognitionError {
                Button(tr("feedback.save")) { model.saveForReview(item.id) }
            }
            verdictButton(.understood, tr("feedback.understood"))
            verdictButton(.keepOriginal, tr("feedback.keepMine"))
            verdictButton(.recognitionError, tr("feedback.asrError"))
        }
        .buttonStyle(PillButtonStyle())
        .font(.system(size: 10))
    }

    private func verdictButton(_ verdict: UserVerdict, _ title: String) -> some View {
        Button {
            model.setVerdict(item.verdict == verdict ? nil : verdict, for: item.id)
        } label: {
            if item.verdict == verdict { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
        .accessibilityAddTraits(item.verdict == verdict ? .isSelected : [])
    }
}

struct SpeakButton: View {
    var text: String
    var language: String
    @Environment(AppModel.self) private var model

    var body: some View {
        if SpeechService.hasVoice(for: language) {
            Button { model.speech.speak(text, languageID: language, settings: model.settings.speech) } label: {
                Image(systemName: "speaker.wave.2").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.Palette.secondaryText)
            .help(tr("feedback.listen"))
            .accessibilityLabel(tr("feedback.listen"))
        }
    }
}

/// One tiny exercise built from the person's own sentence.
struct PracticeExercise: View {
    var practice: PracticeItem
    var language: String
    @State private var answer = ""
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(practice.kind == .gap ? tr("practice.gap") : tr("practice.repair")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText)
            Text(practice.prompt).font(DS.Font.reading)
            HStack {
                TextField(tr("practice.yourAnswer"), text: $answer).textFieldStyle(.roundedBorder)
                Button(tr("practice.check")) { revealed = true }.buttonStyle(PillButtonStyle())
            }
            if revealed {
                let correct = expected.contains(normalize(answer))
                Label(correct ? tr("practice.match") : tr("practice.compare"), systemImage: correct ? "checkmark.circle" : "arrow.left.arrow.right")
                    .font(DS.Font.caption).foregroundStyle(correct ? DS.Palette.success : DS.Palette.secondaryText)
                HStack {
                    Text(practice.answer).font(DS.Font.reading).textSelection(.enabled)
                    SpeakButton(text: practice.answer, language: language)
                }
            }
        }
        .padding(DS.Space.m)
        .background(DS.Palette.readingSurface, in: RoundedRectangle(cornerRadius: DS.Radius.control))
    }

    /// Accepts the full sentence or, for gap exercises, just the missing words.
    private var expected: Set<String> {
        var result: Set<String> = [normalize(practice.answer)]
        let parts = practice.prompt.components(separatedBy: "___").map(normalize)
        let full = normalize(practice.answer)
        if parts.count == 2, full.hasPrefix(parts[0]), full.hasSuffix(parts[1]), full.count >= parts[0].count + parts[1].count {
            result.insert(String(full.dropFirst(parts[0].count).dropLast(parts[1].count)).trimmingCharacters(in: .whitespaces))
        }
        return result
    }

    private func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }.split(separator: " ").joined(separator: " ")
    }
}
