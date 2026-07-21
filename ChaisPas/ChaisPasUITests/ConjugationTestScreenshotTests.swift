//
//  ConjugationTestScreenshotTests.swift
//  ChaisPasUITests
//
//  Visual QA helper for the conjugation-table test redesign: captures the
//  empty state and a mid-fill state (three rows settled, the fourth active) so
//  the reveal can be reviewed before grading is finalized. Writes PNGs to the
//  session scratchpad. Not a functional test.
//

import XCTest

final class ConjugationTestScreenshotTests: XCTestCase {
    /// Where the captured PNGs land for review.
    private let outDir = "/private/tmp/claude-501/-Users-laurenberry-dev-chaispas/99f5a976-9b4b-4966-931e-14eb36ffd143/scratchpad"

    @MainActor
    func testCaptureConjugationTestReveal() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchSuppressingPlacement()

        func save(_ name: String) {
            sleep(1)  // let springs + keyboard settle
            let png = app.screenshot().pngRepresentation
            let url = URL(fileURLWithPath: "\(outDir)/\(name).png")
            try? png.write(to: url)
        }

        // Home → Learn (conjugation) → Test tables
        let conjTile = app.buttons["learn-tile-conjugation"].firstMatch
        let testTables = app.buttons["conjugation-test-tables"].firstMatch
        for _ in 0..<4 where !testTables.exists {
            if conjTile.exists, conjTile.isHittable { conjTile.tap() }
            _ = testTables.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(testTables.waitForExistence(timeout: 15), "test-tables entry point")
        testTables.tap()

        // Empty state
        let field = app.textFields["conjugation-answer-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15), "answer field")
        field.tap()
        save("conj-test-1-empty")

        // Fill three rows (Return steps down), leaving the fourth active.
        for form in ["essaie", "essaies", "essaie"] {
            app.typeText(form + "\n")
            sleep(1)
        }
        save("conj-test-2-midfill")
    }
}
