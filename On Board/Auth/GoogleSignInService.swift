//
//  GoogleSignInService.swift
//  On Board
//
//  Native Google Sign-In via the GoogleSignIn-iOS SDK.
//  Presents the native account picker, gets a Google ID token,
//  which SupabaseAuthService then exchanges for a Supabase session.
//

import Foundation
import GoogleSignIn
import UIKit

@MainActor
enum GoogleSignInService {
    /// Present the native Google Sign-In sheet and return the resulting ID token.
    /// Throws `AuthError.cancelled` if the user dismisses the sheet.
    static func signIn(clientID: String) async throws -> String {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        guard let vc = topViewController() else {
            throw AuthError.unknown("Google Sign-In: no active view controller.")
        }
        return try await idToken(presentingViewController: vc)
    }

    /// Forward a URL to GIDSignIn so the SDK can finish the OAuth callback.
    /// Call this from `onOpenURL` in the app entry point.
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    // MARK: - Private

    private static func idToken(presentingViewController vc: UIViewController) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: vc) { result, error in
                if let error {
                    if let googleError = error as? GIDSignInError,
                       googleError.code == .canceled {
                        continuation.resume(throwing: AuthError.cancelled)
                    } else {
                        continuation.resume(throwing: AuthError.unknown(error.localizedDescription))
                    }
                    return
                }
                guard let idToken = result?.user.idToken?.tokenString else {
                    continuation.resume(
                        throwing: AuthError.unknown("Google sign-in didn't return an ID token.")
                    )
                    return
                }
                continuation.resume(returning: idToken)
            }
        }
    }

    private static func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive })
            .flatMap { $0 as? UIWindowScene }?
            .keyWindow?.rootViewController
    }
}
