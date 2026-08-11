//
//  SignInView+Logic.swift
//  On Board
//
//  Split out of SignInView.swift (precedent: SignInView+Social.swift) —
//  the credential/OTP/password flow logic behind the sign-in form.
//

import SwiftUI

extension SignInView {
    // MARK: - Helpers (logic unchanged)

    func resetOTPSession() {
        otpSent = false
        otpCode = ""
        password = ""
        confirmPassword = ""
        usePassword = false
        submittedDestination = ""
        isVerifyingOTP = false
        emailStatus = nil
        phoneExists = nil
        showAccountDetectedToast = false
        requiresEmailVerification = false
        // Deliberately NOT resendCooldown.reset(): backing out clears the form,
        // not the send history. Re-submitting the same destination inside the
        // window reuses the in-flight code (see sendOTP) instead of burning it
        // with a fresh send — the "Back ➜ Continue" loop used to fire a new
        // OTP every pass, invalidating the email already on its way.
    }

    func signUpWithPassword() async {
        if usesLiveBackend, !network.isConnected {
            presentAlert(PresentableAlertError.from(AuthError.networkUnavailable))
            return
        }
        guard !normalizedCredentialValue.isEmpty, !password.isEmpty, password == confirmPassword else { return }

        do {
            let email = try resolvedDestination()
            resolvingProvider = .email
            let session = try await auth.signUpWithPassword(email: email, password: password)
            if session == nil {
                withAnimation(.snappy(duration: 0.3)) {
                    requiresEmailVerification = true
                }
            }
        } catch {
            presentAlert(PresentableAlertError.from(error))
        }
    }

    func signInWithPassword() async {
        if usesLiveBackend, !network.isConnected {
            presentAlert(PresentableAlertError.from(AuthError.networkUnavailable))
            return
        }
        guard !normalizedCredentialValue.isEmpty, !password.isEmpty else { return }

        do {
            let email = try resolvedDestination()
            resolvingProvider = .email
            await auth.signInWithPassword(email: email, password: password)
        } catch {
            presentAlert(PresentableAlertError.from(error))
        }
    }

    func presentAlert(_ error: PresentableAlertError?) {
        guard let error else { return }
        alertError = error
    }

    var isSigningInCredential: Bool {
        switch credentialMode {
        case .phone:
            if case .signingIn(.phone) = auth.state { true } else { false }
        case .email:
            if case .signingIn(.email) = auth.state { true } else { false }
        }
    }

    var credentialProvider: AuthProvider {
        credentialMode == .phone ? .phone : .email
    }

    var otpSentMessage: String {
        switch credentialMode {
        case .phone:
            let label = PhoneNumberNormalizer.displayLabel(for: submittedDestination)
            return "Code sent to \(label)"
        case .email:
            return "Code sent to \(submittedDestination)"
        }
    }

    var normalizedCredentialValue: String {
        switch credentialMode {
        case .phone:
            phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        case .email:
            EmailNormalizer.normalized(emailAddress)
        }
    }

    private func resolvedDestination() throws -> String {
        switch credentialMode {
        case .phone:
            guard let e164 = PhoneNumberNormalizer.e164(from: normalizedCredentialValue) else {
                throw AuthError.invalidPhoneNumber
            }
            return e164
        case .email:
            let email = normalizedCredentialValue
            guard email.contains("@"), email.contains(".") else {
                throw AuthError.unknown("Enter a valid email address.")
            }
            return email
        }
    }

    func sendOTP(isResend: Bool) async {
        if usesLiveBackend, !network.isConnected {
            presentAlert(PresentableAlertError.from(AuthError.networkUnavailable))
            return
        }

        isSendingOTP = true
        defer { isSendingOTP = false }

        do {
            let destination = try resolvedDestination()

            // One window for BOTH send paths. Continue with the same address
            // inside the window doesn't re-send (the code already in flight is
            // still valid — a re-send would invalidate it mid-delivery); it
            // just returns to the code-entry screen. A different address has
            // no code in flight, so it sends immediately.
            guard resendCooldown.canSend(to: destination) else {
                if !isResend {
                    submittedDestination = destination
                    withAnimation(.snappy(duration: 0.35)) { otpSent = true }
                }
                return
            }

            switch credentialMode {
            case .phone:
                if !isResend {
                    phoneExists = try await auth.checkPhoneExists(phone: destination)
                }
                try await auth.sendPhoneOTP(phone: destination)
            case .email:
                if !isResend {
                    emailStatus = try await auth.checkEmailExists(email: destination)
                }
                try await auth.sendEmailOTP(email: destination)
            }
            submittedDestination = destination
            withAnimation(.snappy(duration: 0.35)) {
                if !isResend && (emailStatus?.exists == true || phoneExists == true) {
                    showAccountDetectedToast = true
                }
                otpSent = true
            }
            if !isResend { otpCode = "" }
            resendCooldown.start(duration: otpCooldownSeconds, destination: destination)
        } catch {
            presentAlert(PresentableAlertError.from(error))
        }
    }

    func verifyOTP() async {
        guard !isVerifyingOTP else { return }
        if usesLiveBackend, !network.isConnected {
            presentAlert(PresentableAlertError.from(AuthError.networkUnavailable))
            return
        }

        isVerifyingOTP = true
        resolvingProvider = credentialProvider
        defer { isVerifyingOTP = false }

        let token = OTPCodeInput.sanitized(otpCode)
        let destination = submittedDestination.isEmpty
            ? (try? resolvedDestination()) ?? normalizedCredentialValue
            : submittedDestination

        switch credentialMode {
        case .phone:
            await auth.verifyPhoneOTP(phone: destination, token: token)
        case .email:
            await auth.verifyEmailOTP(email: destination, token: token)
        }
    }
}
