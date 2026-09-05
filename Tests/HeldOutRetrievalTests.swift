import XCTest
@testable import CampingCore

/// These tests exercise local retrieval and citation identity, not model generation.
final class HeldOutRetrievalTests: XCTestCase {
    private struct Scenario: Decodable {
        let id: String
        let question: String
        let expectedSourceIDs: [String]
        let expectedBehavior: String
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func library() throws -> ReferenceLibrary {
        try ReferenceLibrary(data: Data(contentsOf: projectRoot
            .appendingPathComponent("Resources/ReferenceLibrary/references.json")))
    }

    private func scenarios() throws -> [Scenario] {
        try JSONDecoder().decode([Scenario].self, from: Data(contentsOf: projectRoot
            .appendingPathComponent("evaluation/scenarios.json")))
    }

    func testHeldOutExpectedReferencesExist() throws {
        let scenarios = try scenarios()
        let availableIDs = Set(try library().passages.map(\.id))
        XCTAssertFalse(scenarios.isEmpty)
        XCTAssertEqual(Set(scenarios.map(\.id)).count, scenarios.count)
        for scenario in scenarios {
            XCTAssertFalse(scenario.question.isEmpty, scenario.id)
            XCTAssertFalse(scenario.expectedBehavior.isEmpty, scenario.id)
            XCTAssertTrue(Set(scenario.expectedSourceIDs).isSubset(of: availableIDs),
                          "\(scenario.id) refers to a missing local passage")
        }
    }

    func testHeldOutQuestionsRetrieveEveryExpectedPassage() throws {
        let library = try library()
        for scenario in try scenarios() {
            // Empty expectations describe unsupported content, not a lexical
            // no-match requirement. Shared words can still retrieve a passage.
            guard !scenario.expectedSourceIDs.isEmpty else { continue }
            // Exercise the same default result limit used by the application.
            // Include current-condition questions here even if routing later
            // declines generation: their preparation reference must be findable.
            let retrievedIDs = library.search(scenario.question).map(\.id)
            let missing = Set(scenario.expectedSourceIDs).subtracting(retrievedIDs)
            XCTAssertTrue(missing.isEmpty,
                          "\(scenario.id): missing \(missing.sorted()); retrieved \(retrievedIDs)")
        }
    }

    func testValidLibraryCitationOutsideRetrievedContextIsRejected() throws {
        let library = try library()
        let navigation = try XCTUnwrap(scenarios().first { $0.id == "eval-02-navigation" })
        let supplied = library.search(navigation.question)
        let suppliedIDs = Set(supplied.map(\.id))
        let unsupplied = try XCTUnwrap(library.passages.first { !suppliedIDs.contains($0.id) })

        // Synthetic validator input; this is not a generated model answer.
        XCTAssertThrowsError(try AnswerPolicy.check("Test citation [\(unsupplied.id)].", supplied: supplied)) {
            XCTAssertEqual($0 as? AnswerPolicy.CitationError, .unknownCitation(unsupplied.id))
        }
    }
}
