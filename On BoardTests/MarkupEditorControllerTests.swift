//
//  MarkupEditorControllerTests.swift
//  On BoardTests
//
//  The toolbar's selection semantics can't be driven by synthesized taps
//  (still broken under this Xcode), so the controller's contract is pinned
//  here against a real UITextView: apply keeps the selection, active traits
//  report applied styling, and tapping an active style removes the whole
//  enclosing pair — including the stacked *** case.
//

import Testing
import UIKit
@testable import On_Board

@MainActor
struct MarkupEditorControllerTests {

    private func makeEditor(_ text: String) -> (MarkupEditorController, UITextView) {
        let controller = MarkupEditorController()
        let textView = UITextView()
        textView.text = text
        controller.textView = textView
        return (controller, textView)
    }

    // MARK: - Apply

    @Test func wrappingKeepsTheTextSelected() {
        let (controller, textView) = makeEditor("make this bold please")
        textView.selectedRange = NSRange(location: 5, length: 9) // "this bold"
        controller.applyInline("**")
        #expect(textView.text == "make **this bold** please")
        // Selection survives, shifted past the opening delimiter.
        #expect(textView.selectedRange == NSRange(location: 7, length: 9))
    }

    @Test func caretInsertionParksBetweenTheDelimiters() {
        let (controller, textView) = makeEditor("hello ")
        textView.selectedRange = NSRange(location: 6, length: 0)
        controller.applyInline("~~")
        #expect(textView.text == "hello ~~~~")
        #expect(textView.selectedRange == NSRange(location: 8, length: 0))
    }

    // MARK: - Active traits

    @Test func activeTraitsReportInsideAStyledRun() {
        let (controller, textView) = makeEditor("so **bold** here")
        textView.selectedRange = NSRange(location: 7, length: 0) // caret in "bold"
        controller.refreshActiveTraits()
        #expect(controller.activeTraits.contains(.bold))
    }

    @Test func activeTraitsIntersectAcrossASelection() {
        let (controller, textView) = makeEditor("**bold** and plain")
        // Selection spanning styled AND plain text: no trait is fully applied.
        textView.selectedRange = NSRange(location: 2, length: 12)
        controller.refreshActiveTraits()
        #expect(controller.activeTraits.isEmpty)
    }

    @Test func caretInPlainTextReportsNothing() {
        let (controller, textView) = makeEditor("just words")
        textView.selectedRange = NSRange(location: 4, length: 0)
        controller.refreshActiveTraits()
        #expect(controller.activeTraits.isEmpty)
    }

    // MARK: - Toggle off

    /// A bare caret inside the run removes the pair for the WHOLE run.
    @Test func toggleOffFromCaretRemovesTheWholePair()  {
        let (controller, textView) = makeEditor("so **bold** here")
        textView.selectedRange = NSRange(location: 7, length: 0)
        controller.refreshActiveTraits()
        controller.applyInline("**")
        #expect(textView.text == "so bold here")
    }

    /// A partial selection of the styled text removes the whole pair too.
    @Test func toggleOffFromPartialSelectionRemovesTheWholePair() {
        let (controller, textView) = makeEditor("an __underlined run__ stays")
        textView.selectedRange = NSRange(location: 5, length: 5) // "under"
        controller.refreshActiveTraits()
        controller.applyInline("__")
        #expect(textView.text == "an underlined run stays")
    }

    /// Un-bolding the stacked token demotes *** to * (italic survives).
    @Test func unBoldingBoldItalicLeavesItalic() {
        let (controller, textView) = makeEditor("very ***much*** so")
        textView.selectedRange = NSRange(location: 9, length: 0)
        controller.refreshActiveTraits()
        #expect(controller.activeTraits.contains(.bold))
        #expect(controller.activeTraits.contains(.italic))
        controller.applyInline("**")
        #expect(textView.text == "very *much* so")
        controller.refreshActiveTraits()
        #expect(!controller.activeTraits.contains(.bold))
    }

    @Test func unItalicisingBoldItalicLeavesBold() {
        let (controller, textView) = makeEditor("very ***much*** so")
        textView.selectedRange = NSRange(location: 9, length: 0)
        controller.refreshActiveTraits()
        controller.applyInline("*")
        #expect(textView.text == "very **much** so")
    }

    // MARK: - Block styles still behave

    @Test func titleAppliesToCaretLine() {
        let (controller, textView) = makeEditor("plain line")
        textView.selectedRange = NSRange(location: 3, length: 0)
        controller.applyBlock(.title)
        #expect(textView.text == "# plain line")
    }

    @Test func bodyStripsAHeadingMarker() {
        let (controller, textView) = makeEditor("# was a title")
        textView.selectedRange = NSRange(location: 5, length: 0)
        controller.applyBlock(.body)
        #expect(textView.text == "was a title")
    }
}
