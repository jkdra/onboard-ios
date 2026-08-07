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
    /// Bumped by the coordinator after any programmatic edit so SwiftUI
    /// pulls the new text into the binding.
    fileprivate var onProgrammaticChange: (() -> Void)?

    func applyInline(_ delimiter: String) {
        guard let textView, let selection = textView.selectedTextRange else { return }
        let selected = textView.text(in: selection) ?? ""
        if selected.isEmpty {
            // Insert a pair, park the caret between them.
            textView.replace(selection, withText: delimiter + delimiter)
            if let position = textView.position(from: selection.start, offset: delimiter.count) {
                textView.selectedTextRange = textView.textRange(from: position, to: position)
            }
        } else {
            textView.replace(selection, withText: delimiter + selected + delimiter)
        }
        onProgrammaticChange?()
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
            textView.invalidateIntrinsicContentSize()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Rule 3: derived styling must never leak into new typing.
            textView.typingAttributes = MarkupStyler.baseAttributes
            updateCurrentBlock(textView)
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

/// The composer's formatting bar: style menu leading, inline styles center,
/// keyboard dismiss trailing. Lives in the sheet's bottom safe-area inset so
/// it rides above the keyboard.
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
        HStack(spacing: 4) {
            Menu {
                Button("Title") { controller.applyBlock(.title) }
                Button("Subtitle") { controller.applyBlock(.subtitle) }
                Button("Body") { controller.applyBlock(.body) }
            } label: {
                HStack(spacing: 4) {
                    Text(blockLabel)
                        .fontStyle(.subheadline)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(.rect)
            }

            Spacer(minLength: 0)

            inlineButton("bold", "Bold") { controller.applyInline("**") }
            inlineButton("italic", "Italic") { controller.applyInline("*") }
            inlineButton("underline", "Underline") { controller.applyInline("__") }
            inlineButton("strikethrough", "Strikethrough") { controller.applyInline("~~") }

            Spacer(minLength: 0)

            Button {
                KeyboardDismisser.dismiss()
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
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

    private func inlineButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 36)
                .contentShape(.rect)
        }
        .accessibilityLabel(label)
    }
}
