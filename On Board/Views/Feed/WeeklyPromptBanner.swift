//
//  WeeklyPromptBanner.swift
//  On Board
//
//  The board's weekly prompt shown quietly at the top of the composer — a
//  conversation starter, never a required field. Deliberately styled as info
//  (a hairline chip), NOT as one of the glass input fields, so it doesn't read
//  as something to tap or fill, and it stays cohesive with the final-hour
//  notice that shares the top of the composer. The caller resolves the prompt
//  string (profanity-gated) and only mounts this when a prompt exists, so there
//  is no "no prompt this week" filler in the composer.
//

import SwiftUI

struct WeeklyPromptBanner: View {
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("This week", systemImage: "quote.bubble.fill")
                .fontStyle(.caption2)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            Text(prompt)
                .fontStyle(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 0.8))
        // Read as one unit to VoiceOver: "This week, <prompt>".
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack {
        WeeklyPromptBanner(prompt: "What's the best album you've listened to this week?")
        Spacer()
    }
    .padding()
}
