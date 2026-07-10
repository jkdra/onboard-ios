//
//  SupabaseBoardService+Moderation.swift
//  On Board
//
//  Reporting and blocking. Reports go through the `report_content` RPC
//  (validation + dedupe live server-side); blocks are direct table writes
//  guarded by RLS (a user can only manage rows where they are the blocker).
//

import Foundation
import Supabase

extension SupabaseBoardService {
    func reportContent(
        targetType: ReportTargetType,
        targetID: UUID,
        reason: ReportReason,
        details: String?
    ) async throws {
        struct Params: Encodable {
            let pTargetType: String
            let pTargetId: UUID
            let pReason: String
            let pDetails: String?
        }
        try await mapAuthErrors {
            _ = try await client
                .rpc("report_content", params: Params(
                    pTargetType: targetType.rawValue,
                    pTargetId: targetID,
                    pReason: reason.rawValue,
                    pDetails: details?.trimmed.isEmpty == false ? details?.trimmed : nil
                ))
                .execute()
        }
    }

    func blockUser(blockedID: UUID) async throws {
        struct Row: Encodable {
            let blockerId: UUID
            let blockedId: UUID
        }
        guard let userID = try? await client.auth.session.user.id else {
            throw BoardServiceError.notAuthenticated
        }
        // ignoreDuplicates is required, not optional: without it this upserts via
        // ON CONFLICT DO UPDATE, and `blocks` (by design) has no UPDATE policy, so
        // re-blocking an already-blocked user would be rejected by RLS.
        try await mapAuthErrors {
            _ = try await client
                .from("blocks")
                .upsert(Row(blockerId: userID, blockedId: blockedID), onConflict: "blocker_id,blocked_id", ignoreDuplicates: true)
                .execute()
        }
    }

    func unblockUser(blockedID: UUID) async throws {
        guard let userID = try? await client.auth.session.user.id else {
            throw BoardServiceError.notAuthenticated
        }
        try await mapAuthErrors {
            _ = try await client
                .from("blocks")
                .delete()
                .eq("blocker_id", value: userID.uuidString)
                .eq("blocked_id", value: blockedID.uuidString)
                .execute()
        }
    }

    func fetchBlockedUserIDs(for userID: UUID) async throws -> [UUID] {
        struct Row: Decodable {
            let blockedId: UUID
        }
        let rows: [Row] = try await mapAuthErrors {
            try await client
                .from("blocks")
                .select("blocked_id")
                .eq("blocker_id", value: userID.uuidString)
                .execute()
                .value
        }
        return rows.map(\.blockedId)
    }

    func fetchProfiles(ids: [UUID]) async throws -> [Profile] {
        guard !ids.isEmpty else { return [] }
        return try await mapAuthErrors {
            try await client
                .from("profiles")
                .select()
                .in("id", values: ids.map(\.uuidString))
                .execute()
                .value
        }
    }
}
