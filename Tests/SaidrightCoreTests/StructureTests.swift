import Foundation
import Testing
@testable import SaidrightCore

@Suite struct SmartStructureTests {
    private func mode(_ level: CleanupLevel, smart: Bool = true) -> Mode {
        var m = ModePresets.starter(names: [:], spoken: ["ru", "en"])[0]
        m.cleanup = level
        m.rules.smartStructure = smart
        return m
    }

    @Test func onlyListLikeTextIsWorthASecondRequest() {
        #expect(SmartStructure.worthAsking("Купить молоко, написать Арсену, закончить монтаж и отправить преподавателю работу."))
        #expect(SmartStructure.worthAsking("The meeting moved to Wednesday at three. Can you bring the numbers, the slides and the budget?"))
        #expect(SmartStructure.worthAsking("Сначала открой проект, потом запусти тесты, затем отправь отчёт."))
        #expect(!SmartStructure.worthAsking("Я думаю, нам стоит перенести созвон на завтра."))
        #expect(!SmartStructure.worthAsking("Ok, thanks!"))
    }

    @Test func spokenTableRequestIsRecognised() {
        #expect(SmartStructure.requestsTable("Привет, нужна таблица с тремя столбцами: ChatGPT, Claude и Gemini."))
        #expect(SmartStructure.requestsTable("Make a table with two columns, name and price."))
        #expect(SmartStructure.requestsTable("Mach eine Tabelle mit drei Spalten."))
        #expect(SmartStructure.requestsTable("做一个表格，三列。"))
        #expect(!SmartStructure.requestsTable("Я думаю, нам стоит перенести созвон на завтра."))
        #expect(SmartStructure.worthAsking("Нужна таблица: имя и цена."))
        #expect(SmartStructure.withoutTableRequest("Привет! Нужна таблица с тремя столбцами: ChatGPT, Claude и Gemini. Скорость высокая.") == "привет с chatgpt claude и gemini скорость высокая")
    }

