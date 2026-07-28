//
//  SessionErrorClassifier.swift
//  On Board
//

import Foundation
import Supabase

enum SessionErrorClassifier {
    /// Checks typed/structured signals first, and only falls back to matching
    /// English substrings in `error.localizedDescription` for error types this
    /// app doesn't otherwise recognize. That fallback is the one path that can
    /// silently miss a session expiry on a device set to a non-English system
    /// language, since Foundation localizes `localizedDescription` for its own
    /// error domains (URLError, etc.) — the typed checks below don't have that
    /// problem: `HTTPError.response.statusCode` is a plain Int, and
    /// `PostgrestError.code`/`.message` are raw strings PostgREST always sends
    /// in English regardless of the device's locale.
    static func isSessionExpired(_ error: Error) -> Bool {
        if let httpError = error as? HTTPError, httpError.response.statusCode == 401 {
            return true
        }
        if let postgrestError = error as? PostgrestError {
            // PGRST301 is PostgREST's own code for "JWT expired".
            if postgrestError.code == "PGRST301" { return true }
            let text = (postgrestError.message + " " + (postgrestError.code ?? "")).lowercased()
            if text.contains("jwt expired") || text.contains("jwt") && text.contains("expired") {
                return true
            }
        }

        let text = error.localizedDescription.lowercased()
        if text.contains("jwt expired")
            || text.contains("session expired")
            || text.contains("invalid jwt")
            || text.contains("not authenticated")
            || text.contains("401") {
            return true
        }

        let nsError = error as NSError
        if nsError.domain.contains("Auth"), nsError.code == 401 {
            return true
        }
        return false
    }
}
