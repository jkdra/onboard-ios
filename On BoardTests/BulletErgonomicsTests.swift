import Testing
import Foundation
@testable import On_Board

// Pins the bullet-list editing behaviors (continue / exit / un-bullet) and
// the body-only display tiers. All ranges are UTF-16 offsets per NSRange.
@MainActor
struct BulletErgonomicsTests {
    private func nsLength(_ s: String) -> Int { (s as NSString).length }

    // MARK: Return continues a non-empty bullet

    @Test func returnAtEndOfBulletContinuesList() {
        let text = "- first item"
        let caret = NSRange(location: nsLength(text), length: 0)
        let edit = MarkupEditorController.bulletReturnEdit(text: text, replacementRange: caret)
        #expect(edit == .init(range: caret, replacement: "\n- ", caret: caret.location + 3))
    }

    @Test func returnPreservesStarMarkerVariant() {
        let text = "* starred"
        let caret = NSRange(location: nsLength(text), length: 0)
        let edit = MarkupEditorController.bulletReturnEdit(text: text, replacementRange: caret)
        #expect(edit?.replacement == "\n* ")
    }

    @Test func returnMidBulletSplitsIntoTwoBullets() {
        let text = "- first item"
        let caret = NSRange(location: 7, length: 0) // between "first" and " item"
        let edit = MarkupEditorController.bulletReturnEdit(text: text, replacementRange: caret)
        #expect(edit == .init(range: caret, replacement: "\n- ", caret: 10))
    }

    @Test func returnOnSecondLineBulletUsesThatLine() {
        let text = "intro line\n- item"
        let caret = NSRange(location: nsLength(text), length: 0)
        let edit = MarkupEditorController.bulletReturnEdit(text: text, replacementRange: caret)
        #expect(edit?.replacement == "\n- ")
    }

    // MARK: Return exits an empty bullet

    @Test func returnOnEmptyBulletExitsList() {
        let text = "- item\n- "
        let caret = NSRange(location: nsLength(text), length: 0)
        let edit = MarkupEditorController.bulletReturnEdit(text: text, replacementRange: caret)
        // Strips the trailing "- " line entirely, swallows the newline.
        #expect(edit == .init(range: NSRange(location: 7, length: 2), replacement: "", caret: 7))
    }

    @Test func returnOnWhitespaceOnlyBulletExitsList() {
        let text = "- item\n-  "
        let caret = NSRange(location: nsLength(text), length: 0)
        let edit = MarkupEditorController.bulletReturnEdit(text: text, replacementRange: caret)
        #expect(edit == .init(range: NSRange(location: 7, length: 3), replacement: "", caret: 7))
    }

    // MARK: Return leaves everything else alone

    @Test func returnOnBodyAndHeadingLinesIsDefault() {
        for text in ["plain body", "# heading", "## subtitle", ""] {
            let caret = NSRange(location: nsLength(text), length: 0)
            #expect(MarkupEditorController.bulletReturnEdit(text: text, replacementRange: caret) == nil)
        }
    }

    // MARK: Backspace un-bullets

    @Test func backspaceAfterMarkerDeletesWholeMarker() {
        let text = "- item"
        // Backspace at caret 2 arrives as deletion of {1,1}.
        let widened = MarkupEditorController.bulletBackspaceRange(text: text, deletionRange: NSRange(location: 1, length: 1))
        #expect(widened == NSRange(location: 0, length: 2))
    }

    @Test func backspaceAfterSecondLineMarkerWidens() {
        let text = "intro\n- item"
        let widened = MarkupEditorController.bulletBackspaceRange(text: text, deletionRange: NSRange(location: 7, length: 1))
        #expect(widened == NSRange(location: 6, length: 2))
    }

    @Test func backspaceElsewhereIsDefault() {
        let text = "- item"
        // Mid-content, inside the marker's first char, and multi-char selections.
        #expect(MarkupEditorController.bulletBackspaceRange(text: text, deletionRange: NSRange(location: 4, length: 1)) == nil)
        #expect(MarkupEditorController.bulletBackspaceRange(text: text, deletionRange: NSRange(location: 0, length: 1)) == nil)
        #expect(MarkupEditorController.bulletBackspaceRange(text: text, deletionRange: NSRange(location: 0, length: 3)) == nil)
    }
}

@MainActor
struct BodyOnlyTierTests {
    @Test func shortBodyOnlyPostIsExtraLarge() {
        #expect(PostMarkup.parse("who's at the library rn").bodyOnlyTier == .extraLarge)
    }

