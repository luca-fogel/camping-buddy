import Foundation

@main
struct ModelCheck {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            print("Usage: CampingModelCheck /absolute/project/path [question]")
            return
        }
        let root = URL(fileURLWithPath: args[1], isDirectory: true)
        let library = try ReferenceLibrary(data: Data(contentsOf: root.appendingPathComponent("Resources/ReferenceLibrary/references.json")))
        let engine = LocalModelEngine()
        let loadSeconds = try await engine.load(directory: root.appendingPathComponent("Resources/Models/gemma-4-E2B-it-4bit"))
        let scenarios: [(String, String)]
        if args.count >= 3 {
            scenarios = [("manual", args[2])]
        } else {
            let data = try Data(contentsOf: root.appendingPathComponent("evaluation/scenarios.json"))
            let rows = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
            scenarios = rows.map { ($0["id"] as! String, $0["question"] as! String) }
        }
        for (id, question) in scenarios {
            let passages = library.search(question)
            var row: [String: Any] = ["id": id, "question": question, "loadSeconds": loadSeconds,
                                     "retrievedIDs": passages.map(\.id), "deviceClass": "Mac; not an iPhone measurement"]
            if AnswerPolicy.requestsOverride(question) {
                row["generated"] = false
                row["answer"] = AnswerPolicy.overrideMessage
                row["status"] = "explicit-override-routed-without-generation"
            } else if AnswerPolicy.outsideScope(question) || passages.isEmpty {
                row["generated"] = false
                row["answer"] = AnswerPolicy.outsideScope(question) ? AnswerPolicy.scopeMessage : AnswerPolicy.noEvidence
                row["status"] = "routed-without-generation"
            } else {
              do {
                let result = try await engine.answer(prompt: AnswerPolicy.prompt(question: question, passages: passages))
                row["generated"] = true
                row["rawAnswer"] = result.text
                row["metrics"] = result.metrics
                row["firstGeneratedChunkSeconds"] = result.firstChunkSeconds
                row["answerSeconds"] = result.responseSeconds
                row["mlxAllocatorPeakBytes"] = result.allocatorPeakBytes
                do {
                    let checked = try AnswerPolicy.check(result.text, supplied: passages)
                    row["answer"] = checked.text
                    row["citedIDs"] = checked.citedIDs
                    row["status"] = "citation-identities-valid; semantic-review-required"
                } catch { row["status"] = "withheld-citation-check-failed" }
              } catch {
                row["generationAttempted"] = true
                row["generationCompleted"] = false
                row["status"] = "withheld-generation-failed-or-incomplete"
                row["error"] = error.localizedDescription
              }
            }
            let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        }
    }
}
