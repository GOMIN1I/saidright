import SaywellCore
import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: UUID?
    @State private var query = ""

    private var records: [DictationRecord] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return model.history.records }
        return model.history.records.filter { $0.raw.localizedCaseInsensitiveContains(q) || $0.output.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationSplitView {
            List(records, selection: $selection) { record in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: record.modeSymbol).font(.system(size: 10))
                        Text(record.modeName).font(.system(size: 10, weight: .semibold))
                        Spacer()
                        Text(record.date, format: .dateTime.day().month().hour().minute()).font(.system(size: 10)).foregroundStyle(DS.Palette.secondaryText)
                    }
                    .foregroundStyle(DS.Palette.secondaryText)
                    Text(record.output.isEmpty ? tr("history.empty") : record.output).font(DS.Font.body).lineLimit(2)
                }
                .padding(.vertical, 2)
                .tag(record.id)
                .contextMenu {
                    Button(tr("result.copy")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(record.output, forType: .string) }
                    Button(tr("history.delete"), role: .destructive) { model.deleteRecord(record.id) }
                }
            }
            .searchable(text: $query, placement: .sidebar, prompt: tr("history.search"))
            .overlay { if records.isEmpty { ContentUnavailableView(tr("history.none"), systemImage: "clock", description: Text(tr("history.noneDetail"))) } }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            .toolbar {
                ToolbarItem {
                    Button { importAudio() } label: { Label(tr("import.button"), systemImage: "square.and.arrow.down") }
                        .help(tr("import.help"))
                        .disabled(model.isBusy)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                model.importAudio(url)
                return true
            }
        } detail: {
            if let id = selection, let record = model.history.records.first(where: { $0.id == id }) {
                HistoryDetail(record: record)
            } else {
                ContentUnavailableView(tr("history.select"), systemImage: "text.alignleft")
            }
        }
    }
}

extension HistoryView {
    func importAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importAudio(url)
        WindowRouter.show("main")
    }
}

struct HistoryDetail: View {
    var record: DictationRecord
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                HStack {
                    Label(record.modeName, systemImage: record.modeSymbol).font(DS.Font.headline)
                    Spacer()
                    Text(record.date, format: .dateTime).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText)
                }
                if let edited = record.edited {
                    ComparisonView(original: record.raw, edited: edited)
                } else {
                    Text(record.raw).font(DS.Font.reading).textSelection(.enabled)
                }
                if let note = record.editNote { Label(note, systemImage: "exclamationmark.circle").font(DS.Font.caption).foregroundStyle(DS.Palette.warning) }
                timingLine
                WrapLayout(spacing: 6) {
                    Button(tr("result.copy")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(record.output, forType: .string) }
                    if let file = record.audioFile {
                        Button(tr("result.playRecording")) { model.speech.play(Paths.recording(file)) }
                        if record.raw.isEmpty { Button(tr("history.retryRecognition")) { model.retryRecognition(record) } }
                    }
                    Button(tr("history.openInMain")) { model.open(record); WindowRouter.show("main") }
                    Button(tr("history.delete"), role: .destructive) { model.deleteRecord(record.id) }
                }
                .buttonStyle(PillButtonStyle())
                if let feedback = record.feedback {
                    Divider()
                    Text(tr("feedback.title", LanguageCatalog.info(feedback.learningLanguage)?.nativeName ?? feedback.learningLanguage)).sectionLabel()
                    if !record.transcriptConfirmed { Text(tr("feedback.unconfirmedHelp")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText) }
                    ForEach(feedback.items) { item in ReadOnlyFeedbackItem(item: item) }
                    if feedback.items.isEmpty { Text(tr("feedback.noIssues")).font(DS.Font.body).foregroundStyle(DS.Palette.secondaryText) }
                }
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: 680, alignment: .leading)
        }
    }

    private var timingLine: some View {
        let t = record.timing
        var parts: [String] = []
        if let a = t.audioDuration { parts.append(tr("history.audio", a)) }
        if let r = t.recognition { parts.append(tr("history.asr", r)) }
        if let s = t.speechToText { parts.append(tr("history.ready", s)) }
        if t.coldRecognizer { parts.append(tr("history.cold")) }
        return Text(parts.joined(separator: " · ")).font(DS.Font.mono).foregroundStyle(DS.Palette.tertiaryText)
    }
}

