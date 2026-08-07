//
//  MarkupTextEditor.swift
//  On Board
//
//  The rich post composer: a bridged UITextView that live-renders board
//  markup as you type — markers dimmed in place, real formatting on the text
//  between them (Bear/Obsidian style). One editor on EVERY OS version; the
//  iOS 26 AttributedString TextEditor was researched and rejected (spec:
//  2026-08-06-post-rich-text.md, "DECIDED" section).
//
//  THE INVARIANT: characters are the only state. Attributes are a pure
//  function of the text, recomputed from PostMarkup.parse — the SAME parser
//  the feed renders with, so the preview cannot disagree with the posted
//  result. Styling is applied in-place on the text storage; the string
//  binding, undo, autocorrect, and dictation never know formatting exists.
//
//  The five rules (each one is a shipped bug somewhere, see spec):
//  1. Never assign `textView.attributedText` to restyle — in-place
//     `textStorage` edits only, inside one beginEditing/endEditing.
//  2. Skip restyling while `markedTextRange != nil` (CJK/dictation
//     composition); restyle after commit.
//  3. Reset `typingAttributes` on selection change, or typing after a bold
//     run extends the bold.
//  4. Programmatic CHARACTER edits (toolbar inserting markers) go through
//     `textView.replace(_:withText:)` so UIKit registers undo.
//  5. Never touch `.layoutManager` (drops TextKit 2 → TextKit 1).
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
    fileprivate var onProgrammaticChange: (() -> Void)?

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

// MARK: - The representable

struct MarkupTextEditor: UIViewRepresentable {
    @Binding var text: String
    let controller: MarkupEditorController
    var placeholder = "what's on your mind?"
    var autoFocus = true

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.keyboardType = .twitter
        textView.autocapitalizationType = .sentences
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.typingAttributes = MarkupStyler.baseAttributes

        let placeholderLabel = UILabel()
        placeholderLabel.text = placeholder
        placeholderLabel.font = MarkupStyler.baseFont
        placeholderLabel.textColor = .tertiaryLabel
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
        ])
        context.coordinator.placeholderLabel = placeholderLabel

        controller.textView = textView
        controller.onProgrammaticChange = { [weak textView, weak coordinator = context.coordinator] in
            guard let textView, let coordinator else { return }
            coordinator.textDidChange(textView)
        }

        if autoFocus {
            // Next runloop: the sheet's presentation must settle first.
            DispatchQueue.main.async { textView.becomeFirstResponder() }
        }
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // External writes only (draft restore, dev prefill) — the common case
        // is our own binding echo, which this guard turns into a no-op.
        if textView.text != text {
            textView.text = text
            context.coordinator.restyle(textView)
            context.coordinator.placeholderLabel?.isHidden = !text.isEmpty
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(160, fitting.height))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, controller: controller)
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        let text: Binding<String>
        let controller: MarkupEditorController
        var placeholderLabel: UILabel?

        init(text: Binding<String>, controller: MarkupEditorController) {
            self.text = text
            self.controller = controller
        }

        func textViewDidChange(_ textView: UITextView) {
            textDidChange(textView)
        }

        func textDidChange(_ textView: UITextView) {
            // Rule 2: never restyle mid-composition (CJK, dictation).
            if textView.markedTextRange == nil {
                restyle(textView)
            }
            text.wrappedValue = textView.text
            placeholderLabel?.isHidden = !textView.text.isEmpty
            updateCurrentBlock(textView)
            controller.refreshActiveTraits()
            textView.invalidateIntrinsicContentSize()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Rule 3: derived styling must never leak into new typing.
            textView.typingAttributes = MarkupStyler.baseAttributes
            updateCurrentBlock(textView)
            controller.refreshActiveTraits()
        }

        /// One parse, applied in-place. Attribute-only edits preserve the
        /// caret and scroll position, and register nothing with undo — undo
        /// restores characters, this re-derives.
        func restyle(_ textView: UITextView) {
            let markup = PostMarkup.parse(textView.text)
            let storage = textView.textStorage
            storage.beginEditing()
            storage.setAttributes(MarkupStyler.baseAttributes,
                                  range: NSRange(location: 0, length: storage.length))
            for span in markup.spans {
                let nsRange = NSRange(span.range, in: textView.text)
                storage.setAttributes(MarkupStyler.attributes(for: span), range: nsRange)
            }
            storage.endEditing()
        }

        private func updateCurrentBlock(_ textView: UITextView) {
            let text = textView.text as NSString
            guard text.length > 0 else { controller.currentBlock = .body; return }
            let caret = min(textView.selectedRange.location, text.length)
            let line = text.lineRange(for: NSRange(location: caret, length: 0))
            let lineText = text.substring(with: line)
            controller.currentBlock = lineText.hasPrefix("## ") ? .subtitle
                : lineText.hasPrefix("# ") ? .title
                : lineText.hasPrefix("* ") || lineText.hasPrefix("- ") ? .bullet
                : .body
        }
    }
}

// MARK: - Styling

