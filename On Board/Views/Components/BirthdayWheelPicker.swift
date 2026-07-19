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
        // The wheel always *shows* a date, so commit it. Without this the
        // binding stays nil until the user moves a wheel, leaving Continue
        // disabled while the UI looks like a date is already picked.
        .onAppear {
            if date == nil { date = resolvedDate }
        }
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
