//
//  GoogleSignInService.swift
//  On Board
//
//  Native Google Sign-In via the GoogleSignIn-iOS SDK.
//  Presents the native account picker, gets a Google ID token,
//  which SupabaseAuthService then exchanges for a Supabase session.
//

import CryptoKit
import Foundation
import GoogleSignIn
import UIKit

@MainActor
enum GoogleSignInService {
    struct Credential {
        let idToken: String
        /// The nonce embedded in the ID token. Supabase's id_token grant
        /// rejects tokens whose nonce claim has no matching request nonce
        /// ("Passed nonce and nonce in id_token should either both exist or
        /// not"), so the same value must be forwarded to signInWithIdToken.
        let nonce: String
    }

    /// Present the native Google Sign-In sheet and return the resulting ID
    /// token plus the nonce it was minted with.
    /// Throws `AuthError.cancelled` if the user dismisses the sheet.
    static func signIn(clientID: String) async throws -> Credential {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        guard let vc = topViewController() else {
            throw AuthError.unknown("Google Sign-In: no active view controller.")
        }
        let nonce = randomNonce()
        let idToken = try await idToken(presentingViewController: vc, nonce: nonce)
        return Credential(idToken: idToken, nonce: nonce)
    }

    /// Forward a URL to GIDSignIn so the SDK can finish the OAuth callback.
    /// Call this from `onOpenURL` in the app entry point.
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    // MARK: - Private

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func idToken(presentingViewController vc: UIViewController, nonce: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: vc, hint: nil, additionalScopes: nil, nonce: nonce) { result, error in
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
