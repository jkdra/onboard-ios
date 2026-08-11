//
//  LegalService.swift
//  On Board
//
//  NOTE: This is the one service that talks to Supabase directly rather than
//  through a protocol + factory (AuthService / BoardService / OnboardingService).
//  It's a single read-only fetch of public content with an explicit
//  `.unavailable` fallback for unconfigured builds, so the mock seam hasn't
//  been worth the ceremony yet — if it grows, give it the standard
//  protocol + factory treatment.
//

import Foundation
import Supabase

enum LegalServiceError: Error {
    /// No Supabase client (mock/unconfigured build) — fall back to the web page.
    case unavailable
    case notFound
}

/// Read-only fetch of the latest published version of a policy. Public content,
/// so no auth is required; a build without Supabase configured throws
/// `.unavailable` and the caller offers the web page instead.
enum LegalService {
    static func fetch(_ type: LegalDocumentType) async throws -> LegalDocument {
        guard let client = SupabaseClientFactory.client(for: .current) else {
            throw LegalServiceError.unavailable
        }
        let rows: [LegalDocument] = try await client
            .rpc("get_legal_document", params: ["p_type": type.rawValue])
            .execute()
            .value
        guard let doc = rows.first else { throw LegalServiceError.notFound }
        return doc
    }

    /// Records acceptance of the CURRENT terms + privacy versions via the
    /// `accept_legal_documents` RPC (auth-guarded server-side; writes
    /// `profiles.terms_accepted_version` / `privacy_accepted_version`).
    /// Fire-and-forget by design, like `accept_pledge` beside it: the pledge
    /// moment is the user's explicit agreement, and dismissal must never wait
    /// on network. Failures are silent — the columns stay NULL and the next
    /// signed pledge (or a future re-acceptance prompt) retries; a missing
    /// client (mock/unconfigured build) is a no-op.
    static func acceptCurrentDocuments() async {
        guard let client = SupabaseClientFactory.client(for: .current) else { return }
        do {
            async let terms = fetch(.terms)
            async let privacy = fetch(.privacy)
            let (termsVersion, privacyVersion) = try await (terms.version, privacy.version)
            try await client
                .rpc("accept_legal_documents", params: [
                    "p_terms_version": termsVersion,
                    "p_privacy_version": privacyVersion,
                ])
                .execute()
        } catch {
            // Silent by the read-vs-write rule's spirit: this is a background
            // bookkeeping write the user never sees; nothing rolls back.
        }
    }
}
