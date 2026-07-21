//
//  SessionScreenshotTests.swift
//  ChaisPasUITests
//
//  Visual QA helper: walks the session far enough to capture each stage of
//  the hero screen as an attachment. Not a functional test.
//

import XCTest

final class SessionScreenshotTests: XCTestCase {
    @MainActor
    func testCaptureSessionStages() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchSuppressingPlacement()

        func snap(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        let start = app.buttons["continue-learn"].firstMatch
        let gotIt = app.buttons["Got it"].firstMatch
        let intro = app.buttons["Got it — let's build"].firstMatch
        let skip = app.buttons["Skip"].firstMatch
        let done = app.buttons["Done"].firstMatch

        // First launch on a fresh clone renders late; a tap synthesized the
        // instant the button appears can be dropped, so retry until each
        // screen actually presents. Since phase 14 the Home card belongs to
        // the composer, so the session starts from the Learn index's
        // Construction card (fresh clone → concept intro is first).
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        let learnHeader = app.buttons["home-section-learn"].firstMatch
        let construction = app.buttons["learn-construction"].firstMatch
        for _ in 0..<4 where !construction.exists {
            if learnHeader.exists, learnHeader.isHittable { learnHeader.tap() }
            _ = construction.waitForExistence(timeout: 5)
        }
        // A warm store (accumulated app data on the clone) opens straight
        // into a warm-recall drill (listening) with no concept intro, and
        // there's no auto-reveal timer to surface a grade — detect the
        // listening hint too.
        let sayIt = app.staticTexts["SAY IT IN FRENCH"].firstMatch
        var presented = false
        for _ in 0..<3 {
            if construction.exists, construction.isHittable { construction.tap() }
            if intro.waitForExistence(timeout: 8) || gotIt.exists || sayIt.exists {
                presented = true
                break
            }
        }
        XCTAssertTrue(presented, "session never presented after 3 start taps")
        if intro.exists {
            snap("1-concept-intro")
            intro.tap()
        }

        // Ladder: listening state, then reveal it with a stage tap — there
        // is no auto-reveal timer any more.
        let stageTap = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        sleep(1)
        snap("2-ladder-listening")
        stageTap.tap()
        XCTAssertTrue(gotIt.waitForExistence(timeout: 12))
        sleep(1)  // let the reveal spring settle before capturing
        snap("3-ladder-revealed")

        var graded = 0
        while graded < 40, !done.exists, !skip.exists {
            if gotIt.exists {
                gotIt.tap()
                graded += 1
                _ = gotIt.waitForNonExistence(timeout: 5)
            } else {
                // reveal the next prompt (no-op during the street mirror)
                stageTap.tap()
                usleep(300_000)
            }
        }

        if skip.waitForExistence(timeout: 10) {
            sleep(2)
            snap("4-street-mirror")
        }

        // Let the street mirror auto-advance on its audio timers
        // (~15s per item, up to 3 items) to exercise the no-skip path.
        XCTAssertTrue(done.waitForExistence(timeout: 90))
        snap("5-summary")
    }
}