/// UIKit mirror of PostMarkupText's font logic: same families, same
/// composer-appropriate scale, same synthesized oblique for the italic the
/// Zalando family doesn't ship.
enum MarkupStyler {
    static let baseFont = UIFont(name: "ZalandoSansSemiExpanded-Regular", size: 17)
        ?? .systemFont(ofSize: 17)

    static var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        return [.font: baseFont, .foregroundColor: UIColor.label, .paragraphStyle: paragraph]
    }

    static func attributes(for span: PostMarkup.Span) -> [NSAttributedString.Key: Any] {
        var attributes = baseAttributes
        attributes[.font] = font(kind: span.blockKind, traits: span.traits)
        if span.isMarker {
            // The dim that makes the syntax feel inert: visible enough to
            // edit, quiet enough that the CONTENT reads as the post.
            attributes[.foregroundColor] = UIColor.label.withAlphaComponent(0.32)
        } else {
            if span.traits.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if span.traits.contains(.underline) {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
        }
        return attributes
    }

    private static func font(kind: PostBlockKind, traits: InlineTraits) -> UIFont {
        let (family, size, baseWeight): (String, CGFloat, UIFont.Weight?) = switch kind {
        case .title: ("ZalandoSansExpanded-Regular", 26, .heavy)
        case .subtitle: ("ZalandoSansExpanded-Regular", 19, .semibold)
        case .body, .bullet: ("ZalandoSansSemiExpanded-Regular", 17, nil)
        }
        var weight = baseWeight
        if traits.contains(.bold) { weight = .bold }
        if traits.contains(.tag), weight == nil { weight = .semibold }

        let base = UIFont(name: family, size: size) ?? .systemFont(ofSize: size)
        var descriptor = base.fontDescriptor
        var attributes: [UIFontDescriptor.AttributeName: Any] = [:]
        if let weight {
            // These are VARIABLE fonts (wght axis, verified in the TTFs'
            // fvar tables) — a UIFontDescriptor weight trait silently no-ops
            // on them; drive the axis directly. Caught on-simulator: the
            // title rendered regular-weight while italic's matrix worked.
            let wghtAxis = 0x77676874 // 'wght'
            let value: CGFloat = switch weight {
            case .heavy: 800
            case .bold: 700
            default: 600
            }
            let variationKey = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
            attributes[variationKey] = [wghtAxis: value]
        }
        if traits.contains(.italic) {
            attributes[.matrix] = CGAffineTransform(a: 1, b: 0, c: tan(CGFloat.pi / 15), d: 1, tx: 0, ty: 0)
        }
        if !attributes.isEmpty {
            descriptor = descriptor.addingAttributes(attributes)
        }
        return UIFont(descriptor: descriptor, size: size)
    }
}

// MARK: - Toolbar

/// The composer's formatting bar: tone swatch + style menu leading, inline
/// styles center, keyboard dismiss trailing. Lives in the sheet's bottom
/// safe-area inset so it rides above the keyboard — which is also why the
/// tone control lives HERE and not in the toolbar's bottomBar: a bottomBar
/// sits underneath the keyboard on iOS 18, making the old placement
/// unreachable during the entire time anyone is actually typing.
/// TEXT controls only, on purpose: the post's tone lives in the nav bar's
/// principal slot instead — a color control sitting beside B/I/U/S reads as
/// text color no matter what shape it takes (learned the hard way).
struct ComposerToolbar: View {
    let controller: MarkupEditorController

    private var blockLabel: String {
        switch controller.currentBlock {
        case .title: "Title"
        case .subtitle: "Subtitle"
        case .body, .bullet: "Body"
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Menu {
                Button("Title") { controller.applyBlock(.title) }
                Button("Subtitle") { controller.applyBlock(.subtitle) }
                Button("Body") { controller.applyBlock(.body) }
            } label: {
                HStack(spacing: 4) {
                    Text(blockLabel)
                        .fontStyle(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        // Fixed slot sized to the widest label ("Subtitle") so
                        // the center cluster never shifts when the style
                        // changes — a wandering B/I/U/S row reads as broken.
                        .frame(width: 64, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.leading, 16)
                .padding(.vertical, 13)
                .contentShape(.rect)
            }

            Spacer(minLength: 0)

            inlineButton("bold", "Bold", "**")
            inlineButton("italic", "Italic", "*")
            inlineButton("underline", "Underline", "__")
            inlineButton("strikethrough", "Strikethrough", "~~")

            Spacer(minLength: 0)

            Button {
                KeyboardDismisser.dismiss()
            } label: {
                Text("Done")
                    .fontStyle(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 13)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Dismiss keyboard")
        }
        .foregroundStyle(.primary)
        .background {
            GlassBackground(shape: Capsule(style: .continuous),
                            fallback: AnyShapeStyle(.regularMaterial))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func inlineButton(_ icon: String, _ label: String, _ delimiter: String) -> some View {
        let isActive = controller.activeTraits.contains(MarkupEditorController.trait(for: delimiter))
        return Button {
            controller.applyInline(delimiter)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 46)
                .background {
                    // Subtle applied-state highlight; tapping again removes
                    // the modifier across the whole run.
                    if isActive {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.primary.opacity(0.14))
                            .padding(.vertical, 6)
                    }
                }
                .contentShape(.rect)
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
