//
//  LibraryNavigationUITests.swift
//  ChaisPasUITests
//
//  Phase 9 acceptance: from Home, every mode index is reachable and shows
//  real store content; stubbed players present the coming-in-phase-N sheet;
//  Construction remains a real (non-stubbed) entry.
//

import XCTest

final class LibraryNavigationUITests: XCTestCase {
    @MainActor
    func testBrowseEveryMode() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let home = app.buttons["recommended-today"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 30),
                      "Home should appear once the import finishes")

        // LEARN — the Conjugation tile lands on the Learn index anchored at
        // the verb list, populated from the store. Row text merges into the
        // row Button's accessibility label, so match any element type; taps
        // synthesized mid-transition can drop, so re-tap until it lands.
        let conjugationTile = app.buttons["learn-tile-conjugation"].firstMatch
        XCTAssertTrue(conjugationTile.waitForExistence(timeout: 10))
        let firstVerb = app.descendants(matching: .any)["être — to be"].firstMatch
        var onLearnIndex = false
        for _ in 0..<4 where !onLearnIndex {
            if conjugationTile.exists, conjugationTile.isHittable {
                conjugationTile.tap()
            }
            onLearnIndex = firstVerb.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(onLearnIndex, "Learn index should list the pack's verbs")

        // A stubbed player: verb row → coming-in-phase-10 sheet, dismissable.
        firstVerb.tap()
        let stubLabel = app.staticTexts["COMING IN PHASE 10"].firstMatch
        XCTAssertTrue(stubLabel.waitForExistence(timeout: 5))
        app.buttons["D'accord"].firstMatch.tap()
        XCTAssertTrue(stubLabel.waitForNonExistence(timeout: 5))

        // Construction is not stubbed — the real session entry must exist.
        // (The full session run lives in SessionFlowUITests.)
        XCTAssertTrue(app.buttons["learn-construction"].firstMatch.exists)
        goBack(app)
        XCTAssertTrue(home.waitForExistence(timeout: 5))

        // SPEAK — index shows the scenario cards with setting blurbs
        // (blurbs render only on the index, so this can't match a Home card;
        // the blurb text lives inside the card Button's merged label).
        openSection("home-section-speak", in: app)
        let blurb = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "A Paris café")
        ).firstMatch
        XCTAssertTrue(blurb.waitForExistence(timeout: 10),
                      "Speak index should show scenario setting blurbs")
        goBack(app)

        // READ — passages grouped by tier (tier headers exist only there).
        openSection("home-section-read", in: app)
        XCTAssertTrue(app.staticTexts["TIER 0"].firstMatch.waitForExistence(timeout: 10),
                      "Read index should group passages by tier")
        goBack(app)

        // LISTEN — level sections with their blurbs exist only on the index.
        openSection("home-section-listen", in: app)
        let levelBlurb = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "slower street")
        ).firstMatch
        XCTAssertTrue(levelBlurb.waitForExistence(timeout: 10),
                      "Listen index should show the level sections")
        goBack(app)

        XCTAssertTrue(home.waitForExistence(timeout: 5))
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

    @MainActor
    private func goBack(_ app: XCUIApplication) {
        app.navigationBars.buttons.firstMatch.tap()
    }
}
