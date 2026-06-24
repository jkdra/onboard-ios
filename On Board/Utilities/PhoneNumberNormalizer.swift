//
//  PhoneNumberNormalizer.swift
//  On Board
//

import Foundation

enum PhoneNumberNormalizer {
    /// Formats user input into E.164 for Supabase / Twilio (`+15555550100`).
    /// US numbers without a country code are assumed to be +1.
    static func e164(from input: String, defaultCountryCode: String = "1") -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }

        let candidate: String
        if trimmed.hasPrefix("+") {
            candidate = "+" + digits
        } else if digits.count == 10, defaultCountryCode == "1" {
            candidate = "+1" + digits
        } else if digits.count == 11, digits.hasPrefix("1") {
            candidate = "+" + digits
        } else if digits.count >= 10 {
            candidate = "+\(defaultCountryCode)\(digits)"
        } else {
            return nil
        }

        return isValidE164(candidate) ? candidate : nil
    }

    static func isValidE164(_ value: String) -> Bool {
        let pattern = #"^\+[1-9]\d{6,14}$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    /// Readable label for confirmation copy, e.g. `(555) 555-0100` for US numbers.
    static func displayLabel(for e164: String) -> String {
        let digits = e164.filter(\.isNumber)
        guard digits.count == 11, digits.hasPrefix("1") else { return e164 }
        let area = digits.dropFirst().prefix(3)
        let prefix = digits.dropFirst(4).prefix(3)
        let line = digits.suffix(4)
        return "(\(area)) \(prefix)-\(line)"
    }
}
