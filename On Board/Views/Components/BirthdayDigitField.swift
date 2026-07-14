//
//  BirthdayDigitField.swift
//  On Board
//

import SwiftUI

/// Displays a date as YYYY-MM-DD digit boxes (matching `OTPCodeField`'s
/// style); tapping presents a real `DatePicker` in a popover anchored to
/// the tapped boxes. The boxes are a read-only display/trigger here, not a
/// typable field — actual date entry always goes through the native picker.
struct BirthdayDigitField: View {
    @Binding var date: Date?
    var isEnabled: Bool = true
    var maximumDate: Date? = nil

    @State private var isPresented = false
    @State private var pendingDate = Date()

    var body: some View {
        HStack(spacing: 10) {
            group(0..<4)
            dash
            group(4..<6)
            dash
            group(6..<8)
        }
        .overlay {
            DatePicker("Birthday", selection: $pendingDate, in: ...(maximumDate ?? .now), displayedComponents: .date)
//                .colorMultiply(.clear)
                .frame(maxWidth: .infinity)
                .labelsHidden()
        }
        .contentShape(.rect)
        
        Button {
            pendingDate = date ?? maximumDate ?? .now
            isPresented = true
        } label: {
            HStack(spacing: 10) {
                group(0..<4)
                dash
                group(4..<6)
                dash
                group(6..<8)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .frame(maxWidth: .infinity)
        .popover(isPresented: $isPresented) {
            VStack(spacing: 12) {
                DatePicker(
                    "Birthday",
                    selection: $pendingDate,
                    in: ...(maximumDate ?? .now),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(.primary)

                Button("Done") {
                    date = pendingDate
                    isPresented = false
                }
                .buttonStyle(.boardPrimary)
            }
            .safeAreaPadding()
            .presentationCompactAdaptation(.popover)
        }
    }

    private var dash: some View {
        Text("-")
            .fontStyle(.title2)
            .foregroundStyle(.secondary)
    }

    private func group(_ range: Range<Int>) -> some View {
        HStack(spacing: 6) {
            ForEach(range, id: \.self) { index in
                DigitBox(character: character(at: index))
            }
        }
    }

    private func character(at index: Int) -> String {
        let chars = Array(digits)
        return index < chars.count ? String(chars[index]) : ""
    }

    private var digits: String {
        guard let date else { return "" }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

#Preview {
    @Previewable @State var date: Date? = Calendar.current.date(byAdding: .year, value: -18, to: .now)
    return BirthdayDigitField(date: $date, maximumDate: Calendar.current.date(byAdding: .year, value: -16, to: .now))
}
