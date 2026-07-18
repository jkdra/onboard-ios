//
//  BirthdayWheelPicker.swift
//  On Board
//

import SwiftUI

/// Large ordinal-formatted date readout ("August 20th, 2006") over a compact
/// wheel `DatePicker` — no calendar grid, no popover, no digit entry.
struct BirthdayWheelPicker: View {
    @Binding var date: Date?
    var isEnabled: Bool = true
    var maximumDate: Date? = nil

    private var resolvedDate: Date {
        date ?? maximumDate ?? .now
    }

    private var selection: Binding<Date> {
        Binding(get: { resolvedDate }, set: { date = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Self.ordinalFormatted(resolvedDate))
                .fontStyle(.title)
                .fontWeight(.heavy)
                .contentTransition(.numericText())
                .animation(.snappy, value: resolvedDate)

            DatePicker(
                "Birthday",
                selection: selection,
                in: ...(maximumDate ?? .now),
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .tint(.primary)
            .frame(maxWidth: .infinity)
        }
        .disabled(!isEnabled)
    }

    private static func ordinalFormatted(_ date: Date) -> String {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        let year = calendar.component(.year, from: date)
        let month = date.formatted(.dateTime.month(.wide))

        let suffix: String
        switch day {
        case 11, 12, 13:
            suffix = "th"
        default:
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }

        return "\(month) \(day)\(suffix), \(year)"
    }
}

#Preview {
    @Previewable @State var date: Date? = Calendar.current.date(byAdding: .year, value: -18, to: .now)
    return BirthdayWheelPicker(
        date: $date,
        maximumDate: Calendar.current.date(byAdding: .year, value: -16, to: .now)
    )
    .padding()
}
