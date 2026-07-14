//
//  Report.swift
//  On Board
//
//  Content reporting model. Maps to the Supabase `reports` table via the
//  `report_content` RPC. Raw values must match the backend's reason check
//  constraint exactly.
//

import Foundation

/// What kind of content a report targets. Raw values match the backend's
/// `reports.target_type` check constraint.
enum ReportTargetType: String, Sendable {
    case post
    case comment
    case profile
}

/// Why content is being reported. Raw values match the backend's
/// `reports.reason` check constraint.
enum ReportReason: String, CaseIterable, Identifiable, Sendable {
    case spam
    case harassment
    case hate
    case sexual
    case violence
    case selfHarm = "self_harm"
    case misinformation
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .spam: "Spam"
        case .harassment: "Harassment or bullying"
        case .hate: "Hate speech"
        case .sexual: "Sexual content"
        case .violence: "Violence or threats"
        case .selfHarm: "Self-harm"
        case .misinformation: "Misinformation"
        case .other: "Something else"
        }
    }
}

/// A user about to be blocked, carried by the block confirmation dialog.
struct BlockCandidate: Identifiable {
    let userID: UUID
    let handle: String
    var id: UUID { userID }
}

/// A concrete thing being reported, carried by the report sheet.
enum ReportTarget: Identifiable {
    case post(Post)
    case comment(Comment, postID: UUID)
    case profile(Profile)

    var id: UUID {
        switch self {
        case .post(let post): post.id
        case .comment(let comment, _): comment.id
        case .profile(let profile): profile.id
        }
    }

    var targetType: ReportTargetType {
        switch self {
        case .post: .post
        case .comment: .comment
        case .profile: .profile
        }
    }

    /// Short description shown at the top of the report sheet.
    var summary: String {
        switch self {
        case .post(let post): "Post: “\(post.title)”"
        case .comment(let comment, _): "Comment by \(comment.author)"
        case .profile(let profile): "Profile: \(profile.handle)"
        }
    }
}
