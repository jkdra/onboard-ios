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
        VStack(alignment: .leading, spacing: 10) {
            field
            // iOS fills one-time codes from Apple Mail and Messages only, so a
            // student reading .edu mail in Gmail or Outlook has to paste — and
            // the field they'd paste into is a 1.5%-opacity TextField behind
            // the digit boxes, on a .numberPad with no paste key. The only
            // affordance was long-pressing something invisible.
            //
            // PasteButton is user-initiated, so it reads the clipboard WITHOUT
            // the "pasted from" permission banner that a UIPasteboard read
            // would trigger. Shown whenever the field is empty and enabled:
            // checking the clipboard's contents first to decide would itself
            // be the read we're avoiding.
            if isEnabled, code.isEmpty {
                PasteButton(payloadType: String.self) { strings in
                    guard let pasted = strings.first else { return }
                    let digits = OTPCodeInput.sanitized(pasted)
                    guard !digits.isEmpty else { return }
                    // Assigning drives the same onChange path as typing, so
                    // completion still auto-submits.
                    code = digits
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                .tint(.primary)
            }
        }
    }

    private var field: some View {
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
                // 0.015, not 0: fully transparent views are dropped from the
                // accessibility tree, which makes the field unreachable for
                // UI tests and VoiceOver. This stays visually invisible while
                // remaining focusable through accessibility.
                .opacity(0.015)
                .disabled(!isEnabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The real TextField is opacity(0), which UI tests can't address —
        // this identifier gives them the tappable digit row instead.
        .accessibilityIdentifier("OTPCodeField")
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
