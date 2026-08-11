//
//  AppleNameAdoptionTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

struct AppleNameAdoptionTests {
    @Test func adoptsWhenCurrentNameEmpty() {
        #expect(AppleNameAdoption.shouldAdopt(currentDisplayName: ""))
        #expect(AppleNameAdoption.shouldAdopt(currentDisplayName: "   "))
        #expect(AppleNameAdoption.shouldAdopt(currentDisplayName: nil))
    }

    @Test func neverOverwritesAChosenName() {
        #expect(!AppleNameAdoption.shouldAdopt(currentDisplayName: "Jawad Khadra"))
    }
}
