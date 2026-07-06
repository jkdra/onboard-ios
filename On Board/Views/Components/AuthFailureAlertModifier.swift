//
//  AuthFailureAlertModifier.swift
//  On Board
//
//  Bridges AuthStore.state == .failed(message) into a local alert. Several
//  screens (sign-in, delete account, account management) need this same
//  wiring — the view's own `alertError` binding may also be populated from
//  other error sources, which is fine, since this only writes into it and
//  clears via `auth.cancelSignIn()` when the resulting alert is dismissed.
//

import SwiftUI

private struct AuthFailureAlertModifier: ViewModifier {
    let auth: AuthStore
    @Binding var alertError: PresentableAlertError?

    private var authFailureMessage: String? {
        if case .failed(let message) = auth.state { message } else { nil }
    }

    func body(content: Content) -> some View {
        content
            .presentableErrorAlert(error: $alertError) {
                if case .failed = auth.state {
                    auth.cancelSignIn()
                }
            }
            .onChange(of: authFailureMessage) { _, message in
                guard let message else { return }
                alertError = PresentableAlertError(message: message)
            }
    }
}

extension View {
    func authFailureAlert(_ auth: AuthStore, error: Binding<PresentableAlertError?>) -> some View {
        modifier(AuthFailureAlertModifier(auth: auth, alertError: error))
    }
}
