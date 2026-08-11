//
//  SchoolEmailRulesTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct SchoolEmailRulesTests {
    @Test func acceptsEduAddresses() {
        #expect(SchoolEmailRules.isValid("student@example.edu"))
    }

    @Test func rejectsNonEduAddresses() {
        #expect(!SchoolEmailRules.isValid("student@gmail.com"))
    }
}