    @Test func middlingBodyOnlyPostIsLarge() {
        let text = String(repeating: "a", count: 100)
        #expect(PostMarkup.parse(text).bodyOnlyTier == .large)
    }

    @Test func longBodyOnlyPostIsStandard() {
        let text = String(repeating: "a", count: 200)
        #expect(PostMarkup.parse(text).bodyOnlyTier == .standard)
    }

    @Test func anyStructuralMarkupStandsDown() {
        #expect(PostMarkup.parse("# short").bodyOnlyTier == .standard)
        #expect(PostMarkup.parse("## short").bodyOnlyTier == .standard)
        #expect(PostMarkup.parse("- short").bodyOnlyTier == .standard)
    }

    @Test func emptyContentIsStandard() {
        #expect(PostMarkup.parse("").bodyOnlyTier == .standard)
    }

    /// The composer must publish what it previewed: the editor's body size
    /// and the detail renderer's tier come from one table.
    @Test func composerBodySizeMatchesTheTierRamp() {
        #expect(MarkupStyler.bodySize(for: .extraLarge) == 20)
        #expect(MarkupStyler.bodySize(for: .large) == 18)
        #expect(MarkupStyler.bodySize(for: .standard) == 17)
    }

    /// Body-only emphasis is a UI step (~1.2), never the editorial-headline
    /// ratio (1.5) it shipped as — 26pt on a 17pt body read as a title.
    @Test func bodyOnlyEmphasisStaysBelowHeadlineRatio() {
        let standard = MarkupStyler.bodySize(for: .standard)
        let biggest = MarkupStyler.bodySize(for: .extraLarge)
        #expect(biggest / standard <= 1.25)
        #expect(biggest > standard) // still visibly the main event
    }

    /// Adding a heading stands the tier down, so the composer's body size
    /// settles back to base — the size is the feedback that structure took.
    @Test func addingAHeadingReturnsTheComposerToBaseSize() {
        let bodyOnly = PostMarkup.parse("who's at the library rn")
        let withHeading = PostMarkup.parse("# study group\nwho's at the library rn")
        #expect(MarkupStyler.bodySize(for: bodyOnly.bodyOnlyTier) == 20)
        #expect(MarkupStyler.bodySize(for: withHeading.bodyOnlyTier) == 17)
    }

    @Test func boundariesAreExact() {
        #expect(PostMarkup.parse(String(repeating: "a", count: 80)).bodyOnlyTier == .extraLarge)
        #expect(PostMarkup.parse(String(repeating: "a", count: 81)).bodyOnlyTier == .large)
        #expect(PostMarkup.parse(String(repeating: "a", count: 140)).bodyOnlyTier == .large)
        #expect(PostMarkup.parse(String(repeating: "a", count: 141)).bodyOnlyTier == .standard)
    }

    @Test func inlineTraitsDoNotStandDown() {
        // Bold/italic/tags are still "body-only" — only STRUCTURE stands down.
        #expect(PostMarkup.parse("**loud** short post #tag").bodyOnlyTier == .extraLarge)
    }
}

@MainActor
struct VerboseAgeTests {
    private func age(minutesAgo: Double) -> String {
        Date.now.addingTimeInterval(-minutesAgo * 60).boardVerboseAge
    }

    @Test func spellsOutRecentAges() {
        #expect(age(minutesAgo: 0.2) == "just now")
        #expect(age(minutesAgo: 1) == "1 min ago")
        #expect(age(minutesAgo: 45) == "45 mins ago")
        #expect(age(minutesAgo: 60) == "1 hour ago")
        #expect(age(minutesAgo: 60 * 5) == "5 hours ago")
        #expect(age(minutesAgo: 60 * 24) == "1 day ago")
        #expect(age(minutesAgo: 60 * 24 * 3) == "3 days ago")
    }

    /// Past a week the week-count stops being placeable, so it becomes the
    /// calendar date.
    @Test func olderThanAWeekBecomesADate() {
        let old = Date.now.addingTimeInterval(-60 * 60 * 24 * 9)
        let parts = Calendar.current.dateComponents([.month, .day], from: old)
        #expect(old.boardVerboseAge == "\(parts.month!)-\(parts.day!)")
    }

    /// The compact form is unchanged — dense surfaces still use it.
    @Test func compactFormIsUntouched() {
        #expect(Date.now.addingTimeInterval(-30).boardRelativeAge == "now")
        #expect(Date.now.addingTimeInterval(-60 * 5).boardRelativeAge == "5m")
        #expect(Date.now.addingTimeInterval(-60 * 60 * 24 * 2).boardRelativeAge == "2d")
    }
}
