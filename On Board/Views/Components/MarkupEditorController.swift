//
//  MarkupEditorController.swift
//  On Board
//
//  Split out of MarkupTextEditor.swift — the shared handle between the
//  SwiftUI toolbar and the UIKit text view. See MarkupTextEditor.swift's
//  header for the composer's invariant and the five rules.
//

import SwiftUI
import UIKit

// MARK: - Controller (toolbar → editor bridge)

/// Shared handle between the SwiftUI toolbar and the UIKit text view. The
/// toolbar calls the apply methods; the coordinator keeps `currentBlock`
/// fresh so the style menu reports the caret's line.
@MainActor @Observable
final class MarkupEditorController {
    weak var textView: UITextView?
    var currentBlock: PostBlockKind = .body
    /// The inline traits considered "applied" at the current caret/selection —
    /// drives the toolbar's highlighted state. Caret: the traits of the run
    /// the caret sits in. Selection: a trait is active only if EVERY selected
    /// character carries it.
    var activeTraits: InlineTraits = []
    /// Bumped by the coordinator after any programmatic edit so SwiftUI
    /// pulls the new text into the binding.
    /// (Not fileprivate: set by MarkupTextEditor.swift's `makeUIView`.)
    var onProgrammaticChange: (() -> Void)?

    static func trait(for delimiter: String) -> InlineTraits {
        switch delimiter {
        case "**": .bold
        case "*": .italic
        case "__": .underline
        case "~~": .strikethrough
        default: []
        }
    }

    private static func traits(forToken token: String) -> InlineTraits {
        switch token {
        case "***": [.bold, .italic]
        default: trait(for: token)
        }
    }

    func applyInline(_ delimiter: String) {
        guard let textView else { return }
        let trait = Self.trait(for: delimiter)

        // Toggle OFF: the trait is already applied here — remove the
        // enclosing pair for the WHOLE run, whether the user has a bare
        // caret, a partial selection, or the exact run selected.
        if activeTraits.contains(trait) {
            removeEnclosingPair(for: trait)
            onProgrammaticChange?()
            return
        }

        let selection = textView.selectedRange
        guard let uiSelection = uiRange(textView, selection) else { return }
        let selected = textView.text(in: uiSelection) ?? ""
        if selected.isEmpty {
            // Insert a pair, park the caret between them.
            textView.replace(uiSelection, withText: delimiter + delimiter)
            textView.selectedRange = NSRange(location: selection.location + delimiter.count, length: 0)
        } else {
            textView.replace(uiSelection, withText: delimiter + selected + delimiter)
            // KEEP the text selected (shifted past the opening delimiter) —
            // collapsing to the end forces reselection for every follow-up.
            textView.selectedRange = NSRange(location: selection.location + delimiter.count,
                                             length: (selected as NSString).length)
        }
        onProgrammaticChange?()
    }

    /// Removes the delimiter pair introducing `trait` around the caret /
    /// selection. Handles the stacked token: un-bolding `***x***` leaves
    /// `*x*`, un-italicising it leaves `**x**`.
    private func removeEnclosingPair(for trait: InlineTraits) {
        guard let textView else { return }
        let sourceText = textView.text ?? ""
        let markup = PostMarkup.parse(sourceText)
        let selection = textView.selectedRange
        let probe = selection.length > 0
            ? selection.location
            : max(selection.location - 1, 0)

        // The content span carrying the trait at the probe point.
        guard let anchorIndex = markup.spans.firstIndex(where: { span in
            guard !span.isMarker, span.traits.contains(trait) else { return false }
            let range = NSRange(span.range, in: sourceText)
            return probe >= range.location && probe <= range.upperBound
        }) else { return }

        func tokenText(_ span: PostMarkup.Span) -> String { String(sourceText[span.range]) }

        // Nearest introducing marker before the anchor, and its mate after.
        guard let openIndex = stride(from: anchorIndex - 1, through: 0, by: -1).first(where: { index in
            let span = markup.spans[index]
            return span.isMarker && Self.traits(forToken: tokenText(span)).contains(trait)
        }) else { return }
        guard let closeIndex = ((anchorIndex + 1)..<markup.spans.count).first(where: { index in
            let span = markup.spans[index]
            return span.isMarker && tokenText(span) == tokenText(markup.spans[openIndex])
        }) else { return }

        let token = tokenText(markup.spans[openIndex])
        // Removing bold ("**") from "***" must leave "*"; every plain token
        // removes to nothing.
        let replacement = reducedToken(token, removing: trait)

        let openNS = NSRange(markup.spans[openIndex].range, in: sourceText)
        let closeNS = NSRange(markup.spans[closeIndex].range, in: sourceText)

        // Back to front so the open range stays valid.
        if let closeRange = uiRange(textView, closeNS) { textView.replace(closeRange, withText: replacement) }
        if let openRange = uiRange(textView, openNS) { textView.replace(openRange, withText: replacement) }

        // Restore something sensible: the original selection shifted by the
        // characters removed ahead of it.
        let removedAhead = openNS.length - (replacement as NSString).length
        let newLocation = max(selection.location - (selection.location > openNS.location ? removedAhead : 0), 0)
        textView.selectedRange = NSRange(location: newLocation, length: selection.length)
    }

