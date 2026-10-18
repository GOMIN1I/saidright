// Dumps the editor and smart-formatting prompts exactly as SaidrightCore builds them, for
// scripts/eval-editing.py. Build and run:
//   swiftc -O -o build/dump-editor-prompts Sources/SaidrightCore/*.swift scripts/dump-editor-prompts.swift -module-name dump -parse-as-library
//   build/dump-editor-prompts <modes.json> <texts.json: ["…", …]> > <prompts.json>
import Foundation

@main
struct DumpEditorPrompts {
    static func main() throws {
        let args = CommandLine.arguments
        let lib = try JSONDecoder().decode(ModeLibrary.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let texts = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as! [String]
        var modes: [[String: Any]] = []
        for m in lib.modes where m.cleanup.usesEditor {
            modes.append(["name": m.name, "cleanup": m.cleanup.rawValue, "smartStructure": m.rules.smartStructure, "system": EditorPrompt.system(for: m)])
        }
        let schemaData = try JSONSerialization.data(withJSONObject: SmartStructure.schema)
        let out: [String: Any] = [
            "modes": modes,
            "structure": ["plain": SmartStructure.system(allowTitle: false), "title": SmartStructure.system(allowTitle: true), "plainTable": SmartStructure.system(allowTitle: false, table: true), "titleTable": SmartStructure.system(allowTitle: true, table: true)],
            "schema": String(data: schemaData, encoding: .utf8)!,
            "texts": texts.map { ["text": $0, "worthAsking": SmartStructure.worthAsking($0), "table": SmartStructure.requestsTable($0), "wrapped": EditorPrompt.wrap($0)] as [String: Any] },
        ]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted]))
    }
}
