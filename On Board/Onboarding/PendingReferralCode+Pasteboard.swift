//
//  PendingReferralCode+Pasteboard.swift
//  On Board
//
//  Deferred deep-link fallback for invite codes. A universal link only reaches
//  the app when it's ALREADY installed; a user who taps an invite link without
//  the app gets sent to TestFlight/App Store instead, and the code would be
//  lost. To bridge that gap, the web invite page copies the invite URL to the
//  clipboard before handing the user off, and the freshly-installed app reads it
//  back here so the code is pre-filled — the user never has to type it.
//
//  (Firebase Dynamic Links, the old way to do this, shut down in Aug 2025, and
//  Apple ships no first-party deferred deep link. Clipboard hand-off is the
//  pragmatic, SDK-free approach and the only one that works during TestFlight.)
//

import UIKit

extension PendingReferralCode {
    /// Codes are 4–16 unambiguous ASCII alphanumerics — mirrors the web
    /// `CODE_PATTERN` and `generate_referral_code`. Anything else is rejected.
    static func isValidCode(_ s: String) -> Bool {
        (4...16).contains(s.count) && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// Pull a referral code out of clipboard text — an invite URL
    /// (`https://onboardapp.org/invite/<code>`, `onboard://invite/<code>`, or a
    /// `?code=` query) or a bare code. Returns the canonical lowercase code, or
    /// nil if the text isn't an invite.
    static func extractInviteCode(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidCode(trimmed) { return trimmed.lowercased() }

        guard let comps = URLComponents(string: trimmed) else { return nil }
        let parts = comps.path.split(separator: "/").map(String.init)

        // https://onboardapp.org/invite/<code>
        if let idx = parts.firstIndex(of: "invite"), idx + 1 < parts.count,
           isValidCode(parts[idx + 1]) {
            return parts[idx + 1].lowercased()
        }
        // onboard://invite/<code>  (code is the first path component; host == "invite")
        if comps.host == "invite", let first = parts.first, isValidCode(first) {
            return first.lowercased()
        }
        // ...?code=<code>
        if let code = comps.queryItems?.first(where: { $0.name == "code" })?.value,
           isValidCode(code) {
            return code.lowercased()
        }
        return nil
    }

    /// If no invite code is pending yet, try to recover one the web invite page
    /// stashed on the clipboard (see file header). Safe to call on every
    /// onboarding entry — it no-ops once a code exists.
    ///
    /// Privacy: gated behind `detectedPatterns(for: [\.probableWebURL])`, which
    /// inspects the clipboard WITHOUT surfacing the "pasted from…" banner and
    /// WITHOUT exposing its contents. Only a clipboard that actually holds a URL
    /// is ever read, so a user who didn't arrive from an invite is never read
    /// and never sees a paste banner.
    @MainActor
    static func hydrateFromPasteboardIfNeeded() async {
        guard (UserDefaults.standard.string(forKey: key) ?? "").isEmpty else { return }

        let pasteboard = UIPasteboard.general
        guard pasteboard.hasStrings else { return }

        // Banner-free peek: does the clipboard hold a URL-like string at all?
        // `detectedPatterns(for:)` (iOS 15+, key-path based) reports which
        // patterns match WITHOUT exposing contents, so the system shows no
        // paste notification. (The older enum-based `detectPatterns(for:
        // completionHandler:)` was deprecated in iOS 15 in favour of this.)
        let webURLKey: PartialKeyPath<UIPasteboard.DetectedValues> = \.probableWebURL
        let detected = (try? await pasteboard.detectedPatterns(for: [webURLKey])) ?? []
        guard detected.contains(webURLKey) else { return }

        guard let raw = pasteboard.string, let code = extractInviteCode(from: raw) else { return }
        store(code)
    }
}
