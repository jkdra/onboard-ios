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

    enum Intent {
        case link
        case change
    }

    let mode: Mode
    var intent: Intent = .link
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
                    Text(footerText)
                        .fontStyle(.footnote)
                }

                Section {
                    if otpSent {
                        Button {
                            Task { await verify() }
                        } label: {
                            LoadingButtonLabel(intent == .change ? "Verify and update" : "Verify and link", isLoading: isVerifying, spinnerTint: .accentColor)
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
                        Button {
                            Task { await send(isResend: false) }
                        } label: {
                            LoadingButtonLabel("Send code", isLoading: isSending, spinnerTint: .accentColor)
                        }
                        .disabled(isSending || normalizedValue.isEmpty)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .keyboardDoneToolbar()
            .presentableErrorAlert(error: $alertError)
        }
    }

    private var navigationTitle: String {
        switch (mode, intent) {
        case (.phone, .link): "Link Phone"
        case (.email, .link): "Link Email"
        case (.phone, .change): "Change Phone"
        case (.email, .change): "Change Email"
        }
    }

    private var footerText: String {
        switch (mode, intent) {
        case (.phone, .link):
            "We'll text you a code to link this number to your account."
        case (.email, .link):
            "We'll email you a code to link this address to your account."
        case (.phone, .change):
            "We'll text you a code to update the number on your account."
        case (.email, .change):
            "We'll email you a code to update the address on your account."
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
        // Cooldown deliberately kept — backing out clears the form, not the
        // send history (see send(isResend:)).
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

        isSending = true
        defer { isSending = false }

        do {
            let destination = try resolvedDestination()

            // One window for both send paths: same destination inside the
            // window reopens code entry without re-sending (the in-flight code
            // stays valid); a different destination sends immediately.
            guard resendCooldown.canSend(to: destination) else {
                if !isResend {
                    submittedDestination = destination
                    otpSent = true
                }
                return
            }

            switch mode {
            case .phone:
                try await auth.sendLinkPhoneOTP(phone: destination)
            case .email:
                try await auth.sendLinkEmailOTP(email: destination)
            }
            submittedDestination = destination
            otpSent = true
            resendCooldown.start(duration: otpCooldownSeconds, destination: destination)
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
