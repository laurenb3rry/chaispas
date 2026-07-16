//
//  LibraryScreenshotTests.swift
//  ChaisPasUITests
//
//  Visual QA helper: captures the library surfaces (Home top and scrolled,
//  each mode index, a Learn player intro). Not a functional test.
//

import XCTest

final class LibraryScreenshotTests: XCTestCase {
    @MainActor
    func testCaptureLibraryScreens() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        func snap(_ name: String) {
            sleep(1)  // let springs settle
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        let home = app.buttons["recommended-today"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 30))
        snap("1-home-top")

        // Back-chevron taps can drop mid-transition (the phase-4 gotcha in
        // navigation clothes): re-tap until Home actually returns.
        func popToHome() {
            for _ in 0..<3 where !home.exists {
                let back = app.navigationBars.buttons.firstMatch
                if back.exists, back.isHittable { back.tap() }
                _ = home.waitForExistence(timeout: 5)
            }
            XCTAssertTrue(home.exists, "should pop back to Home")
        }

        app.swipeUp()
        snap("2-home-middle")
        app.swipeUp()
        snap("3-home-bottom")

        // Learn index via the Vocabulary tile (exercises the anchor scroll)
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        let vocabTile = app.buttons["learn-tile-vocabulary"].firstMatch
        let vocabRow = app.descendants(matching: .any)["Vocabulary 1 · words 1–25"].firstMatch
        for _ in 0..<4 where !vocabRow.exists {
            if vocabTile.exists, vocabTile.isHittable { vocabTile.tap() }
            _ = vocabRow.waitForExistence(timeout: 5)
        }
        snap("4-learn-index-vocab-anchor")

        // The vocab player's word-card intro (phase 10)
        vocabRow.tap()
        if app.buttons["Start the drill"].firstMatch.waitForExistence(timeout: 10) {
            snap("5-vocab-player-intro")
            app.buttons["player-close"].firstMatch.tap()
            // the cover animates out; tapping nav mid-dismiss fails AX actions
            _ = app.buttons["player-close"].firstMatch.waitForNonExistence(timeout: 5)
        }
        popToHome()

        // The conjugation table (the phase-10 typography moment): present
        // tense, then a tense switch, then the drill stage.
        let conjTile = app.buttons["learn-tile-conjugation"].firstMatch
        let etreRow = app.descendants(matching: .any)["être — to be"].firstMatch
        for _ in 0..<4 where !etreRow.exists {
            if conjTile.exists, conjTile.isHittable { conjTile.tap() }
            _ = etreRow.waitForExistence(timeout: 5)
        }
        etreRow.tap()
        if app.buttons["Start the drill"].firstMatch.waitForExistence(timeout: 10) {
            snap("9-conjugation-table-present")
            app.buttons["PASSÉ COMPOSÉ"].firstMatch.tap()
            snap("10-conjugation-table-passe-compose")
            app.buttons["Start the drill"].firstMatch.tap()
            _ = app.buttons["Got it"].firstMatch.waitForExistence(timeout: 15)
            snap("11-drill-stage-revealed")
            app.buttons["drill-close"].firstMatch.tap()
            _ = app.buttons["drill-close"].firstMatch.waitForNonExistence(timeout: 5)
        }
        popToHome()

        // Grammar: explanation stage, then the examples list.
        let gramTile = app.buttons["learn-tile-grammar"].firstMatch
        let gramRow = app.descendants(matching: .any)["Gender & articles: le, la, un, une"].firstMatch
        for _ in 0..<4 where !gramRow.exists {
            if gramTile.exists, gramTile.isHittable { gramTile.tap() }
            _ = gramRow.waitForExistence(timeout: 5)
        }
        gramRow.tap()
        if app.buttons["The examples"].firstMatch.waitForExistence(timeout: 10) {
            snap("12-grammar-explanation")
            app.buttons["The examples"].firstMatch.tap()
            sleep(1)
            snap("13-grammar-examples")
            app.buttons["player-close"].firstMatch.tap()
            _ = app.buttons["player-close"].firstMatch.waitForNonExistence(timeout: 5)
        }
        popToHome()

        // Remaining indexes
        for (identifier, marker, name) in [
            ("home-section-speak", "A Paris café", "6-speak-index"),
            ("home-section-read", "TIER 0", "7-read-index"),
            ("home-section-listen", "slower street", "8-listen-index"),
        ] {
            let header = app.buttons[identifier].firstMatch
            for _ in 0..<6 where !(header.exists && header.isHittable) {
                app.swipeUp()
            }
            header.tap()
            _ = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", marker)
            ).firstMatch.waitForExistence(timeout: 10)
            snap(name)
            popToHome()
        }
    }
}
