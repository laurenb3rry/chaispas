//
//  NotesUITests.swift
//  ChaisPasUITests
//
//  The notes feature: the Home entry point opens the list, and a two-finger
//  pinch on a consumption surface captures a note that then shows up in the
//  list. Covers the two regressions found by hand — the note button not
//  opening, and a captured note not appearing.
//

import XCTest

final class NotesUITests: XCTestCase {
    @MainActor
    func testNotesButtonOpensAndCloses() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchSuppressingPlacement()

        let notesButton = app.buttons["home-notes"].firstMatch
        XCTAssertTrue(notesButton.waitForExistence(timeout: 30))
        notesButton.tap()

        let close = app.buttons["notes-close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 10),
                      "the note button should open the notes screen")
        close.tap()

        XCTAssertTrue(notesButton.waitForExistence(timeout: 5),
                      "closing notes should return to Home")
    }

    @MainActor
    func testPinchCapturesNoteThatShowsInList() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchSuppressingPlacement()

        let home = app.buttons["continue-learn"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 30))

        // Home → Read index → the first passage → the Reader (a surface that
        // carries the capture gesture, tagged "Read") — the sturdiest player to
        // reach by identifier.
        openSection("home-section-read", in: app)
        let row = app.buttons["passage-rd_event_01"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let close = app.buttons["read-close"].firstMatch
        for _ in 0..<4 where !close.exists {
            if row.exists, row.isHittable { row.tap() }
            _ = close.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(close.exists, "the passage row should open the Reader")
        XCTAssertTrue(app.staticTexts["quartier"].firstMatch.waitForExistence(timeout: 10),
                      "the passage body should be on the page")

        // Pinch → the quick-capture composer.
        app.pinch(withScale: 2.0, velocity: 1.5)
        let field = app.textViews["note-composer-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8),
                      "a pinch should raise the note composer")

        let marker = "metro is je dois prendre"
        field.tap()
        field.typeText(marker)
        app.buttons["note-composer-save"].firstMatch.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 8),
                      "saving should dismiss the composer back to the Reader")

        // Reader → back to Home → open the notes list.
        XCTAssertTrue(close.waitForExistence(timeout: 5),
                      "saving should return to the Reader, not dismiss it")
        close.tap()
        swipeRight(app)
        let notesButton = app.buttons["home-notes"].firstMatch
        XCTAssertTrue(notesButton.waitForExistence(timeout: 8))
        notesButton.tap()

        XCTAssertTrue(app.buttons["notes-close"].firstMatch.waitForExistence(timeout: 8))
        // The captured note is here — as a field value or its breadcrumb.
        let noteField = app.textFields["note-row-field"].firstMatch
        XCTAssertTrue(noteField.waitForExistence(timeout: 8),
                      "the captured note should appear in the list")
        let value = (noteField.value as? String) ?? ""
        XCTAssertTrue(value.contains(marker) || app.staticTexts["READ"].exists,
                      "the note should carry its text and its breadcrumb")
    }

    /// Drives the real pinch → composer and captures screenshots of the docked
    /// bar (empty, then with text) for a design review.
    @MainActor
    func testComposerScreenshots() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchSuppressingPlacement()

        XCTAssertTrue(app.buttons["continue-learn"].firstMatch.waitForExistence(timeout: 30))
        openSection("home-section-read", in: app)
        let row = app.buttons["passage-rd_event_01"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let close = app.buttons["read-close"].firstMatch
        for _ in 0..<4 where !close.exists {
            if row.exists, row.isHittable { row.tap() }
            _ = close.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(app.staticTexts["quartier"].firstMatch.waitForExistence(timeout: 10))

        app.pinch(withScale: 2.0, velocity: 1.5)
        let field = app.textViews["note-composer-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8), "pinch should raise the composer")

        attach(app, name: "composer-empty")

        field.tap()
        field.typeText("prendre le métro — I have to take the metro is je dois prendre le métro")
        attach(app, name: "composer-typed")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: Helpers

    @MainActor
    private func openSection(_ identifier: String, in app: XCUIApplication) {
        let header = app.buttons[identifier].firstMatch
        for _ in 0..<6 where !(header.exists && header.isHittable) { app.swipeUp() }
        XCTAssertTrue(header.exists && header.isHittable, "\(identifier) should be reachable")
        header.tap()
    }

    @MainActor
    private func swipeRight(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.52))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
}
