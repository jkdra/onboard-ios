//
//  BoardErrorHandling.swift
//  On Board
//

import SwiftUI

private struct BoardErrorHandlingModifier: ViewModifier {
    @Environment(AuthStore.self) private var auth
    @Environment(BoardStore.self) private var store

    @Binding var alertError: PresentableAlertError?

    func body(content: Content) -> some View {
        content
            .onChange(of: store.loadError) { _, message in
                guard let message, !message.isEmpty else { return }
                handle(message)
            }
    }

    private func handle(_ message: String) {
        defer { store.clearLoadError() }

        if message == AuthError.sessionExpired.localizedDescription
            || message == BoardServiceError.sessionExpired.localizedDescription {
            Task { await auth.reportSessionExpired() }
            return
        }

        alertError = PresentableAlertError(message: message)
    }
}

extension View {
    func boardErrorHandling(alertError: Binding<PresentableAlertError?>) -> some View {
        modifier(BoardErrorHandlingModifier(alertError: alertError))
    }
}
