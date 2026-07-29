//
//  WireDateParser.swift
//  On Board
//
//  Shared parser for the "yyyy-MM-dd" wire format used for stored birthday/
//  graduation date strings — POSIX locale so parsing doesn't depend on the
//  device's locale/calendar. BirthdayCelebration and GraduationMonth both
//  need this same parse; kept here so the locale/format pairing only has to
//  be right in one place.
//

import Foundation

enum WireDateParser {
    static func date(from raw: String?) -> Date? {
        guard let raw else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: raw)
    }
}
