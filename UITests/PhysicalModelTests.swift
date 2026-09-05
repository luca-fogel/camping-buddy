import XCTest

/// A connected-device smoke test. This does not establish Mac-off operation,
/// disabled networking, semantic answer quality, or sustained battery/heat behavior.
final class PhysicalModelTests: XCTestCase {
    @MainActor
    func testBundledModelGeneratesOnPhysicalDevice() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Real local model generation is tested on a physical iPhone only.")
        #else
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Camping Buddy"].waitForExistence(timeout: 15))

        // Read the local source before loading the model. No website is opened.
        app.tabBars.buttons["Library"].tap()
        let libraryPassage = app.buttons["guide-sleep-system"]
        XCTAssertTrue(reveal(libraryPassage, in: app), "The bundled sleeping guide is missing.")
        libraryPassage.tap()
        assertSleepingSourceIsOpen(in: app)
        attachScreen(app, name: "Physical iPhone — bundled sleeping reference")
        app.buttons["Done"].tap()

        app.tabBars.buttons["Settings"].tap()
        let status = app.staticTexts["modelStatus"]
        XCTAssertTrue(reveal(status, in: app))
        let load = app.buttons["loadModel"]
        XCTAssertTrue(reveal(load, in: app))
        load.tap()
        let loadFinished = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label CONTAINS %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@",
                "ready · local files only", "Model unavailable:", "Loading stopped."),
            object: status)
        let loadResult = XCTWaiter.wait(for: [loadFinished], timeout: 120)
        attachText(status.exists ? status.label : "Model status disappeared.",
                   name: "Physical iPhone — model loading result")
        guard loadResult == .completed else {
            attachScreen(app, name: "Physical iPhone — model load timeout")
            XCTFail("The bundled model did not finish loading within 120 seconds.")
            return
        }
        guard status.label.contains("ready · local files only") else {
            attachScreen(app, name: "Physical iPhone — model unavailable")
            XCTFail("The real bundled model is unavailable: \(status.label)")
            return
        }

        app.tabBars.buttons["Ask"].tap()
        let question = "What sleeping gear should I pack?"
        // This button fills the real input with a question; it supplies no answer.
        let suggestedQuestion = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "Pack for a good night")).firstMatch
        XCTAssertTrue(reveal(suggestedQuestion, in: app))
        suggestedQuestion.tap()
        app.buttons["sendQuestion"].tap()

        // A fast response may finish before Stop becomes visible. If it does,
        // the later AI-answer assertion still requires a real accepted generation.
        let stop = app.buttons["stopAnswer"]
        _ = stop.waitForExistence(timeout: 3)
        let generationFinished = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: stop)
        guard XCTWaiter.wait(for: [generationFinished], timeout: 120) == .completed else {
            attachScreen(app, name: "Physical iPhone — generation timeout")
            attachText(app.debugDescription, name: "Physical iPhone — timeout UI state")
            if stop.exists { stop.tap() }
            XCTFail("Local generation did not finish within 120 seconds.")
            return
        }

        let aiAnswer = app.staticTexts["AI answer · Check the guides"]
        guard reveal(aiAnswer, in: app) else {
            attachScreen(app, name: "Physical iPhone — answer not accepted")
            attachText(app.debugDescription, name: "Physical iPhone — answer failure UI state")
            XCTFail("No accepted generated AI answer appeared; a fallback or withheld answer is not a pass.")
            return
        }
        let citedSource = app.buttons["answer-guide-sleep-system"]
        XCTAssertTrue(reveal(citedSource, in: app), "The generated answer lacks its local sleeping-guide source button.")
        let responseText = app.staticTexts.allElementsBoundByIndex.map(\.label)
            .filter { !$0.isEmpty }.joined(separator: "\n")
        attachText("Question: \(question)\n\nAccepted response screen:\n\(responseText)",
                   name: "Physical iPhone — generated response")
        attachScreen(app, name: "Physical iPhone — generated answer and source")
        citedSource.tap()
        assertSleepingSourceIsOpen(in: app)
        app.buttons["Done"].tap()

        app.tabBars.buttons["Settings"].tap()
        let modelDetails = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "Model details")).firstMatch
        XCTAssertTrue(reveal(modelDetails, in: app), "Model details must be reachable from Settings.")
        modelDetails.tap()
        XCTAssertTrue(app.navigationBars["Model details"].waitForExistence(timeout: 5))
        let measurements = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "MLX allocator peak")).firstMatch
        XCTAssertTrue(reveal(measurements, in: app), "No real generation measurements were displayed.")
        XCTAssertTrue(measurements.label.contains("first text"))
        XCTAssertTrue(measurements.label.contains("answer"))
        attachText("Connected physical-iPhone smoke test. Networking was not changed by this test.\n\n\(measurements.label)\n\nMLX allocator peak is not total app memory. Mac-off operation, cold offline launch, battery, and heat still require independent testing.",
                   name: "Physical iPhone — observed timing and allocator memory")
        attachScreen(app, name: "Physical iPhone — Model details measurements")
        #endif
    }

    @MainActor
    private func assertSleepingSourceIsOpen(in app: XCUIApplication) {
        let body = app.staticTexts["guideBody"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertTrue(body.label.contains("Plan for a tent, sleeping pad"))
        let attribution = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "What to Bring — National Park Service")).firstMatch
        XCTAssertTrue(reveal(attribution, in: app), "The guide's source attribution is missing.")
        let summaryReview = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "not been reviewed by an expert")).firstMatch
        XCTAssertTrue(reveal(summaryReview, in: app), "The guide's review limitation is missing.")
        let sourceDetails = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "Source details")).firstMatch
        XCTAssertTrue(reveal(sourceDetails, in: app), "The source-details disclosure is missing.")
        sourceDetails.tap()
        let provenance = app.staticTexts["https://www.nps.gov/subjects/camping/what-to-bring.htm"]
        XCTAssertTrue(reveal(provenance, in: app), "The local source provenance is missing.")
        let reviewStatus = app.staticTexts["Development seed; not expert-reviewed."]
        XCTAssertTrue(reveal(reviewStatus, in: app), "The source's development review status is missing.")
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return true }
            // Chat may already have scrolled to its bottom while the model was
            // loading, so a target above the viewport needs a downward swipe.
            if element.exists && element.frame.midY < app.frame.midY { app.swipeDown() }
            else { app.swipeUp() }
        }
        return element.exists && element.isHittable
    }

    @MainActor
    private func attachScreen(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachText(_ text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
