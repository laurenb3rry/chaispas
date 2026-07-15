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

        let gotIt = app.buttons["Got it"].firstMatch
        let intro = app.buttons["Got it — let's build"].firstMatch
        let missed = app.buttons["Missed it"].firstMatch
        let skip = app.buttons["Skip"].firstMatch
        let done = app.buttons["Done"].firstMatch

        // Home fades in behind RootView's async-import transition; a tap
        // synthesized mid-transition can be dropped (the phase-4 gotcha), so
        // re-tap the recommended card until the session actually presents.
        // On a fresh store the session opens with the concept intro.
        let start = app.buttons["recommended-today"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 30),
                      "Home should appear once the import finishes")
        var entered = false
        for _ in 0..<4 where !entered {
            if start.exists { start.tap() }
            entered = intro.waitForExistence(timeout: 5) || gotIt.exists
        }
        XCTAssertTrue(entered, "session should present after tapping Start")
        if intro.exists { intro.tap() }

        // Construction ladder → street mirror → spontaneous close: grade
        // every reveal, missing every 4th item so the rung controller walks
        // both ways. Only user-gated buttons (intro/grades) are tapped — the
        // street mirror advances itself on audio timers, and tapping its
        // transient Skip races the element vanishing mid-tap (the phase-8
        // flake). The mirror is simply waited out instead.
        _ = skip // transient; deliberately never tapped
        var graded = 0
        let deadline = Date.now.addingTimeInterval(480)
        while !done.exists, Date.now < deadline {
            if intro.exists {
                intro.tap()
            } else if gotIt.exists {
                (graded % 4 == 3 && missed.exists ? missed : gotIt).tap()
                graded += 1
                // grade buttons animate out after the tap; wait them out so
                // the next iteration can't grab an outgoing element mid-fade
                _ = gotIt.waitForNonExistence(timeout: 5)
            } else {
                usleep(500_000)
            }
        }
        XCTAssertGreaterThanOrEqual(graded, 8, "ladder should run at least 8 items")
        XCTAssertTrue(done.waitForExistence(timeout: 60), "session stalled before summary")

        // Summary → back to Home
        XCTAssertTrue(app.staticTexts["C'est fait."].waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(
            start.waitForExistence(timeout: 10),
            "Home should return after the session completes"
        )
    }
}
