//
//  UITestLaunch.swift
//  ChaisPasUITests
//
//  Phase 14: a fresh install offers the placement assessment before Home.
//  Every test that isn't about placement suppresses the offer via the
//  UserDefaults argument domain and starts on Home exactly as before.
//  Phase 15: those tests also disable the speech transcript — a live mic +
//  its permission alert would wedge the taps the tests drive.
//

import XCTest

extension XCUIApplication {
    func launchSuppressingPlacement() {
        launchArguments += ["-placementOffered", "YES", "-showSpokenTranscript", "NO"]
        launch()
    }
}
