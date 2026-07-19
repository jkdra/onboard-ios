//
//  OnboardingCancelButton.swift
//  On Board
//
//  The first onboarding step gets a quiet escape hatch: an ✕ "Cancel" toolbar
//  button (top leading — later steps use a normal back button instead) that
//  confirms via an alert before doing anything. The user can sign out (their
//  partial progress stays server-side and `effectiveOnboardingStep` resumes
//  them where they left off next sign-in) or delete the partial account
//  entirely — the `delete_own_account` RPC wipes the profile, auth user, and
//  any pending waitlist entry. Apple-linked sessions revoke the Apple token
//  first (same sequence as DeleteAccountView) so Apple stops listing the app
//  as authorized.
//

import SwiftUI

struct OnboardingCancelModifier: ViewModifier {
    @Environment(AuthStore.self) private var auth

    @State private var showCancelAlert = false
    @State private var isCancelling = false
    @State private var alertError: PresentableAlertError?

    func body(content: Content) -> some View {
        content
            .disabled(isCancelling)
            .overlay {
                if isCancelling {
                    ZStack {
                        Color(.systemBackground)
                            .opacity(0.6)
                            .ignoresSafeArea()
                        ProgressView()
                            .scaleEffect(1.1)
                    }
                    .transition(.opacity)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showCancelAlert = true
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .foregroundStyle(.secondary)
                    .disabled(isCancelling)
                    .accessibilityLabel("Cancel account creation")
                }
            }
            .alert("Cancel account creation?", isPresented: $showCancelAlert) {
                Button("Sign out & finish later") {
                    Task { await signOutKeepingProgress() }
                }
                Button("Delete my info & cancel", role: .destructive) {
                    Task { await deletePartialAccount() }
                }
                Button("Keep going", role: .cancel) {}
            } message: {
                Text("Sign out to pick up where you left off later, or delete everything you've entered so far.")
            }
            .presentableErrorAlert(error: $alertError)
    }

    private func signOutKeepingProgress() async {
        isCancelling = true
        defer { isCancelling = false }
        await auth.signOut()
    }

    private func deletePartialAccount() async {
        isCancelling = true
        defer { isCancelling = false }

        do {
            // Same revoke-before-delete sequence as DeleteAccountView: Apple keeps
            // treating the app as authorized unless the token is revoked first.
            if auth.session?.linkedIdentities.contains(where: { $0.provider == .apple }) == true {
                let authorization = try await AppleSignInCoordinator.requestAuthorization()
                let code = try AppleSignInCoordinator.authorizationCode(from: authorization.credential)
                try await auth.revokeApple(authorizationCode: code)
            }

            try await auth.deleteAccount()
        } catch {
            // `.from` returns nil when the user dismissed the Apple sheet —
            // that's them changing their mind about changing their mind, not an error.
            alertError = PresentableAlertError.from(error)
        }
    }
}

extension View {
    /// Adds the onboarding "Cancel" (✕) toolbar affordance with its
    /// confirmation alert. Applied by `OnboardingCoordinator` to the first
    /// step only — subsequent steps expose a normal back button instead.
    func onboardingCancelToolbar() -> some View {
        modifier(OnboardingCancelModifier())
    }
}
