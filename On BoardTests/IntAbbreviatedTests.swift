//
//  IntAbbreviatedTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct IntAbbreviatedTests {
    @Test func leavesSmallNumbersUnchanged() {
        #expect(999.abbreviated == "999")
    }

    @Test func abbreviatesThousands() {
        #expect(1_300.abbreviated == "1.3k")
    }
}
