//
//  PlacementUITests.swift
//  ChaisPasUITests
//
//  Phase 14 acceptance (PLAN2 §9), through the real UI: a fresh install
//  offers the placement assessment, the three modules run end to end on
//  pack content, and the summary lands back on Home. Plus the skip path.
//
//  These tests force the offer on via the argument domain: test classes
//  share a simulator clone's store, so a genuinely fresh install can't be
//  assumed mid-suite (the gate logic itself is unit-tested).
//

import XCTest

final class PlacementUITests: XCTestCase {
    @MainActor
    func testPlacementRunEndToEnd() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-placementForceOffer", "YES", "-showSpokenTranscript", "NO"]
        app.launch()

        // Fresh install → the calibration intro, before Home.
        let begin = app.buttons["placement-begin"].firstMatch
        XCTAssertTrue(begin.waitForExistence(timeout: 30),
                      "a fresh install should offer placement after the import")

        // Springs drop taps mid-transition — re-tap until the flow presents.
        let ready = app.buttons["placement-ready"].firstMatch
        for _ in 0..<4 where !ready.exists {
            if begin.exists, begin.isHittable { begin.tap() }
            _ = ready.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(ready.exists, "Begin should present the first module intro")

        // Drive whatever the flow shows next: module intros, typed
        // transcriptions, reveal → self-grade, word yes/no. Deliberately
        // types garbage / grades "not yet" / calls everything "not a word" —
        // a low reading is a perfectly valid calibration, and the flow stays
        // deterministic (a wrong transcription always waits on Next).
        let done = app.buttons["placement-done"].firstMatch
        let answerField = app.textFields["placement-answer"].firstMatch
        let check = app.buttons["placement-submit"].firstMatch
        let next = app.buttons["placement-next"].firstMatch
        let reveal = app.buttons["placement-reveal"].firstMatch
        let notYet = app.buttons["placement-not-yet"].firstMatch
        let notAWord = app.buttons["placement-word-no"].firstMatch

        // Every placement control is user-gated — it persists until tapped,
        // and transitions only follow taps. So: tap on `exists` alone (the
        // one query that can't hard-fail on a vanished element), then sleep
        // past that tap's engine beat + spring so the next iteration reads a
        // stable screen. Property-polling (`isEnabled`/`isHittable`) during
        // a module-boundary transition is what hard-failed here twice — the
        // element disappears between query resolutions.
        let deadline = Date.now.addingTimeInterval(240)
        while !done.exists, Date.now < deadline {
            if ready.exists {
                ready.tap()
                usleep(700_000)
            } else if reveal.exists {
                reveal.tap()
                usleep(700_000)
            } else if notYet.exists {
                notYet.tap()
                usleep(1_000_000)  // grade beat 500ms + spring settle
            } else if next.exists {
                next.tap()
                usleep(900_000)    // miss beat + spring settle
            } else if answerField.exists {
                answerField.tap()
                usleep(300_000)    // let keyboard focus land
                answerField.typeText("zz")
                if check.exists { check.tap() }
                usleep(700_000)    // wrong → result state waits on Next
            } else if notAWord.exists {
                notAWord.tap()
                usleep(700_000)    // vocab beat 280ms + spring settle
            } else {
                usleep(300_000)
            }
        }

        XCTAssertTrue(done.waitForExistence(timeout: 10),
                      "the flow should end on the calibration summary")
        XCTAssertTrue(app.staticTexts["Calibrated."].exists)

        // Done → Home, with the composer card composed.
        let home = app.buttons["recommended-learn"].firstMatch
        for _ in 0..<4 where !home.exists {
            if done.exists, done.isHittable { done.tap() }
            _ = home.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(home.exists, "Done should land on Home with the recommended card")
    }

    /// The offer must be skippable straight into Home.
    @MainActor
    func testSkipGoesStraightToHome() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-placementForceOffer", "YES", "-showSpokenTranscript", "NO"]
        app.launch()

        let skip = app.buttons["placement-skip"].firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 30))
        let home = app.buttons["recommended-learn"].firstMatch
        for _ in 0..<4 where !home.exists {
            if skip.exists, skip.isHittable { skip.tap() }
            _ = home.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(home.exists, "skipping placement should land on Home")
    }
}
