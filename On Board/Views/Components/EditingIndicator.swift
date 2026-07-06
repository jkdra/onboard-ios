//
//  EditingIndicator.swift
//  On Board
//
//  Cycling "EDITING." / "EDITING.." / "EDITING..." marquee shown in
//  the post detail edit banner. Uses `TimelineView` so SwiftUI drives
//  the tick — no manual `Timer` to keep in sync with view lifetime.
//

import SwiftUI

struct EditingIndicator: View {
    /// How long each dot phase is held on screen.
    var period: TimeInterval = 0.4

    var body: some View {
        TimelineView(.periodic(from: .now, by: period)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate / period) % 3
            let dots = String(repeating: ".", count: phase + 1)
            Text("EDITING\(dots)")
        }
    }
}

#Preview {
    NavigationStack {
        EditingIndicator()
            .fontStyle(.title3)
    }
}
