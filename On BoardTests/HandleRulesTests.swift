//
//  HandleRulesTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct HandleRulesTests {
    @Test func acceptsValidHandles() {
        #expect(HandleRules.isValid("maya.c"))
        #expect(HandleRules.isValid("leo_kp"))
        #expect(HandleRules.isValid("ab"))
    }

    @Test func rejectsInvalidHandles() {
        #expect(!HandleRules.isValid("a"))
        #expect(!HandleRules.isValid("has spaces"))
        #expect(!HandleRules.isValid("bad@handle"))
    }

    @Test func detectsProvisionalHandles() {
        #expect(HandleRules.isProvisional("u_abc123"))
        #expect(!HandleRules.isProvisional("maya.c"))
    }
}
