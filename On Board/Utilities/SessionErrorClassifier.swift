//
//  SessionErrorClassifier.swift
//  On Board
//

import Foundation

enum SessionErrorClassifier {
    static func isSessionExpired(_ error: Error) -> Bool {
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