    @Test func spokenTableKeepsGreetingAndDropsTheRequest() throws {
        let source = "Привет, нужна таблица с тремя столбцами: ChatGPT, Claude и Gemini. Сравнение по критериям. Скорость: у ChatGPT высокая, у Claude средняя, у Gemini высокая. Цена: 20, 20 и 20 долларов. Спасибо!"
        let json = #"{"format":"structured","title":"","blocks":[{"type":"paragraph","text":"Привет, нужна таблица:","items":[],"rows":[]},{"type":"table","text":"","items":[],"rows":[["Критерий","ChatGPT","Claude","Gemini"],["Скорость","Высокая","Средняя","Высокая"],["Цена","20 $","20 $","20 $"]]},{"type":"paragraph","text":"Спасибо!","items":[],"rows":[]}]}"#
        let layout = try #require(SmartStructure.parse(json, source: source, allowTitle: true))
        #expect(SmartStructure.render(title: layout.title, blocks: layout.blocks) == "Привет, нужна таблица:\n\n| Критерий | ChatGPT | Claude | Gemini |\n| --- | --- | --- | --- |\n| Скорость | Высокая | Средняя | Высокая |\n| Цена | 20 $ | 20 $ | 20 $ |\n\nСпасибо!")
        // Values that were never dictated are still rejected.
        let invented = json.replacingOccurrences(of: "Средняя", with: "Медленная")
        #expect(SmartStructure.parse(invented, source: source, allowTitle: true) == nil)
        // A greeting placed after the table moves back in front of it.
        let late = #"{"format":"structured","title":"","blocks":[{"type":"table","text":"","items":[],"rows":[["","ChatGPT","Claude","Gemini"],["Скорость","высокая","средняя","высокая"],["Цена","20 $","20 $","20 $"]]},{"type":"paragraph","text":"Привет.","items":[],"rows":[]},{"type":"paragraph","text":"Спасибо!","items":[],"rows":[]}]}"#
        let moved = try #require(SmartStructure.parse(late, source: source, allowTitle: true))
        #expect(moved.blocks.map(\.kind) == [.paragraph, .table, .paragraph])
        #expect(moved.blocks.first?.text == "Привет.")
        // A dropped greeting is restored from the dictation.
        #expect(SmartStructure.tableIntroduction(source) == "Привет, нужна таблица:")
        #expect(SmartStructure.tableIntroduction("Сделай таблицу с двумя столбцами: имя и цена.") == nil)
        let noGreeting = json.replacingOccurrences(of: #"{"type":"paragraph","text":"Привет, нужна таблица:","items":[],"rows":[]},"#, with: "")
        let restored = try #require(SmartStructure.parse(noGreeting, source: source, allowTitle: true))
        #expect(restored.blocks.first?.text == "Привет, нужна таблица:")
        // Content outside the request may not disappear.
        let dropped = json.replacingOccurrences(of: #"["Цена","20 $","20 $","20 $"]"#, with: "")
            .replacingOccurrences(of: "],]", with: "]]")
        #expect(SmartStructure.parse(dropped, source: source, allowTitle: true) == nil)
    }

    @Test func checklistIsRenderedFromBlocks() throws {
        let source = "Купить молоко, написать Арсену, закончить монтаж и отправить преподавателю работу."
        let json = #"{"format":"structured","title":"Задачи","blocks":[{"type":"checklist","text":"","items":["Купить молоко","Написать Арсену","Закончить монтаж","Отправить работу преподавателю"],"rows":[]}]}"#
        let layout = try #require(SmartStructure.parse(json, source: source, allowTitle: true))
        #expect(SmartStructure.render(title: layout.title, blocks: layout.blocks) == "## Задачи\n\n- [ ] Купить молоко\n- [ ] Написать Арсену\n- [ ] Закончить монтаж\n- [ ] Отправить работу преподавателю")
        // Light level: no invented title.
        #expect(SmartStructure.parse(json, source: source, allowTitle: false)?.title == "")
    }

    @Test func introSentenceAndBulletsAndTable() throws {
        let source = "The meeting moved to Wednesday. Can you bring the numbers, the slides and the budget? Anna has 3 slides, Ben has 5 slides."
        let json = #"{"format":"structured","title":"","blocks":[{"type":"paragraph","text":"The meeting moved to Wednesday. Can you bring:","items":[],"rows":[]},{"type":"bullets","text":"","items":["The numbers","The slides","The budget"],"rows":[]},{"type":"table","text":"","items":[],"rows":[["Anna","Ben"],["3 slides","5 slides"]]}]}"#
        let layout = try #require(SmartStructure.parse(json, source: source, allowTitle: true))
        #expect(SmartStructure.render(title: layout.title, blocks: layout.blocks) == "The meeting moved to Wednesday. Can you bring:\n\n- The numbers\n- The slides\n- The budget\n\n| Anna | Ben |\n| --- | --- |\n| 3 slides | 5 slides |")
    }

    @Test func tableDictatedRowByRow() throws {
        let source = "Мне нужна таблица с тремя столбцами: ChatGPT, Claude и Gemini. В первой строке цена: 20 долларов, 20 долларов и 20 долларов. Во второй строке контекст: 128 тысяч, 200 тысяч и миллион."
        let json = #"{"format":"structured","title":"","blocks":[{"type":"paragraph","text":"Мне нужна таблица:","items":[],"rows":[]},{"type":"table","text":"","items":[],"rows":[["","ChatGPT","Claude","Gemini"],["Цена","20 долларов","20 долларов","20 долларов"],["Контекст","128 тысяч","200 тысяч","миллион"]]}]}"#
        let layout = try #require(SmartStructure.parse(json, source: source, allowTitle: true))
        #expect(SmartStructure.render(title: layout.title, blocks: layout.blocks).contains("| Цена | 20 долларов | 20 долларов | 20 долларов |"))
    }

    @Test func tableOfColumnNamesOnly() throws {
        let source = "Составь таблицу со столбцами Grok, Gemini и Copilot"
        let json = #"{"format":"structured","title":"","blocks":[{"type":"paragraph","text":"Составь таблицу:","items":[],"rows":[]},{"type":"table","text":"","items":[],"rows":[["Grok","Gemini","Copilot"]]}]}"#
        let layout = try #require(SmartStructure.parse(json, source: source, allowTitle: true))
        #expect(SmartStructure.render(title: layout.title, blocks: layout.blocks) == "Составь таблицу:\n\n| Grok | Gemini | Copilot |\n| --- | --- | --- |")
    }

    @Test func comparisonByCriteriaWithoutValues() throws {
        let source = "Составь таблицу со столбцами Grok, Gemini и Copilot где будет проводиться сравнение по критериям цена, производительность, качество"
        let json = #"{"format":"structured","title":"","blocks":[{"type":"table","text":"","items":[],"rows":[["","Grok","Gemini","Copilot"],["цена","","",""],["производительность","","",""],["качество","","",""]]}]}"#
        let layout = try #require(SmartStructure.parse(json, source: source, allowTitle: true))
        #expect(SmartStructure.render(title: layout.title, blocks: layout.blocks).contains("| Производительность |  |  |  |"))
    }

    @Test func shortTableRequestKeepsItsIntroduction() throws {
        for (source, json) in [
            ("Создай таблицу сравнения чаджи 5 и клоуду.", #"{"format":"structured","title":"","blocks":[{"type":"paragraph","text":"Создай таблицу сравнения:","items":[],"rows":[]},{"type":"table","text":"","items":[],"rows":[["","чаджи 5","клоуду"]]}]}"#),
            ("Создай таблицу сравнения со столбцами JGPD, Gemini, Compile", #"{"format":"structured","title":"","blocks":[{"type":"paragraph","text":"Создай таблицу сравнения:","items":[],"rows":[]},{"type":"table","text":"","items":[],"rows":[["JGPD","Gemini","Compile"]]}]}"#),
        ] {
            #expect(SmartStructure.parse(json, source: source, allowTitle: true) != nil, "\(source)")
        }
    }

    @Test func tableRequestInOwnWords() throws {
        let source = "Создай таблицу со столбцами ChatGPT, Gemini, Copilot, где будут такие строчки как цена, качество, производительность."
        let json = #"{"format":"structured","title":"","blocks":[{"type":"table","text":"","items":[],"rows":[["","ChatGPT","Gemini","Copilot"],["Цена","","",""],["Качество","","",""],["Производительность","","",""]]}]}"#
        #expect(SmartStructure.parse(json, source: source, allowTitle: true) != nil)
        // A greeting and a deadline around the request still have to survive.
        let wrapped = "Привет! " + source + " Нужно к пятнице."
        let dropped = #"{"format":"structured","title":"","blocks":[{"type":"paragraph","text":"Привет!","items":[],"rows":[]},{"type":"table","text":"","items":[],"rows":[["","ChatGPT","Gemini","Copilot"],["Цена","","",""]]}]}"#
        #expect(SmartStructure.parse(dropped, source: wrapped, allowTitle: true) == nil)
    }

    @Test func plainTextForAppsWithoutMarkdown() throws {
        #expect(TextFlavor.forApp(bundleID: "md.obsidian") == .markdown)
        #expect(TextFlavor.forApp(bundleID: "com.microsoft.VSCode") == .markdown)
        #expect(TextFlavor.forApp(bundleID: "ru.keepcoder.Telegram") == .plain)
        #expect(TextFlavor.forApp(bundleID: "com.anthropic.claudefordesktop") == .plain)
        #expect(TextFlavor.forApp(bundleID: nil) == .markdown)
        let blocks = [
            SmartStructure.Block(kind: .paragraph, text: "Нужно сделать:"),
            SmartStructure.Block(kind: .checklist, items: ["Позвонить врачу", "Оплатить интернет"]),
            SmartStructure.Block(kind: .bullets, items: ["Молоко", "Хлеб"]),
            SmartStructure.Block(kind: .heading, text: "Работа"),
        ]
        #expect(SmartStructure.render(title: "", blocks: blocks, flavor: .plain) == "Нужно сделать:\n\n1. Позвонить врачу\n2. Оплатить интернет\n\n• Молоко\n• Хлеб\n\nРабота")
        #expect(SmartStructure.render(title: "", blocks: blocks).contains("- [ ] Позвонить врачу"))
        #expect(IntegrityReport.withoutMarkdown("• Молоко\n1. Хлеб") == "Молоко Хлеб")
    }

    @Test func tableThatDropsAColumnIsStillRejected() {
        let source = "Составь таблицу со столбцами Grok, Gemini и Copilot где будет проводиться сравнение по критериям цена, производительность, качество"
        let json = #"{"format":"structured","title":"","blocks":[{"type":"table","text":"","items":[],"rows":[["","Grok","Gemini"],["цена","",""]]}]}"#
        #expect(SmartStructure.parse(json, source: source, allowTitle: true) == nil)
    }

    @Test func mixedFieldsFromSmallModelsAreRepaired() throws {
        let source = "Hey, so the meeting's moved to Wednesday at three. Can you bring the numbers, the slides and the budget?"
        let json = #"{"blocks":[{"rows":[],"text":"Hey, so the meeting's moved to Wednesday at three. Can you bring the numbers, the slides and the budget?","items":["the numbers","the slides","the budget"],"type":"bullets"}],"format":"structured","title":""}"#
        let layout = try #require(SmartStructure.parse(json, source: source, allowTitle: true))
        #expect(SmartStructure.render(title: layout.title, blocks: layout.blocks) == "Hey, so the meeting's moved to Wednesday at three. Can you bring:\n\n- The numbers\n- The slides\n- The budget")
    }

    @Test func droppedContentKeepsTheEdit() {
        let source = "Hey, so the meeting's moved to Wednesday at three. Can you bring the numbers, the slides and the budget?"
        let json = #"{"format":"structured","title":"","blocks":[{"type":"bullets","text":"","items":["The numbers","The slides","The budget"],"rows":[]}]}"#
        #expect(SmartStructure.parse(json, source: source, allowTitle: true) == nil)
    }

    @Test func repeatedContentKeepsTheEdit() {
        let source = "Купить молоко и написать Арсену и закончить монтаж."
        let json = #"{"format":"structured","title":"","blocks":[{"type":"paragraph","text":"Купить молоко и написать Арсену и закончить монтаж.","items":[],"rows":[]},{"type":"checklist","text":"","items":["Купить молоко","Написать Арсену","Закончить монтаж"],"rows":[]}]}"#
        #expect(SmartStructure.parse(json, source: source, allowTitle: true) == nil)
    }

    @Test func titleInAnotherAlphabetIsDropped() throws {
        let source = "Купить молоко, написать Арсену и закончить монтаж."
        let json = #"{"format":"structured","title":"Tasks","blocks":[{"type":"checklist","text":"","items":["купить молоко","написать Арсену","закончить монтаж"],"rows":[]}]}"#
        let layout = try #require(SmartStructure.parse(json, source: source, allowTitle: true))
        #expect(layout.title == "")
        #expect(layout.blocks[0].items[0] == "Купить молоко")
    }

    @Test func proseOrInventedItemsKeepTheEdit() {
        let source = "Купить молоко, написать Арсену и закончить монтаж."
        #expect(SmartStructure.parse(#"{"format":"prose","title":"","blocks":[]}"#, source: source, allowTitle: true) == nil)
        let invented = #"{"format":"structured","title":"","blocks":[{"type":"checklist","text":"","items":["Купить молоко","Позвонить маме в субботу вечером"],"rows":[]}]}"#
        #expect(SmartStructure.parse(invented, source: source, allowTitle: true) == nil)
    }

    @Test func pipelineAppliesLayoutAfterTheEdit() async {
        // The mock answers both requests with the same body: a Responses API reply whose text is
        // the layout JSON. The editor step accepts it as text only if it passes integrity, so
        // use a mode whose editor output equals the input.
        var m = mode(.correct)
        m.rules.smartStructure = false
        #expect(!EditorPrompt.system(for: m).contains("SmartStructure"))
    }

    @Test func markdownLayoutIsNotCountedAsAddedText() {
        let raw = "купить молоко написать Арсену закончить монтаж и отправить преподавателю работу"
        let edited = "## Задачи\n\n- [ ] Купить молоко\n- [ ] Написать Арсену\n- [ ] Закончить монтаж\n- [ ] Отправить работу преподавателю"
        let report = IntegrityReport.check(raw: raw, edited: edited, level: .correct)
        #expect(!report.reject, "\(report.issues)")
        #expect(IntegrityReport.withoutMarkdown("1. **Пятница**\n> цитата\n| a | b |\n|---|---|\n| 1 | 2 |") == "Пятница цитата a b 1 2")
    }

    @Test func longInventedTextIsStillRejected() {
        let raw = "купить молоко и хлеб"
        let edited = "## Список покупок на неделю\n\n- [ ] Купить молоко в магазине у дома\n- [ ] Купить свежий хлеб и ещё сыр, яйца и фрукты для всей семьи"
        #expect(IntegrityReport.check(raw: raw, edited: edited, level: .correct).reject)
    }

    @Test func rulesSavedBeforeSmartStructureStillDecode() throws {
        let old = #"{"removeFillers":false,"removeRepetitions":true,"keepProfanity":true,"keepSlang":true,"spokenFormatting":false,"allowParagraphs":true}"#
        let rules = try JSONDecoder().decode(CleanupRules.self, from: Data(old.utf8))
        #expect(rules.removeFillers == false)
        #expect(rules.smartStructure == true)
    }

    @Test func modesExportedUnderThePreviousNameImport() throws {
        var library = ModeLibrary(modes: ModePresets.starter(names: [:], spoken: ["en"]))
        var json = String(decoding: try library.export(library.modes.map(\.id)), as: UTF8.self)
        json = json.replacingOccurrences(of: "saidright.modes", with: "saywell.modes")
        #expect(try library.importModes(from: Data(json.utf8)).count == 4)
    }
}

@Suite struct RichTextTests {
    @Test func tableAndListsBecomeHTML() {
        let text = "Нужно:\n\n1. Позвонить врачу\n2. Оплатить интернет\n\n| | ChatGPT | Claude |\n| --- | --- | --- |\n| Цена | 20 | 20 |"
        #expect(RichText.hasLayout(text))
        let html = RichText.html(text)
        #expect(html.contains("<ol><li>Позвонить врачу</li><li>Оплатить интернет</li></ol>"))
        #expect(html.contains("<table"))
        #expect(html.contains(">ChatGPT</th>"))
        #expect(html.contains(">Цена</td>"))
        #expect(!html.contains("---"))
        #expect(!RichText.hasLayout("Просто предложение, без списков."))
        #expect(RichText.html("a < b & c").contains("a &lt; b &amp; c"))
        #expect(TextFlavor.wantsRichText(bundleID: "com.apple.Notes"))
        #expect(!TextFlavor.wantsRichText(bundleID: "com.apple.Safari"))
    }
}
