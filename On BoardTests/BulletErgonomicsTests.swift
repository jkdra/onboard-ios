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
