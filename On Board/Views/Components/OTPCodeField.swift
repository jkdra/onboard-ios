//
//  OTPCodeInput.swift
//  On Board
//

import SwiftUI

enum OTPCodeInput {
    static let defaultLength = 6

    static func sanitized(_ value: String, length: Int = defaultLength) -> String {
        String(value.filter(\.isNumber).prefix(length))
    }

    static func isComplete(_ value: String, length: Int = defaultLength) -> Bool {
        sanitized(value, length: length).count == length
    }
}

struct OTPCodeField: View {
    @Binding var code: String
    var isEnabled: Bool = true
    var onComplete: () -> Void

    @FocusState private var isFocused: Bool
    @State private var didTriggerCompletion = false

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 8) {
                ForEach(0..<OTPCodeInput.defaultLength, id: \.self) { index in
                    if index == OTPCodeInput.defaultLength / 2 { dash }
                    DigitBox(character: character(at: index), isActive: isEnabled && isFocused && index == code.count)
                }
            }

            TextField("Verification code", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 42)
                .contentShape(Rectangle())
                .opacity(0)
                .disabled(!isEnabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onTapGesture { if isEnabled { isFocused = true } }
        .onChange(of: code) { _, newValue in
            let sanitized = OTPCodeInput.sanitized(newValue)
            if sanitized != newValue {
                code = sanitized
                return
            }

            if sanitized.count < OTPCodeInput.defaultLength {
                didTriggerCompletion = false
            }

            guard OTPCodeInput.isComplete(sanitized), !didTriggerCompletion else { return }
            didTriggerCompletion = true
            onComplete()
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled {
                didTriggerCompletion = false
            }
        }
    }

    private func character(at index: Int) -> String {
        let chars = Array(code)
        return index < chars.count ? String(chars[index]) : ""
    }

    private var dash: some View {
        Text("-")
            .fontStyle(.title2)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    @Previewable @State var code = ""
    @Previewable @State var didComplete = false

    return VStack(spacing: 20) {
        OTPCodeField(code: $code, isEnabled: true) {
            didComplete = true
        }

        Text(didComplete ? "Complete! Code: \(code)" : " ")
            .fontStyle(.footnote)
            .foregroundStyle(.secondary)

        Button("Reset") {
            code = ""
            didComplete = false
        }
    }
    .padding()
}
