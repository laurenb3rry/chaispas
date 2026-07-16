//
//  LearnModeUITests.swift
//  ChaisPasUITests
//
//  Phase 10 acceptance (PLAN2 §9): one full unit of each Learn sub-mode —
//  conjugation, vocabulary, grammar — playable end to end: intro surface →
//  drill run through the shared engine → summary → back to the library.
//

import XCTest

final class LearnModeUITests: XCTestCase {
    @MainActor
    func testFullUnitOfEachSubMode() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let home = app.buttons["recommended-today"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 30),
                      "Home should appear once the import finishes")

        // CONJUGATION — être: the table shows aligned formal + street forms,
        // then the drill run. Form cells are buttons (tap = hear it), so
        // their text lives in merged button labels, not staticTexts.
        openLearnUnit(app, tile: "learn-tile-conjugation", row: "être — to be")
        XCTAssertTrue(
            app.descendants(matching: .any)["j'suis"].firstMatch.waitForExistence(timeout: 10),
            "table should show the street form beside the formal one")
        XCTAssertTrue(app.descendants(matching: .any)["vous êtes"].firstMatch.exists,
                      "table should show all persons of the selected tense")
        startAndFinishDrill(app)
        backToHome(app)

        // VOCABULARY — pack 1: swipeable word cards, then the sentence drill.
        openLearnUnit(app, tile: "learn-tile-vocabulary",
                      row: "Vocabulary 1 · words 1–25")
        XCTAssertTrue(app.staticTexts["1 OF 25"].firstMatch.waitForExistence(timeout: 10),
                      "vocab intro should open on the first word card")
        // swipes drop like taps under load — retry until the pager moves
        var paged = false
        for _ in 0..<4 where !paged {
            app.swipeLeft()
            paged = app.staticTexts["2 OF 25"].firstMatch.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(paged, "swiping should page through the words")
        startAndFinishDrill(app)
        backToHome(app)

        // GRAMMAR — lesson 1: explanation → examples with audio → drill.
        openLearnUnit(app, tile: "learn-tile-grammar",
                      row: "Gender & articles: le, la, un, une")
        let examplesCTA = app.buttons["The examples"].firstMatch
        XCTAssertTrue(examplesCTA.waitForExistence(timeout: 10),
                      "grammar player should open on the explanation stage")
        examplesCTA.tap()
        // example lines are speakable buttons — match the merged label
        XCTAssertTrue(
            app.descendants(matching: .any)["La situation n'est pas bonne."].firstMatch
                .waitForExistence(timeout: 5),
            "examples stage should list the canonical examples")
        startAndFinishDrill(app)
        backToHome(app)
    }

    /// Home tile → Learn index (anchor-scrolled to the section) → unit row.
    /// Taps synthesized mid-transition can drop (the phase-4 gotcha), so
    /// re-tap until the destination actually appears.
    @MainActor
    private func openLearnUnit(_ app: XCUIApplication, tile: String, row: String) {
        let tileButton = app.buttons[tile].firstMatch
        XCTAssertTrue(tileButton.waitForExistence(timeout: 10))
        // Row text merges into the row Button's accessibility label — match
        // any element type (the phase-9 gotcha).
        let rowElement = app.descendants(matching: .any)[row].firstMatch
        for _ in 0..<4 where !rowElement.exists {
            if tileButton.exists, tileButton.isHittable { tileButton.tap() }
            _ = rowElement.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(rowElement.exists, "Learn index should show \(row)")
        for _ in 0..<4 where !app.buttons["Start the drill"].firstMatch.exists
            && !app.buttons["The examples"].firstMatch.exists {
            if rowElement.exists, rowElement.isHittable { rowElement.tap() }
            _ = app.buttons["Start the drill"].firstMatch.waitForExistence(timeout: 4)
                || app.buttons["The examples"].firstMatch.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(app.buttons["Start the drill"].firstMatch.exists
                      || app.buttons["The examples"].firstMatch.exists,
                      "\(row) should open its player")
    }

    /// Runs the drill to its summary: force each reveal with a stage tap
    /// (instead of waiting out prompt audio + speak-pause), grade every item,
    /// missing every 4th so the rung controller walks both ways.
    @MainActor
    private func startAndFinishDrill(_ app: XCUIApplication) {
        let start = app.buttons["Start the drill"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()

        let gotIt = app.buttons["Got it"].firstMatch
        let missed = app.buttons["Missed it"].firstMatch
        let done = app.buttons["Done"].firstMatch
        var graded = 0
        let deadline = Date.now.addingTimeInterval(300)
        while !done.exists, Date.now < deadline {
            if gotIt.exists {
                (graded % 4 == 3 && missed.exists ? missed : gotIt).tap()
                graded += 1
                // outgoing grade buttons animate out; never grab one mid-fade
                _ = gotIt.waitForNonExistence(timeout: 5)
            } else {
                // listening step: a stage tap reveals immediately
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
                usleep(400_000)
            }
        }
        XCTAssertGreaterThanOrEqual(graded, 10, "drill run should grade 10–15 items")
        XCTAssertTrue(done.waitForExistence(timeout: 30), "drill stalled before summary")
        XCTAssertTrue(app.staticTexts["Et voilà."].firstMatch.exists)
        done.tap()
    }

    /// Pops the Learn index back to Home so the next sub-mode enters through
    /// its own tile (which re-anchors the index scroll).
    @MainActor
    private func backToHome(_ app: XCUIApplication) {
        let home = app.buttons["recommended-today"].firstMatch
        for _ in 0..<3 where !home.exists {
            app.navigationBars.buttons.firstMatch.tap()
            _ = home.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(home.exists, "should return to Home between sub-modes")
    }
}
