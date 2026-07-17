//
//  UITestLaunch.swift
//  ChaisPasUITests
//
//  Phase 14: a fresh install offers the placement assessment before Home.
//  Every test that isn't about placement suppresses the offer via the
//  UserDefaults argument domain and starts on Home exactly as before.
//

import XCTest

extension XCUIApplication {
    func launchSuppressingPlacement() {
        launchArguments += ["-placementOffered", "YES"]
        launch()
    }
}
