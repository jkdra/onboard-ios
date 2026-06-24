//
//  LinkSignInMethodView.swift
//  On Board
//

import SwiftUI

struct LinkSignInMethodView: View {
    enum Mode {
        case phone
        case email
    }

    let mode: Mode
    let onLinked: () -> Void

    @Environment(AuthStore.self) private var auth
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.dismiss) private var dismiss

    @State private var value = ""
    @State private var otpCode = ""
    @State private var otpSent = false
    @State private var isSending = false
    @State private var isVerifying = false
    @State private var alertError: PresentableAlertError?
    @State private var submittedDestination = ""
    @State private var resendCooldown = OTPCooldown()

    private let otpCooldownSeconds = 60

    private var usesLiveBackend: Bool {
        AppConfiguration.current.isSupabaseConfigured
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(mode == .phone ? "+1 555 555 0100" : "Email address", text: $value)
                        .keyboardType(mode == .phone ? .phonePad : .emailAddress)
                        .textContentType(mode == .phone ? .telephoneNumber : .emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(otpSent || isSending)

                    if otpSent {
                        Text(otpSentMessage)
                            .fontStyle(.caption)
                            .foregroundStyle(.secondary)

                        OTPCodeField(code: $otpCode, isEnabled: otpSent && !isVerifying) {
                            Task { await verify() }
                        }
                    } else if mode == .phone {
                        Text("US numbers work without +1.")
                            .fontStyle(.caption)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(mode == .phone
                         ? "We'll text you a code to link this number to your account."
                         : "We'll email you a code to link this address to your account.")
                        .fontStyle(.footnote)
                }

                Section {
                    if otpSent {
                        Button("Verify and link") {
                            Task { await verify() }
                        }
                        .disabled(isVerifying || !OTPCodeInput.isComplete(otpCode))

                        OTPResendControl(
                            channel: mode == .phone ? "text" : "email",
                            secondsRemaining: resendCooldown.secondsRemaining,
                            isSending: isSending,
                            onResend: { Task { await send(isResend: true) } }
                        )

                        Button("Use a different \(mode == .phone ? "number" : "address")") {
                            resetOTPSession()
                        }
                        .fontStyle(.footnote)
                    } else {
                        Button("Send code") {
                            Task { await send(isResend: false) }
                        }
                        .disabled(isSending || normalizedValue.isEmpty)
                    }
                }
            }
            .navigationTitle(mode == .phone ? "Link Phone" : "Link Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .presentableErrorAlert(error: $alertError)
        }
    }

    private var normalizedValue: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedOTP: String {
        otpCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var otpSentMessage: String {
        switch mode {
        case .phone:
            "We texted \(PhoneNumberNormalizer.displayLabel(for: submittedDestination))."
        case .email:
            "We emailed \(submittedDestination)."
        }
    }

    private func resetOTPSession() {
        otpSent = false
        otpCode = ""
        submittedDestination = ""
        resendCooldown.reset()
    }

    private func resolvedDestination() throws -> String {
        switch mode {
        case .phone:
            guard let e164 = PhoneNumberNormalizer.e164(from: normalizedValue) else {
                throw AuthError.invalidPhoneNumber
            }
            return e164
        case .email:
            let email = normalizedValue.lowercased()
            guard email.contains("@"), email.contains(".") else {
                throw AuthError.unknown("Enter a valid email address.")
            }
            return email
        }
    }

    private func send(isResend: Bool) async {
        if usesLiveBackend, !network.isConnected {
            alertError = PresentableAlertError.from(AuthError.networkUnavailable)
            return
        }

        if isResend, !resendCooldown.canResend {
            return
        }

        isSending = true
        defer { isSending = false }

        do {
            let destination = try resolvedDestination()
            switch mode {
            case .phone:
                try await auth.sendLinkPhoneOTP(phone: destination)
            case .email:
                try await auth.sendLinkEmailOTP(email: destination)
            }
            submittedDestination = destination
            otpSent = true
            resendCooldown.start(duration: otpCooldownSeconds)
        } catch {
            alertError = PresentableAlertError.from(error)
        }
    }

    private func verify() async {
        if usesLiveBackend, !network.isConnected {
            alertError = PresentableAlertError.from(AuthError.networkUnavailable)
            return
        }

        isVerifying = true
        defer { isVerifying = false }

        let token = OTPCodeInput.sanitized(otpCode)
        let destination = submittedDestination.isEmpty
            ? (try? resolvedDestination()) ?? normalizedValue
            : submittedDestination

        do {
            switch mode {
            case .phone:
                try await auth.verifyLinkPhoneOTP(phone: destination, token: token)
            case .email:
                try await auth.verifyLinkEmailOTP(email: destination, token: token)
            }
            onLinked()
            dismiss()
        } catch {
            alertError = PresentableAlertError.from(error)
        }
    }
}
