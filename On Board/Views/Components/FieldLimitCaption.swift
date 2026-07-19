//
//  FieldLimitCaption.swift
//  On Board
//
//  Character-count caption for limited text fields. Appears once the count
//  crosses 80% of the limit; orange while approaching, red once exceeded.
//

import SwiftUI

struct FieldLimitCaption: View {
    let count: Int
    let limit: Int

    var body: some View {
        if count >= Int(Double(limit) * 0.8) {
            Text("\(count)/\(limit)")
                .fontStyle(.caption2)
                .foregroundStyle(count > limit ? Color.red : Color.orange)
                .monospacedDigit()
        }
    }
}
