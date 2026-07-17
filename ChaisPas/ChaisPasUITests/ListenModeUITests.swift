//
//  ListenModeUITests.swift
//  ChaisPasUITests
//
//  Phase 12 acceptance (PLAN2 §9), through the real UI: open an episode from
//  the Listen index, sit through the cold listen (audio only — the transcript
//  must not be visible), answer the three questions, reach the transcript
//  hub, dip into the shadow stage, and land back with a best score on the
//  index row.
//

import XCTest

final class ListenModeUITests: XCTestCase {
    @MainActor
    func testFullEpisodeFlow() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchSuppressingPlacement()

        let home = app.buttons["recommended-learn"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 30),
                      "Home should appear once the import finishes")

        // Listen index → the first level-A episode (level+id sort).
        openSection("home-section-listen", in: app)
        let row = app.buttons["episode-lst_a01"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let close = app.buttons["listen-close"].firstMatch
        for _ in 0..<4 where !close.exists {
            if row.exists, row.isHittable { row.tap() }
            _ = close.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(close.exists, "episode row should open the player")

        // Stage 1 — the cold listen is austere: a pause control and no text
        // from the episode. The pause toggle must work; the questions CTA
        // only appears once the audio has actually finished.
        let toggle = app.buttons["playback-toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()   // pause
        toggle.tap()   // resume
        let toQuestions = app.buttons["to-questions"].firstMatch
        XCTAssertTrue(toQuestions.waitForExistence(timeout: 180),
                      "the questions CTA should appear when the audio ends")

        // Stage 2 — answer all three questions (first option every time;
        // right or wrong doesn't matter to the flow). Taps drop under load
        // (the phase-4 gotcha) — re-tap until the first question appears.
        let firstOption = app.buttons["question-option-0"].firstMatch
        let done = app.buttons["Done"].firstMatch
        for _ in 0..<4 where !firstOption.exists {
            if toQuestions.exists, toQuestions.isHittable { toQuestions.tap() }
            _ = firstOption.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(firstOption.exists, "the first question should be on stage")
        let deadline = Date.now.addingTimeInterval(120)
        while !done.exists, Date.now < deadline {
            if firstOption.exists, firstOption.isHittable, firstOption.isEnabled {
                firstOption.tap()
            }
            usleep(400_000)
        }

        // Stage 3 — the transcript hub: score line, hub actions.
        XCTAssertTrue(done.waitForExistence(timeout: 10),
                      "answering the questions should land on the transcript hub")
        XCTAssertTrue(app.buttons["slow-pass"].firstMatch.exists)

        // Stage 5 — enter the shadow stage (re-tap: a dropped tap here would
        // silently skip the stage, since the hub is what we wait for after),
        // then skip both lines back to the hub (full shadow timing is
        // covered by the engine tests).
        let toShadow = app.buttons["to-shadow"].firstMatch
        let skip = app.buttons["shadow-skip"].firstMatch
        let shadowLabel = app.staticTexts["LISTEN — FULL SPEED"].firstMatch
        for _ in 0..<4 where !skip.exists && !shadowLabel.exists {
            if toShadow.exists, toShadow.isHittable { toShadow.tap() }
            _ = skip.waitForExistence(timeout: 3)
                || shadowLabel.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(skip.exists || shadowLabel.exists,
                      "the shadow stage should be on stage")
        let backAtHub = app.buttons["slow-pass"].firstMatch
        let shadowDeadline = Date.now.addingTimeInterval(120)
        while !backAtHub.exists, Date.now < shadowDeadline {
            if skip.exists, skip.isHittable { skip.tap() }
            usleep(400_000)
        }
        XCTAssertTrue(backAtHub.waitForExistence(timeout: 10),
                      "skipping both shadow lines should return to the hub")

        // Done → the index row now shows a best score.
        for _ in 0..<4 where !row.exists {
            if done.exists, done.isHittable { done.tap() }
            _ = row.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(row.exists)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", "best ")
            ).firstMatch.waitForExistence(timeout: 5),
            "the episode row should reflect the completed run")
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
