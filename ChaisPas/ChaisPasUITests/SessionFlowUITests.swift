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
        app.launchSuppressingPlacement()

        let gotIt = app.buttons["Got it"].firstMatch
        let intro = app.buttons["Got it — let's build"].firstMatch
        let missed = app.buttons["Missed it"].firstMatch
        let skip = app.buttons["Skip"].firstMatch
        let done = app.buttons["Done"].firstMatch

        // Home fades in behind RootView's async-import transition; a tap
        // synthesized mid-transition can be dropped (the phase-4 gotcha), so
        // re-tap until each screen actually presents. Since phase 14 the
        // Home card belongs to the composer, so the session starts from the
        // Learn index's Construction card. On a fresh store the session
        // opens with the concept intro.
        let home = app.buttons["recommended-learn"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 30),
                      "Home should appear once the import finishes")
        let learnHeader = app.buttons["home-section-learn"].firstMatch
        let start = app.buttons["learn-construction"].firstMatch
        for _ in 0..<4 where !start.exists {
            if learnHeader.exists, learnHeader.isHittable { learnHeader.tap() }
            _ = start.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(start.exists, "the Learn index should show the Construction card")
        // The session opens on the concept intro on a fresh store, or straight
        // into a warm-recall drill (listening) on a store with due reviews —
        // detect either (there's no auto-reveal timer to surface a grade).
        let sayIt = app.staticTexts["say it in French — tap to reveal"].firstMatch
        var entered = false
        for _ in 0..<4 where !entered {
            if start.exists, start.isHittable { start.tap() }
            entered = intro.waitForExistence(timeout: 5) || gotIt.exists || sayIt.exists
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
                // No auto-reveal timer any more — a stage tap reveals the
                // answer during the listening step (a harmless no-op during
                // the street mirror, which self-advances on its audio timers).
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
                usleep(300_000)
            }
        }
        XCTAssertGreaterThanOrEqual(graded, 8, "ladder should run at least 8 items")
        XCTAssertTrue(done.waitForExistence(timeout: 60), "session stalled before summary")

        // Summary → back to Home
        XCTAssertTrue(app.staticTexts["C'est fait."].waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(
            start.waitForExistence(timeout: 10),
            "the Learn index should return after the session completes"
        )
    }
}