struct ReadOnlyFeedbackItem: View {
    var item: FeedbackItem
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(tr("kind.\(item.kind.rawValue)")).font(.system(size: 10, weight: .semibold)).foregroundStyle(DS.Palette.secondaryText)
                if let v = item.verdict { Text(tr("verdict.\(v.rawValue)")).font(.system(size: 10)).foregroundStyle(DS.Palette.tertiaryText) }
            }
            HStack { Text(item.original).strikethrough().foregroundStyle(DS.Palette.removed); Image(systemName: "arrow.right").font(.system(size: 9)); Text(item.suggestion).underline().foregroundStyle(DS.Palette.added) }
            Text(item.explanation).font(DS.Font.caption)
        }
        .padding(DS.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.readingSurface, in: RoundedRectangle(cornerRadius: DS.Radius.small))
    }
}

/// Spaced review of the person's own saved constructions.
struct PracticeView: View {
    @Environment(AppModel.self) private var model
    @State private var revealed = false
    @State private var answer = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            Text(tr("practice.title")).font(DS.Font.headline)
            Text(tr("practice.explain")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
            if let card = model.dueCards.first {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    HStack {
                        Text(LanguageCatalog.info(card.language)?.nativeName ?? card.language).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText)
                        if !card.topic.isEmpty { Text("· \(card.topic)").font(DS.Font.caption).foregroundStyle(DS.Palette.tertiaryText) }
                        Spacer()
                        Text(tr("practice.remaining", model.dueCards.count)).font(DS.Font.caption).foregroundStyle(DS.Palette.tertiaryText)
                    }
                    Text(card.prompt).font(.system(size: 17))
                    TextField(tr("practice.yourAnswer"), text: $answer).textFieldStyle(.roundedBorder).onSubmit { revealed = true }
                    if revealed {
                        HStack {
                            Text(card.answer).font(.system(size: 15, weight: .medium)).textSelection(.enabled)
                            SpeakButton(text: card.answer, language: card.language)
                        }
                        if !card.explanation.isEmpty { Text(card.explanation).font(DS.Font.caption).foregroundStyle(DS.Palette.secondaryText) }
                        if !card.source.isEmpty { Text(tr("practice.source", card.source)).font(.system(size: 10)).foregroundStyle(DS.Palette.tertiaryText).lineLimit(3) }
                        HStack {
                            ForEach(ReviewGrade.allCases, id: \.self) { g in
                                Button(tr("grade.\(g.rawValue)")) { model.grade(card, g); revealed = false; answer = "" }
                                    .buttonStyle(PillButtonStyle(prominent: g == .good))
                            }
                            Spacer()
                            Button(tr("practice.deleteCard"), role: .destructive) { model.deleteCard(card.id); revealed = false }.buttonStyle(PillButtonStyle())
                        }
                    } else {
                        Button(tr("practice.show")) { revealed = true }.buttonStyle(PillButtonStyle(prominent: true))
                    }
                }
                .padding(DS.Space.l)
                .background(DS.Palette.readingSurface, in: RoundedRectangle(cornerRadius: DS.Radius.surface))
            } else {
                ContentUnavailableView(model.history.cards.isEmpty ? tr("practice.noCards") : tr("practice.allDone"), systemImage: "checkmark.seal", description: Text(model.history.cards.isEmpty ? tr("practice.noCardsDetail") : tr("practice.allDoneDetail", model.history.cards.count)))
            }
            Spacer()
        }
        .padding(DS.Space.xl)
        .frame(minWidth: 480, minHeight: 420)
    }
}
