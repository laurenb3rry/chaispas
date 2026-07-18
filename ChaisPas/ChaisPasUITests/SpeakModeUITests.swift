//
//  SpeakModeUITests.swift
//  ChaisPasUITests
//
//  Phase 11 acceptance (PLAN2 §9), through the real UI: open a scenario from
//  the Speak index, play the dialogue end to end — skipping NPC audio with
//  stage taps and self-grading every line — and land on the summary with the
//  replay-different-variant CTA. Phase 15: former branch points are now plain
//  user turns that accept any of several lines (no option tapping).
//

import XCTest

final class SpeakModeUITests: XCTestCase {
    @MainActor
    func testFullScenarioPlaythroughWithBranch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchSuppressingPlacement()

        let home = app.buttons["recommended-learn"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 30),
                      "Home should appear once the import finishes")

        // Speak index → the café scenario (difficulty 1, sorts first).
        openSection("home-section-speak", in: app)
        let card = app.buttons["scenario-scn_cafe"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let close = app.buttons["speak-close"].firstMatch
        for _ in 0..<4 where !close.exists {
            if card.exists, card.isHittable { card.tap() }
            _ = close.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(close.exists, "scenario card should open the player")

        // Drive the conversation. NPC lines auto-advance after their audio;
        // a stage tap skips ahead (and reveals during the speak-pause), so
        // the test never waits out real playback.
        let gotIt = app.buttons["Got it"].firstMatch
        let missed = app.buttons["Missed it"].firstMatch
        let summary = app.staticTexts["Et voilà."].firstMatch

        var graded = 0
        let deadline = Date.now.addingTimeInterval(240)
        while !summary.exists, Date.now < deadline {
            if gotIt.exists, gotIt.isHittable {
                (graded % 4 == 3 && missed.exists ? missed : gotIt).tap()
                graded += 1
                // outgoing grade buttons animate out; never grab one mid-fade
                _ = gotIt.waitForNonExistence(timeout: 5)
            } else {
                // NPC speaking or a user turn awaiting the reveal: a stage tap
                // moves things on. (0.5, 0.2) is safely below the chrome and
                // above the centered exchange, so it never lands on a control.
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
                usleep(300_000)
            }
        }

        XCTAssertTrue(summary.waitForExistence(timeout: 10),
                      "playthrough should reach the end screen")
        XCTAssertGreaterThanOrEqual(graded, 4, "should have graded real exchanges")
        XCTAssertTrue(app.buttons["replay-variant"].firstMatch.exists,
                      "end screen should offer the different-variant replay")

        // Done returns to the index. (That completion persists and shows on
        // the card is covered directly and reliably by the unit tests
        // `completionPersistsToDisk` and `fullPlaythrough…` — far less
        // brittle than re-deriving it through this coordinate-tap playthrough.)
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 10),
                      "Done should land back on the Speak index")
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
