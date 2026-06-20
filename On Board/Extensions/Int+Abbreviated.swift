//
//  Int+Abbreviated.swift
//  On Board
//
//  Compact-number formatting for counts (e.g. 1300 -> "1.3k", 2_200_000 -> "2.2m").
//

import Foundation

extension Int {
    var abbreviated: String {
        if abs(self) < 1000 { return "\(self)" }
        return formatted(
            .number
                .notation(.compactName)
                .precision(.fractionLength(0...1))
        ).lowercased()
    }
}
