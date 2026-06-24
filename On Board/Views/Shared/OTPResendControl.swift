//
//  OTPResendControl.swift
//  On Board
//

import SwiftUI

struct OTPResendControl: View {
    let channel: String
    let secondsRemaining: Int
    let isSending: Bool
    let onResend: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if secondsRemaining > 0 {
                Text("Resend \(channel) in \(secondsRemaining)s")
                    .foregroundStyle(.secondary)
            } else {
                Button("Resend \(channel)") {
                    onResend()
                }
                .disabled(isSending)
            }

            if isSending {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .fontStyle(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
