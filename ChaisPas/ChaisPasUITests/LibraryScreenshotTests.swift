//
//  LibraryScreenshotTests.swift
//  ChaisPasUITests
//
//  Visual QA helper: captures the library surfaces (Home top and scrolled,
//  each mode index, a Learn player intro). Not a functional test.
//

import XCTest

final class LibraryScreenshotTests: XCTestCase {
    /// Close taps drop like any synthesized tap (the phase-4 gotcha):
    /// re-tap until the cover is actually gone.
    @MainActor
    private func closePlayer(_ app: XCUIApplication, button identifier: String) {
        let close = app.buttons[identifier].firstMatch
        for _ in 0..<4 where close.exists {
            if close.isHittable { close.tap() }
            if close.waitForNonExistence(timeout: 5) { break }
        }
        XCTAssertTrue(close.waitForNonExistence(timeout: 5),
                      "\(identifier) should dismiss the player")
    }

    @MainActor
    func testCaptureLibraryScreens() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchSuppressingPlacement()

        func snap(_ name: String) {
            sleep(1)  // let springs settle
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        let home = app.buttons["recommended-learn"].firstMatch
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
            closePlayer(app, button: "player-close")
        }
        popToHome()

        // The conjugation table (10c reference-card treatment): present
        // tense, then a tense switch, then the drill stage. aller carries the
        // 10c-register sample explanation.
        let conjTile = app.buttons["learn-tile-conjugation"].firstMatch
        let allerRow = app.descendants(matching: .any)["aller — to go"].firstMatch
        for _ in 0..<4 where !allerRow.exists {
            if conjTile.exists, conjTile.isHittable { conjTile.tap() }
            _ = allerRow.waitForExistence(timeout: 5)
        }
        allerRow.tap()
        if app.buttons["Start the drill"].firstMatch.waitForExistence(timeout: 10) {
            snap("9-conjugation-explanation")
            // the table + tense-usage panel live below the explanation
            app.swipeUp()
            snap("9b-conjugation-table-present")
            app.buttons["PASSÉ COMPOSÉ"].firstMatch.tap()
            snap("10-conjugation-table-passe-compose")
            app.buttons["Start the drill"].firstMatch.tap()
            _ = app.buttons["Got it"].firstMatch.waitForExistence(timeout: 15)
            snap("11-drill-stage-revealed")
            closePlayer(app, button: "drill-close")
        }
        popToHome()

        // Grammar: explanation stage, then the examples list. The connectors
        // lesson carries the 10c-register sample explanation.
        let gramTile = app.buttons["learn-tile-grammar"].firstMatch
        let gramRow = app.descendants(matching: .any)["Discourse glue: du coup, donc, alors, bref"].firstMatch
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
            closePlayer(app, button: "player-close")
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
