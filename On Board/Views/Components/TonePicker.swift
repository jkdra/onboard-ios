//
//  TonePicker.swift
//  On Board
//
//  Compact dropdown for choosing a post's tone. Used in both the
//  new-post composer (where "Any Color!" is offered as a deferred-
//  random fallback) and the post detail edit mode (where the tone
//  is required). The trigger is a single capsule chip — same
//  general shape language as the reaction bar segments — with the
//  current swatch on the left, color name next to it, and a small
//  chevron hint. Tap opens a system Menu listing the options.
//

import SwiftUI

struct TonePicker: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var selection: PostTone?

    /// When true, "Any Color!" appears as the deferred-random option.
    /// Set to `false` when the surrounding flow requires a concrete tone.
    let includeRandom: Bool
    /// When false, renders without the capsule background — use in toolbars
    /// so the picker inherits the native toolbar material instead.
    var showBackground: Bool

    init(selection: Binding<PostTone?>, includeRandom: Bool = true, showBackground: Bool = true) {
        self._selection = selection
        self.includeRandom = includeRandom
        self.showBackground = showBackground
    }

    /// Convenience for callers holding a non-optional `PostTone` (e.g.
    /// the post-detail edit flow). Bridges to the optional binding and
    /// forces `includeRandom = false` since `nil` is not representable.
    init(selection: Binding<PostTone>, showBackground: Bool = true) {
        self._selection = Binding(
            get: { selection.wrappedValue },
            set: { newValue in
                if let newValue { selection.wrappedValue = newValue }
            }
        )
        self.includeRandom = false
        self.showBackground = showBackground
    }

    var body: some View {
        Menu {
            Picker("Tone", selection: $selection) {
                if includeRandom {
                    Text("Any Color!").tag(PostTone?.none)
                }
                ForEach(PostTone.allCases) { tone in
                    Text(tone.displayName).tag(Optional(tone))
                }
            }
        } label: {
            trigger
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var trigger: some View {
        HStack(spacing: 8) {
            swatch
                .frame(width: showBackground ? 18 : 14, height: showBackground ? 18 : 14)
            Text(selection?.displayName ?? "Any Color!")
                .fontStyle(.subheadline)
                .fontWeight(.heavy)
            Image(systemName: "chevron.down")
                .fontStyle(.caption2)
                .fontWeight(.bold)
                .opacity(0.55)
        }
        .foregroundStyle(.primary)
        .padding(showBackground ? 14 : 8)
        .background {
            if showBackground {
                Color(uiColor: .systemBackground)
                selection?.color.opacity(scheme == .dark ? 0.25 : 0.3)
            }
        }
        .clipShape(.capsule(style: .continuous))
        .overlay {
            if showBackground {
                Capsule(style: .continuous)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            }
        }
        .fixedSize()
        .contentTransition(.identity)
        .animation(.smooth(duration: 0.2), value: selection)
    }

    @ViewBuilder
    private var swatch: some View {
        if let tone = selection {
            Circle().fill(tone.color)
        } else {
            // Multicolor disc that reads as "any/random".
            Circle().fill(
                AngularGradient(
                    gradient: Gradient(colors: [
                        .red, .orange, .yellow, .green, .blue, .purple, .red
                    ]),
                    center: .center
                )
            )
        }
    }
}

#Preview {
    StatefulPreview()
        .padding()
}

private struct StatefulPreview: View {
    @State private var tone: PostTone? = nil
    var body: some View {
        VStack(spacing: 24) {
            TonePicker(selection: $tone)
            TonePicker(selection: $tone, includeRandom: false)
        }
    }
}
