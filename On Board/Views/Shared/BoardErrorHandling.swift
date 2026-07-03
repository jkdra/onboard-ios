//
//  BoardErrorHandling.swift
//  On Board
//

import SwiftUI

private struct BoardErrorHandlingModifier: ViewModifier {
    @Environment(AuthStore.self) private var auth
    @Environment(BoardStore.self) private var store

    @Binding var alertError: PresentableAlertError?
    /// When true, suppresses the alert while `store.activeBoardWeek` is nil — used by
    /// screens that already show a dedicated inline "Couldn't load board" retry state,
    /// so the failure isn't surfaced twice.
    var suppressWhenBoardMissing = false

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

        if suppressWhenBoardMissing && store.activeBoardWeek == nil { return }

        alertError = PresentableAlertError(message: message)
    }
}

extension View {
    func boardErrorHandling(
        alertError: Binding<PresentableAlertError?>,
        suppressWhenBoardMissing: Bool = false
    ) -> some View {
        modifier(BoardErrorHandlingModifier(alertError: alertError, suppressWhenBoardMissing: suppressWhenBoardMissing))
    }
}
