//
//  ButlerFont.swift
//  On Board
//
//  Butler (Fabian De Smet) — a high-contrast display serif, free for commercial
//  use. Used *only* for On Board First Class display text: the "First Class"
//  wordmark and plan names. Body and UI text stay on the app's ZalandoSans
//  `.fontStyle` — high-contrast serifs get fragile at small sizes and in long
//  runs, so this is deliberately display-only.
//
//  `Font.custom(_:size:relativeTo:)` scales with Dynamic Type via `relativeTo:`,
//  exactly like `FontStyles.swift`, so First Class display text grows with the
//  user's text-size setting. PostScript names ("Butler-Free-Blk"/"-Med") were
//  read directly from the bundled OTFs; registered in `On-Board-Info.plist`
//  under `UIAppFonts`. Standard Butler, not the Stencil cut (see the First
//  Class design spec for why).
//

import SwiftUI

public enum ButlerFont {
    /// Butler ExtraBold — for the big "First Class" wordmark. Chosen over the
    /// heavier Black cut: Black reads slightly clunky at large display sizes,
    /// ExtraBold keeps the same dramatic contrast while staying cleaner.
    public static func extraBold(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .largeTitle) -> Font {
        .custom("Butler-Free-XBd", size: size, relativeTo: textStyle)
    }

    /// Butler Medium — for plan names, the boarding-pass eyebrow, and (as the
    /// screen's one deliberate exception) perk titles on the First Class
    /// screen. Perk *blurbs* stay on the system font — only titles get the
    /// display serif, so reading text stays legible at small sizes.
    public static func medium(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .title3) -> Font {
        .custom("Butler-Free-Med", size: size, relativeTo: textStyle)
    }
}
