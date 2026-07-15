//
//  LibraryScreenshotTests.swift
//  ChaisPasUITests
//
//  Visual QA helper: captures the phase-9 library surfaces (Home top and
//  scrolled, each mode index, a coming-soon sheet). Not a functional test.
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

        // Coming-soon sheet from a vocab pack row
        vocabRow.tap()
        if app.staticTexts["COMING IN PHASE 10"].waitForExistence(timeout: 5) {
            snap("5-coming-soon-sheet")
            app.buttons["D'accord"].firstMatch.tap()
        }
        app.navigationBars.buttons.firstMatch.tap()

        // Remaining indexes
        XCTAssertTrue(home.waitForExistence(timeout: 5))
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
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(home.waitForExistence(timeout: 5))
        }
    }
}