    private func reducedToken(_ token: String, removing trait: InlineTraits) -> String {
        if token == "***" {
            return trait == .bold ? "*" : trait == .italic ? "**" : ""
        }
        return ""
    }

    func refreshActiveTraits() {
        guard let textView, let sourceText = textView.text, !sourceText.isEmpty else {
            activeTraits = []
            return
        }
        let markup = PostMarkup.parse(sourceText)
        let selection = textView.selectedRange
        let contentSpans = markup.spans.filter { !$0.isMarker }

        if selection.length == 0 {
            let probe = max(selection.location - 1, 0)
            let hit = contentSpans.first { span in
                let range = NSRange(span.range, in: sourceText)
                return probe >= range.location && probe < range.upperBound
            }
            activeTraits = hit?.traits.subtracting(.tag) ?? []
        } else {
            // Intersection over every content span the selection overlaps.
            var intersection: InlineTraits? = nil
            for span in contentSpans {
                let range = NSRange(span.range, in: sourceText)
                guard NSIntersectionRange(range, selection).length > 0 else { continue }
                intersection = intersection.map { $0.intersection(span.traits) } ?? span.traits
            }
            activeTraits = intersection?.subtracting(.tag) ?? []
        }
    }

    private func uiRange(_ textView: UITextView, _ range: NSRange) -> UITextRange? {
        guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: start, offset: range.length) else { return nil }
        return textView.textRange(from: start, to: end)
    }

    /// Line-scoped styles. Applying to a partial selection promotes it onto
    /// its own line (split before and after); returning to Body strips the
    /// marker and deliberately does NOT rejoin lines (spec: undo symmetry is
    /// not worth the edge cases).
    func applyBlock(_ kind: PostBlockKind) {
        guard let textView else { return }
        let text = textView.text as NSString
        var selection = textView.selectedRange

        let prefix: String = switch kind {
        case .title: "# "
        case .subtitle: "## "
        case .body, .bullet: ""
        }

        // Promote a partial selection onto its own line first.
        if selection.length > 0, kind == .title || kind == .subtitle {
            let lineRange = text.lineRange(for: selection)
            let selEndsBeforeLineEnd = selection.upperBound < lineRange.upperBound
                && text.character(at: selection.upperBound - 1) != 0x0A
            let selStartsAfterLineStart = selection.location > lineRange.location
            if selEndsBeforeLineEnd, let range = textRange(textView, selection.upperBound, 0) {
                textView.replace(range, withText: "\n")
            }
            if selStartsAfterLineStart, let range = textRange(textView, selection.location, 0) {
                textView.replace(range, withText: "\n")
                selection.location += 1
            }
        }

        // Re-read the text (splits above may have changed it), then rewrite
        // the prefix of every touched line.
        let updated = textView.text as NSString
        var lineStart = updated.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let touched = updated.lineRange(for: NSRange(location: selection.location, length: max(selection.length, 0)))
        var offsets: [(NSRange, String)] = []
        while lineStart < touched.upperBound {
            let line = updated.lineRange(for: NSRange(location: lineStart, length: 0))
            let lineText = updated.substring(with: line)
            let existing = lineText.hasPrefix("## ") ? 3 : lineText.hasPrefix("# ") ? 2 : 0
            offsets.append((NSRange(location: line.location, length: existing), prefix))
            lineStart = line.upperBound
            if line.length == 0 { break }
        }
        // Back to front so earlier ranges stay valid.
        for (range, replacement) in offsets.reversed() {
            if let textRange = textRange(textView, range.location, range.length) {
                textView.replace(textRange, withText: replacement)
            }
        }
        onProgrammaticChange?()
    }

    private func textRange(_ textView: UITextView, _ location: Int, _ length: Int) -> UITextRange? {
        guard let start = textView.position(from: textView.beginningOfDocument, offset: location),
              let end = textView.position(from: start, offset: length) else { return nil }
        return textView.textRange(from: start, to: end)
    }
}
