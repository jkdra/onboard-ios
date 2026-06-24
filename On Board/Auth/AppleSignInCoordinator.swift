//
//  AppleSignInCoordinator.swift
//  On Board
//

import AuthenticationServices
import CryptoKit
import Foundation

enum AppleSignInCoordinator {
    /// Result of an authorization request, paired with the raw nonce that must
    /// be forwarded to Supabase so its hash matches the one Apple signed.
    struct Authorization {
        let credential: ASAuthorizationAppleIDCredential
        let rawNonce: String
    }

    @MainActor
    static func requestAuthorization(scopes: [ASAuthorization.Scope] = [.email, .fullName]) async throws -> Authorization {
        let rawNonce = AppleNonce.randomNonce()
        let hashedNonce = AppleNonce.sha256Hex(rawNonce)

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = scopes
        request.nonce = hashedNonce

        let controller = ASAuthorizationController(authorizationRequests: [request])
        let authorization = try await controller.performRequests()

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.unknown("Could not read your Apple ID credential.")
        }
        return Authorization(credential: credential, rawNonce: rawNonce)
    }

    static func idToken(from credential: ASAuthorizationAppleIDCredential) throws -> String {
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            throw AuthError.unknown("Could not read your Apple ID token.")
        }
        return idToken
    }

    static func fullName(from credential: ASAuthorizationAppleIDCredential) -> String? {
        credential.fullName?.formatted()
    }
}

/// Nonce helpers used to bind an Apple ID token to a single sign-in attempt.
/// Supabase's GoTrue compares `sha256_hex(rawNonce)` to the `nonce` claim Apple
/// embedded in the ID token, so the hash we hand Apple must be lowercase hex.
enum AppleNonce {
    static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length

        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                // Fall back to arc4random; preferable to crashing the sign-in flow.
                randoms = (0..<randoms.count).map { _ in UInt8.random(in: .min ... .max) }
            }

            for random in randoms where remaining > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension ASAuthorizationController {
    @MainActor
    func performRequests() async throws -> ASAuthorization {
        let delegate = AuthorizationDelegate()
        self.delegate = delegate
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            self.performRequests()
        }
    }
}

@MainActor
private final class AuthorizationDelegate: NSObject, ASAuthorizationControllerDelegate {
    var continuation: CheckedContinuation<ASAuthorization, any Error>?

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        continuation?.resume(returning: authorization)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: any Error
    ) {
        continuation?.resume(throwing: error)
    }
}
