import XCTest

/// Interface and bundled-content checks. These tests do not supply generated
/// answers or establish physical-device inference, offline networking, or field safety.
final class CampingBuddyUITests: XCTestCase {
    @MainActor
    func testLibrarySearchAndReaderInLightAndDarkAppearance() throws {
        #if !DEBUG
        throw XCTSkip("Deterministic visual launch overrides are available in Debug builds only.")
        #else
        continueAfterFailure = false
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            assertInitialAskScreen(in: app)
            attachScreen(app, name: "\(appearance.capitalized) — Ask")

            openSleepingGuide(in: app, capturePrefix: appearance.capitalized)
            app.buttons["Done"].tap()
            app.tabBars.buttons["Settings"].tap()
            let appearancePicker = element("appearancePicker", in: app)
            XCTAssertTrue(reveal(appearancePicker, in: app), "Appearance settings must remain reachable.")
            let choice = appearancePicker.buttons[appearance.capitalized]
            XCTAssertTrue(choice.exists, "The appearance picker is missing \(appearance).")
            choice.tap()
            XCTAssertTrue(choice.isSelected, "The picker did not retain the requested appearance.")
            attachScreen(app, name: "\(appearance.capitalized) — Settings")
            app.terminate()
        }
        #endif
    }

    @MainActor
    func testSimulatorExplainsUnavailableModelWithoutGenerating() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator availability behavior is separate from the physical model smoke test.")
        #else
        continueAfterFailure = false
        let app = launch(appearance: "light")
        assertInitialAskScreen(in: app)
        app.tabBars.buttons["Settings"].tap()
        let load = app.buttons["loadModel"]
        XCTAssertTrue(reveal(load, in: app), "The local model control is missing.")
        if load.isEnabled { load.tap() }

        let status = element("modelStatus", in: app)
        XCTAssertTrue(reveal(status, in: app), "The model availability explanation must be readable.")
        let simulatorStatus = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS[c] %@", "simulator"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [simulatorStatus], timeout: 5), .completed)
        attachText(status.label, name: "Simulator — explicit model availability")
        attachScreen(app, name: "Simulator — model availability in Settings")

        app.tabBars.buttons["Ask"].tap()
        let input = element("questionInput", in: app)
        input.tap()
        let question = "How should I store food around bears?"
        input.typeText(question)
        app.buttons["sendQuestion"].tap()
        XCTAssertEqual(input.value as? String, question,
                       "An unavailable simulator must preserve the question for a later retry.")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "AI answer")).firstMatch.exists,
            "An unavailable simulator must not display a generated AI answer.")
        XCTAssertFalse(app.buttons["stopAnswer"].exists, "The simulator must not start generation.")
        attachScreen(app, name: "Simulator — preserved question without generation")
        #endif
    }

    @MainActor
    func testScopeResponseClearConversationAndAskAboutGuide() {
        continueAfterFailure = false
        let app = launch(appearance: "light")
        assertInitialAskScreen(in: app)
        let input = element("questionInput", in: app)
        let question = "What is the weather forecast at my campsite today?"
        input.tap()
        input.typeText(question)
        app.buttons["sendQuestion"].tap()

        // This is the app's real deterministic scope route, not a generated
        // answer or a test-injected response.
        let userBubble = app.staticTexts[question]
        XCTAssertTrue(userBubble.waitForExistence(timeout: 5), "The submitted question must appear in the conversation.")
        let response = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "This prototype covers general camping preparation.")).firstMatch
        XCTAssertTrue(response.waitForExistence(timeout: 5), "The real scope response must be displayed.")
        XCTAssertTrue(response.label.contains("confirm current weather"))
        XCTAssertTrue(response.label.contains("responsible land manager"))
        XCTAssertFalse(app.staticTexts["AI answer · Check the guides"].exists,
                       "The deterministic scope response must not be labeled as a model answer.")
        XCTAssertFalse(app.buttons["stopAnswer"].exists)
        XCTAssertTrue(reveal(response, in: app))
        attachScreen(app, name: "Scope response")

        // Clearing must remove both the existing response and an unsent draft.
        input.tap()
        input.typeText("Remember to pack my headlamp")
        let newConversation = app.buttons["newConversation"]
        XCTAssertTrue(newConversation.isEnabled)
        newConversation.tap()
        XCTAssertFalse(userBubble.exists)
        XCTAssertFalse(response.exists)
        let clearedValue = input.value as? String ?? ""
        XCTAssertTrue(clearedValue.isEmpty || clearedValue == (input.placeholderValue ?? ""),
                      "New conversation must clear the unsent question.")
        XCTAssertFalse(app.buttons["sendQuestion"].isEnabled)
        XCTAssertFalse(newConversation.isEnabled)

        app.tabBars.buttons["Library"].tap()
        let search = element("librarySearch", in: app)
        XCTAssertTrue(reveal(search, in: app))
        search.tap()
        search.typeText("sleep")
        let guide = app.buttons["guide-sleep-system"]
        XCTAssertTrue(reveal(guide, in: app))
        guide.tap()
        XCTAssertTrue(app.staticTexts["guideBody"].waitForExistence(timeout: 5))
        let askAboutGuide = app.buttons["askAboutGuide"]
        XCTAssertTrue(reveal(askAboutGuide, in: app))
        askAboutGuide.tap()
        let readerDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["Guide"])
        XCTAssertEqual(XCTWaiter.wait(for: [readerDismissed], timeout: 5), .completed)
        XCTAssertTrue(app.tabBars.buttons["Ask"].isSelected)
        XCTAssertEqual(input.value as? String, "What sleeping gear should I pack?")
        XCTAssertTrue(app.buttons["sendQuestion"].isEnabled)
        XCTAssertFalse(newConversation.isEnabled, "Asking about a guide should fill the composer without submitting it.")
        XCTAssertFalse(app.buttons["stopAnswer"].exists)
    }

    @MainActor
    func testLargeTextKeepsComposerAndGuidesReachable() throws {
        #if !DEBUG
        throw XCTSkip("The accessibility text-size launch override is available in Debug builds only.")
        #else
        continueAfterFailure = false
        let app = launch(appearance: "light", largeText: true)
        assertInitialAskScreen(in: app)
        XCTAssertTrue(element("questionInput", in: app).isHittable,
                      "The composer must remain reachable with accessibility text sizing.")
        XCTAssertTrue(app.buttons["sendQuestion"].exists)
        attachScreen(app, name: "Accessibility text size — Ask")
        openSleepingGuide(in: app, capturePrefix: "Accessibility text size")
        app.buttons["Done"].tap()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(reveal(app.buttons["loadModel"], in: app),
                      "The model control must remain reachable with accessibility text sizing.")
        attachScreen(app, name: "Accessibility text size — Settings")
        #endif
    }

    @MainActor
    func testModelDetailsAndSettingsAccess() throws {
        #if !DEBUG
        throw XCTSkip("Visual launch overrides are available in Debug builds only.")
        #else
        continueAfterFailure = false
        for (appearance, largeText) in [("light", false), ("dark", false), ("light", true)] {
            let app = launch(appearance: appearance, largeText: largeText)
            assertInitialAskScreen(in: app)
            app.buttons["chooseModel"].tap()
            XCTAssertTrue(app.buttons["modelsDone"].waitForExistence(timeout: 5))
            if largeText {
                XCTAssertGreaterThan(app.staticTexts["Your assistant, on your phone."].frame.height, 45,
                                     "Accessibility text sizing must reach the model sheet.")
            }
            attachScreen(app, name: "Model — \(appearance)\(largeText ? " large text" : "")")
            // Exactly one card, and it is the model the app ships.
            let cards = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "modelCard-"))
            XCTAssertEqual(cards.count, 1, "The app offers a single model.")
            let info = app.buttons["modelInfo-bonsai-27b-1bit"]
            XCTAssertTrue(reveal(info, in: app), "The shipped model must be listed with its details.")
            info.tap()
            XCTAssertTrue(app.buttons["modelDetailsDone"].waitForExistence(timeout: 5))
            XCTAssertTrue(element("modelDownloadSize", in: app).waitForExistence(timeout: 5))
            XCTAssertTrue(element("modelFileFormat", in: app).exists)
            attachScreen(app, name: "Model details — \(appearance)\(largeText ? " large text" : "")")
            app.buttons["modelDetailsDone"].tap()
            app.buttons["modelsDone"].tap()
            app.tabBars.buttons["Settings"].tap()
            let manage = app.buttons["manageModels"]
            XCTAssertTrue(reveal(manage, in: app))
            manage.tap()
            XCTAssertTrue(app.buttons["modelsDone"].waitForExistence(timeout: 5))
            // Nothing is downloaded in the simulator, so the offer to fetch it must be present.
            XCTAssertTrue(reveal(app.buttons["downloadModel-bonsai-27b-1bit"], in: app),
                          "An uninstalled model must offer its download.")
            app.terminate()
        }
        #endif
    }

    @MainActor
    private func launch(appearance: String, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-appearance", appearance]
        if largeText { app.launchArguments.append("-ui-testing-large-text") }
        app.launch()
        return app
    }

    @MainActor
    private func assertInitialAskScreen(in app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["Ask"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Ask"].isSelected)
        XCTAssertTrue(app.tabBars.buttons["Library"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
        XCTAssertTrue(element("questionInput", in: app).exists)
        XCTAssertFalse(app.buttons["sendQuestion"].isEnabled, "An empty question cannot be sent.")
    }

    @MainActor
    private func openSleepingGuide(in app: XCUIApplication, capturePrefix: String) {
        app.tabBars.buttons["Library"].tap()
        let search = element("librarySearch", in: app)
        XCTAssertTrue(reveal(search, in: app), "The local library search must be reachable.")
        search.tap()
        search.typeText("sleep")
        let guide = app.buttons["guide-sleep-system"]
        XCTAssertTrue(guide.waitForExistence(timeout: 5), "Search must find the sleeping guide.")
        XCTAssertFalse(app.buttons["guide-offline-navigation"].exists,
                       "Unrelated navigation content should be filtered from a sleep search.")
        XCTAssertTrue(reveal(guide, in: app))
        attachScreen(app, name: "\(capturePrefix) — Library search")
        guide.tap()

        let body = app.staticTexts["guideBody"]
        XCTAssertTrue(body.waitForExistence(timeout: 5), "Opening a guide must display its bundled passage.")
        XCTAssertTrue(body.label.contains("Plan for a tent, sleeping pad, and sleeping bag"))
        XCTAssertTrue(body.label.contains("Check local rules before relying on a hammock or shelter tied to trees."),
                      "The local reader must preserve the complete source-summary text.")
        XCTAssertTrue(reveal(body, in: app), "The guide body must be reachable at the selected text size.")
        attachScreen(app, name: "\(capturePrefix) — Guide body")
        let attribution = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "What to Bring — National Park Service")).firstMatch
        XCTAssertTrue(reveal(attribution, in: app), "The guide must retain its source attribution.")
        let reviewStatus = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "not been reviewed by an expert")).firstMatch
        XCTAssertTrue(reveal(reviewStatus, in: app), "The development review status must remain readable.")
        attachScreen(app, name: "\(capturePrefix) — Guide attribution")
        XCTAssertTrue(app.buttons["Done"].isHittable, "The guide must have a reachable Done control.")
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func reveal(_ target: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<6 {
            if target.exists && target.isHittable { return true }
            app.swipeUp()
        }
        return target.exists && target.isHittable
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
