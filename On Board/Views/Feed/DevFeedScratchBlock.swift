//
//  DevFeedScratchBlock.swift
//  On Board
//
//  DEV/mock-only scratch UI (Signal Lost placeholder preview, tint/aspect
//  pickers, welcome-replay button) — pulled out of ContentView.thisWeekFeed so
//  that already-large, frequently-diffed view doesn't also carry ~50 lines of
//  scratch controls that only ever render in mock builds. See
//  ContentView.hidesDevBlock for when this actually shows.
//

import SwiftUI

struct DevFeedScratchBlock: View {
    @Binding var showWelcomeReplay: Bool

    // DEV-only: refine the Signal Lost image placeholder against a real load.
    @State private var devShowLoadedImage = false
    @State private var devPlaceholderTint: PostTone?
    /// Preview aspect ratio (width / height), matching post.imageAspectRatio.
    @State private var devAspect: Double = 0.8

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // DEV (mock builds): flip between the Signal Lost
            // placeholder and a real loaded image to refine the
            // placeholder's look at post-image proportions.
            Group {
                if devShowLoadedImage {
                    BoardAsyncImage(
                        url: URL(string: "https://picsum.photos/seed/onboard/\(max(1, Int(1000 * devAspect)))/1000"),
                        tone: devPlaceholderTint ?? .blue
                    )
                } else {
                    SignalLostPlaceholder(tint: devPlaceholderTint?.color)
                }
            }
            // Frame to the chosen aspect ratio — the same thing
            // GridCard does with post.imageAspectRatio, so the
            // placeholder sits in the exact frame the image will.
            .frame(maxWidth: .infinity)
            .aspectRatio(devAspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Toggle("Show loaded image", isOn: $devShowLoadedImage)
                .tint(.primary)

            Picker("Placeholder tint", selection: $devPlaceholderTint) {
                Text("Monochrome").tag(PostTone?.none)
                ForEach(PostTone.allCases) { tone in
                    Text(tone.displayName).tag(PostTone?.some(tone))
                }
            }
            .pickerStyle(.menu)

            Picker("Aspect ratio", selection: $devAspect) {
                Text("Portrait 4:5").tag(0.8)
                Text("Tall 3:4").tag(0.75)
                Text("Square 1:1").tag(1.0)
                Text("Photo 3:2").tag(1.5)
                Text("Landscape 16:9").tag(16.0 / 9.0)
            }
            .pickerStyle(.menu)

            Button("Replay Welcome [DEV]") {
                showWelcomeReplay = true
            }
            .foregroundStyle(.secondary)
        }
        .fontStyle(.footnote)
        .padding(.horizontal)
        .padding(.top, 4)
    }
}
