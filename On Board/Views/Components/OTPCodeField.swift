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

    @State private var didTriggerCompletion = false

    var body: some View {
        TextField("Verification code", text: $code)
            .textFieldStyle(.board)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .disabled(!isEnabled)
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
}
