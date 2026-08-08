//
//  PhoneNumberNormalizerTests.swift
//  On BoardTests
//

import Foundation
import Testing
@testable import On_Board

@MainActor
struct PhoneNumberNormalizerTests {
    @Test func formatsTenDigitUSNumbers() {
        #expect(PhoneNumberNormalizer.e164(from: "5555550100") == "+15555550100")
        #expect(PhoneNumberNormalizer.e164(from: "(555) 555-0100") == "+15555550100")
    }

    @Test func preservesExplicitCountryCode() {
        #expect(PhoneNumberNormalizer.e164(from: "+44 7911 123456") == "+447911123456")
    }

    @Test func rejectsTooShortNumbers() {
        #expect(PhoneNumberNormalizer.e164(from: "12345") == nil)
    }

    @Test func displayLabelFormatsUSNumbers() {
        #expect(PhoneNumberNormalizer.displayLabel(for: "+15555550100") == "(555) 555-0100")
    }
}
