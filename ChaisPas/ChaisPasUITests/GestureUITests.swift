//
//  GestureUITests.swift
//  ChaisPasUITests
//
//  Phase 16 follow-up: the forgiving horizontal swipe-back on index screens,
//  and pull-down-to-dismiss on the scrolling players (conjugation/grammar),
//  which a plain downward drag couldn't reach.
//

import XCTest

final class GestureUITests: XCTestCase {
    @MainActor
    func testSwipeRightGoesBackWithoutOpeningARow() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchSuppressingPlacement()

        let home = app.buttons["continue-learn"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 30))

        // Home → Read index (has full-width passage rows to try to catch).
        openSection("home-section-read", in: app)
        XCTAssertTrue(app.staticTexts["TIER 0"].firstMatch.waitForExistence(timeout: 10),
                      "should be on the Read index")

        // A clear left→right drag across a row should pop back to Home, NOT
        // open the passage under the finger.
        swipeRight(app)

        XCTAssertTrue(home.waitForExistence(timeout: 5),
                      "swiping right should return to Home")
        XCTAssertFalse(app.buttons["read-close"].exists,
                       "swiping right must not open a passage")
    }

    @MainActor
    func testPullDownDismissesConjugationPlayer() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchSuppressingPlacement()

        let home = app.buttons["continue-learn"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 30))

        // Home → Learn index → a verb → the conjugation player (a scrolling
        // intro where a plain downward drag used to be eaten by the scroll).
        let conjTile = app.buttons["learn-tile-conjugation"].firstMatch
        let firstVerb = app.descendants(matching: .any)["être — to be"].firstMatch
        for _ in 0..<4 where !firstVerb.exists {
            if conjTile.exists, conjTile.isHittable { conjTile.tap() }
            _ = firstVerb.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(firstVerb.exists, "Learn index should list verbs")

        let startDrill = app.buttons["Start the drill"].firstMatch
        for _ in 0..<4 where !startDrill.exists {
            if firstVerb.exists, firstVerb.isHittable { firstVerb.tap() }
            _ = startDrill.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(startDrill.waitForExistence(timeout: 10),
                      "the conjugation player should open")

        // Pull the table down from the top → dismiss back to the Learn index.
        pullDown(app)

        XCTAssertTrue(startDrill.waitForNonExistence(timeout: 8),
                      "pulling down should dismiss the conjugation player")
        XCTAssertTrue(firstVerb.waitForExistence(timeout: 5),
                      "should be back on the Learn index")
    }

    // MARK: Helpers

    @MainActor
    private func openSection(_ identifier: String, in app: XCUIApplication) {
        let header = app.buttons[identifier].firstMatch
        for _ in 0..<6 where !(header.exists && header.isHittable) { app.swipeUp() }
        XCTAssertTrue(header.exists && header.isHittable, "\(identifier) should be reachable")
        let backButton = app.navigationBars.buttons.firstMatch
        for _ in 0..<4 where !backButton.exists {
            if header.exists, header.isHittable { header.tap() }
            _ = backButton.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(backButton.exists, "\(identifier) should push its index")
    }

    @MainActor
    private func swipeRight(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.52))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func pullDown(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
        // Hold at the bottom so the overscroll is sustained (a real pull), not
        // a flick that springs back before the offset is observed.
        start.press(forDuration: 0.1, thenDragTo: end,
                    withVelocity: .default, thenHoldForDuration: 0.5)
    }
}
