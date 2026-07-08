//
//  SessionFlowUITests.swift
//  ChaisPasUITests
//
//  Drives one full session through every phase the first-launch state can
//  reach: concept intro → construction ladder → street mirror → summary.
//  (Warm recall and spontaneous close need review history / multi-concept
//  unlocks, so they are exercised implicitly on later sessions.)
//

import XCTest

final class SessionFlowUITests: XCTestCase {
    @MainActor
    func testFullSessionFlow() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        // Today screen → session
        let start = app.buttons["Start session"].firstMatch
        if !start.waitForExistence(timeout: 10) {
            app.buttons["Practice again"].firstMatch.tap()
        } else {
            start.tap()
        }

        let gotIt = app.buttons["Got it"].firstMatch
        let intro = app.buttons["Got it — let's build"].firstMatch
        let missed = app.buttons["Missed it"].firstMatch
        let skip = app.buttons["Skip"].firstMatch
        let done = app.buttons["Done"].firstMatch

        // Warm recall only exists once reviews are due; grade any through.
        // Concept intro appears on a fresh store.
        if intro.waitForExistence(timeout: 15) {
            intro.tap()
        }

        // Construction ladder (+ possibly spontaneous close): drade every
        // reveal; miss every 4th item so the rung controller walks both ways.
        var graded = 0
        while graded < 40 {
            if done.exists { break }
            if intro.exists { intro.tap(); continue }
            if skip.exists { skip.tap(); continue }
            guard gotIt.waitForExistence(timeout: 12) else { break }
            if graded % 4 == 3, missed.exists {
                missed.tap()
            } else {
                gotIt.tap()
            }
            graded += 1
        }
        XCTAssertGreaterThanOrEqual(graded, 8, "ladder should run at least 8 items")

        // Street mirror runs on audio timers; skip through whatever remains.
        while !done.exists {
            if skip.waitForExistence(timeout: 5) {
                skip.tap()
            } else if done.waitForExistence(timeout: 30) {
                break
            } else {
                XCTFail("session stalled before summary")
                return
            }
        }

        // Summary → back to Today
        XCTAssertTrue(app.staticTexts["C'est fait."].waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(
            app.buttons["Practice again"].waitForExistence(timeout: 10),
            "Today should reflect the completed session"
        )
    }
}
