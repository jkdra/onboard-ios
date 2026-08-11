//
//  LegalDocument.swift
//  On Board
//
//  A versioned Terms/Privacy document served by the backend (`legal_documents`
//  + the `get_legal_document` RPC) and rendered natively by PolicyView. Hosting
//  the canonical text server-side lets us update it once, show it in-app, and
//  drive a "your terms changed" prompt off the version number.
//

import Foundation

/// NOTE: NO explicit snake_case CodingKeys — the Supabase client decodes with
/// `convertFromSnakeCase`, so `doc_type`/`effective_at`/`requires_reacceptance`
/// map to these camelCase properties automatically. Adding snake_case
/// CodingKeys here would break decoding (see the BoardJSON landmine in
/// CLAUDE.md). `effectiveAt` is kept as a String to avoid any date-strategy
/// mismatch — it's display-only.
struct LegalDocument: Decodable, Sendable, Equatable {
    let docType: String
    let version: Int
    let effectiveAt: String?
    let content: String
    let summary: String?
    let requiresReacceptance: Bool
}

enum LegalDocumentType: String, CaseIterable {
    case terms
    case privacy

    var title: String {
        switch self {
        case .terms: "Terms of Service"
        case .privacy: "Privacy Policy"
        }
    }

    /// Web fallback if the native fetch fails (offline, or a build with no
    /// Supabase configured).
    var webURL: URL {
        switch self {
        case .terms: AppLinks.termsOfServiceURL
        case .privacy: AppLinks.privacyPolicyURL
        }
    }
}
