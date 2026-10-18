import Foundation

/// HTML for apps that paste formatted text (Notes, Pages, Word, Mail, TextEdit): the layout
/// Saidright writes as text — pipe tables, "- [ ] " / "- " / "• " / "1. " lists, "## " headings
/// — becomes a real table, real lists and headings there. Only produced when there is layout;
/// plain prose is pasted as plain text.
public enum RichText {
    public static func hasLayout(_ text: String) -> Bool {
        text.split(separator: "\n").contains { line in
            let l = line.trimmingCharacters(in: .whitespaces)
            return l.hasPrefix("|") || l.hasPrefix("- ") || l.hasPrefix("• ") || l.hasPrefix("## ") || l.range(of: #"^\d{1,3}\. "#, options: .regularExpression) != nil
        }
    }

    public static func html(_ text: String) -> String {
        var out: [String] = []
        var list: (tag: String, items: [String])?
        var table: [[String]] = []
        func flushList() {
            guard let l = list else { return }
            out.append("<\(l.tag)>" + l.items.map { "<li>\($0)</li>" }.joined() + "</\(l.tag)>")
            list = nil
        }
        func flushTable() {
            guard !table.isEmpty else { return }
            let header = table[0].map { "<th style=\"border:1px solid #999;padding:4px 8px;text-align:left\">\($0)</th>" }.joined()
            let rows = table.dropFirst().map { row in "<tr>" + row.map { "<td style=\"border:1px solid #999;padding:4px 8px\">\($0)</td>" }.joined() + "</tr>" }.joined()
            out.append("<table style=\"border-collapse:collapse\"><tr>\(header)</tr>\(rows)</table>")
            table = []
        }
        func item(_ tag: String, _ content: String) {
            if list?.tag != tag { flushList(); list = (tag, []) }
            list?.items.append(content)
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("|") {
                flushList()
                let cells = line.trimmingCharacters(in: CharacterSet(charactersIn: "|")).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if cells.allSatisfy({ $0.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil }) { continue }
                table.append(cells.map(escape))
                continue
            }
            flushTable()
            if line.isEmpty { flushList(); continue }
            if line.hasPrefix("- [ ] ") { item("ul", "☐ " + escape(String(line.dropFirst(6)))) }
            else if line.hasPrefix("- ") || line.hasPrefix("• ") { item("ul", escape(String(line.dropFirst(2)))) }
            else if let r = line.range(of: #"^\d{1,3}\. "#, options: .regularExpression) { item("ol", escape(String(line[r.upperBound...]))) }
            else if line.hasPrefix("## ") { flushList(); out.append("<h3>\(escape(String(line.dropFirst(3))))</h3>") }
            else if line.hasPrefix("> ") { flushList(); out.append("<blockquote>\(escape(String(line.dropFirst(2))))</blockquote>") }
            else { flushList(); out.append("<p>\(escape(line))</p>") }
        }
        flushList(); flushTable()
        return "<meta charset=\"utf-8\">" + out.joined()
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
