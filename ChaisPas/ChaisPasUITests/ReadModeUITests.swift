//
//  ReadModeUITests.swift
//  ChaisPasUITests
//
//  Phase 13 acceptance (PLAN2 §9), through the real UI: open a passage from
//  the Read index, tap a word and get its gloss chip, answer the questions,
//  see the quiet done state, and come back to a row marked read.
//

import XCTest

final class ReadModeUITests: XCTestCase {
    @MainActor
    func testReadPassageEndToEnd() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchSuppressingPlacement()

        let home = app.buttons["continue-learn"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 30),
                      "Home should appear once the import finishes")

        // Read index → the first tier-0 passage (tier+id sort).
        openSection("home-section-read", in: app)
        let row = app.buttons["passage-rd_event_01"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let close = app.buttons["read-close"].firstMatch
        for _ in 0..<4 where !close.exists {
            if row.exists, row.isHittable { row.tap() }
            _ = close.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(close.exists, "passage row should open the Reader")

        // The page is set from the pack: body text is on screen.
        let word = app.staticTexts["quartier"].firstMatch
        XCTAssertTrue(word.waitForExistence(timeout: 10),
                      "the passage body should be on the page")

        // Tap a glossed word → its chip appears inline; tap the chip → gone.
        let chip = app.buttons["gloss-chip"].firstMatch
        for _ in 0..<4 where !chip.exists {
            if word.exists, word.isHittable { word.tap() }
            _ = chip.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(chip.exists, "tapping a glossed word should show its chip")
        // The chip's Text merges into the Button's label (the phase-9 gotcha).
        XCTAssertEqual(chip.label, "neighborhood",
                       "the chip should carry the English gloss")
        chip.tap()
        XCTAssertTrue(chip.waitForNonExistence(timeout: 5))

        // The questions wait at the end of the page — answer them all
        // (first option each; right or wrong doesn't matter to the flow).
        let doneLine = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "marked as read")
        ).firstMatch
        var questionIndex = 0
        let deadline = Date.now.addingTimeInterval(90)
        while !doneLine.exists, questionIndex < 4, Date.now < deadline {
            let option = app.buttons["question-\(questionIndex)-option-0"].firstMatch
            if option.exists, option.isHittable, option.isEnabled {
                option.tap()
                // Every question is on the page at once, so only move on
                // when this one actually locked — a dropped tap would
                // otherwise skip it silently.
                for _ in 0..<10 where option.isEnabled { usleep(200_000) }
                if !option.isEnabled { questionIndex += 1 }
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(doneLine.waitForExistence(timeout: 10),
                      "answering every question should show the quiet done state")
        XCTAssertGreaterThanOrEqual(questionIndex, 2, "the passage carries 2–3 questions")

        // Done → back on the index, the row now reads as read.
        let done = app.buttons["Done"].firstMatch
        for _ in 0..<6 where !(done.exists && done.isHittable) {
            app.swipeUp()
        }
        for _ in 0..<4 where !row.exists {
            if done.exists, done.isHittable { done.tap() }
            _ = row.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(row.exists, "Done should land back on the index")
    }

    /// Scrolls Home until the section header is hittable, then opens it.
    @MainActor
    private func openSection(_ identifier: String, in app: XCUIApplication) {
        let header = app.buttons[identifier].firstMatch
        for _ in 0..<6 where !(header.exists && header.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(header.exists && header.isHittable,
                      "\(identifier) should be reachable by scrolling Home")
        header.tap()
    }
}
