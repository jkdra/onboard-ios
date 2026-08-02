//
//  RuntimeEnvironment.swift
//  On Board
//

import Foundation

enum RuntimeEnvironment {
    /// True whenever an XCTest bundle is loaded into this process — covers both
    /// the unit-test host and the UI-test runner. Use this to skip perpetual
    /// (`repeatForever`) ambient animations: a permanently non-idle app stalls
    /// XCUITest's tap/wait synthesis (see the repeatforever-breaks-uitests
    /// note). Real users still get the motion; automated tests stay reliable.
    static let isRunningTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
