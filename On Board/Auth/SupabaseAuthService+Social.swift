//
//  SupabaseAuthService+Social.swift
//  On Board
//
//  Split out of SupabaseAuthService.swift — Apple and Google sign-in.
//

import AuthenticationServices
import Foundation
import Supabase
import UIKit

// Apple re-sends the full name when a user revokes and re-authorizes the app.
// Only adopt it while the profile has no chosen display name — never overwrite.
enum AppleNameAdoption {
    nonisolated static func shouldAdopt(currentDisplayName: String?) -> Bool {
        (currentDisplayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// Provides a real foreground window as the ASWebAuthenticationSession anchor.
// The SDK's default creates UIWindow() with no scene, which silently fails on iOS 16+.
private final class ForegroundWindowProvider: NSObject, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    static let shared = ForegroundWindowProvider()

    // Explicitly nonisolated so the static `shared` initializer can use it
    // without requiring a @MainActor context.
    nonisolated override init() { super.init() }

    @MainActor
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive })
            .flatMap { $0 as? UIWindowScene }?
            .keyWindow ?? ASPresentationAnchor()
    }
}

extension SupabaseAuthService {
    func signInWithApple(idToken: String, nonce: String?, fullName: String?) async throws -> AuthSession {
        let client = try requireClient()

        _ = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            )
        )

        if let fullName {
            _ = try? await client.auth.update(
                user: UserAttributes(data: ["full_name": .string(fullName)])
            )
            if let userID = client.auth.currentSession?.user.id {
                nonisolated struct NameRow: Decodable {
                    let displayName: String?
                    enum CodingKeys: String, CodingKey { case displayName = "display_name" }
                }
                do {
                    let row: NameRow = try await client
                        .from("profiles")
                        .select("display_name")
                        .eq("id", value: userID.uuidString)
                        .single()
                        .execute()
                        .value
                    if AppleNameAdoption.shouldAdopt(currentDisplayName: row.displayName) {
                        _ = try? await client
                            .from("profiles")
                            .update(["display_name": fullName])
                            .eq("id", value: userID.uuidString)
                            .execute()
                    }
                } catch {
                    // Unknown current name (fetch failed) — never risk overwriting a
                    // chosen display name. The user can set it from their profile.
                }
            }
        }

        return try await requireRefreshedSession()
    }

    func signInWithGoogle() async throws -> AuthSession {
        let client = try requireClient()

        let session: Session

        if let clientID = configuration.googleClientID {
            // Native Google Sign-In: GID SDK presents the account picker, returns an ID token,
            // which we exchange with Supabase directly without opening a browser.
            let credential = try await GoogleSignInService.signIn(clientID: clientID)
            session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .google,
                    idToken: credential.idToken,
                    nonce: credential.nonce
                )
            )
        } else {
            // Fallback: Supabase web OAuth (opens ASWebAuthenticationSession).
            guard configuration.isGoogleOAuthAvailable else {
                throw AuthError.providerUnavailable(.google)
            }
            let provider = ForegroundWindowProvider.shared
            session = try await client.auth.signInWithOAuth(provider: .google) { webSession in
                webSession.presentationContextProvider = provider
                webSession.prefersEphemeralWebBrowserSession = false
            }
        }

        let identities = try await client.auth.userIdentities()
        return Self.mapSession(session, identities: identities)
    }
}
