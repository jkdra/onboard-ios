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
//  Split across files (all in Components/): MarkupEditorController.swift
//  (toolbar → editor bridge), MarkupStyler.swift (attribute derivation),
//  ComposerToolbar.swift (the formatting bar + accessory root).
//

import SwiftUI
import UIKit

// MARK: - The representable

struct MarkupTextEditor: UIViewRepresentable {
    @Binding var text: String
    let controller: MarkupEditorController
    var placeholder = "what's on your mind?"
    var autoFocus = true

    /// The accessory bar lives in the KEYBOARD's view hierarchy, not this
    /// view's, so it inherits nothing from the SwiftUI environment — traits
    /// (dark mode, Dynamic Type) still arrive through UIKit, but a
    /// config-driven `EnvironmentValue` would silently read its default. The
    /// glass kill switch matters on iOS 26+, where the bar IS glass, so it is
    /// re-injected onto the hosted root by hand (see `ComposerAccessoryRoot`).
    @Environment(\.glassEffectsEnabled) private var glassEffectsEnabled

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

        // The formatting bar IS the keyboard's toolbar. It used to be a
        // `.safeAreaInset` on each host screen, which left it parked at the
        // bottom of the sheet with the keyboard down — formatting controls
        // for a field nobody was editing. `placement: .keyboard` can't do
        // this job either: SwiftUI attaches that group to ITS OWN text
        // inputs, and never sees a bridged UITextView. An input accessory
        // is the real thing — present exactly while this view is first
        // responder, and moving as part of the keyboard rather than chasing
        // it through inset math (this codebase has been bitten by stale
        // keyboard insets more than once).
        let root = ComposerAccessoryRoot(controller: controller, glassEnabled: glassEffectsEnabled)
        let host = UIHostingController(rootView: root)
        context.coordinator.accessoryHost = host
        textView.inputAccessoryView = ComposerAccessoryContainer(host: host)

        if autoFocus {
            // Next runloop: the sheet's presentation must settle first.
            DispatchQueue.main.async { textView.becomeFirstResponder() }
        }
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // Keep the injected kill switch current — nothing else crosses into
        // the keyboard's hierarchy on its own.
        context.coordinator.accessoryHost?.rootView.glassEnabled = glassEffectsEnabled

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
        /// Retained here — the container holds the hosting controller's VIEW,
        /// and a released controller stops driving it.
        var accessoryHost: UIHostingController<ComposerAccessoryRoot>?

        init(text: Binding<String>, controller: MarkupEditorController) {
            self.text = text
            self.controller = controller
        }

        func textViewDidChange(_ textView: UITextView) {
            textDidChange(textView)
        }

        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText replacement: String) -> Bool {
            // Rule 2 applies here too: never intervene mid-composition.
            guard textView.markedTextRange == nil else { return true }

            if replacement == "\n",
               let edit = MarkupEditorController.bulletReturnEdit(
                   text: textView.text, replacementRange: range
               ) {
                apply(edit.range, edit.replacement, caret: edit.caret, in: textView)
                return false
            }
            if replacement.isEmpty,
               let widened = MarkupEditorController.bulletBackspaceRange(
                   text: textView.text, deletionRange: range
               ) {
                apply(widened, "", caret: widened.location, in: textView)
                return false
            }
            return true
        }

        /// Routes through `textView.replace` (not raw textStorage) so the
        /// edit registers with undo and fires the normal didChange pipeline
        /// (restyle, binding sync, intrinsic-size invalidation).
        private func apply(_ range: NSRange, _ replacement: String, caret: Int, in textView: UITextView) {
            guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                  let end = textView.position(from: start, offset: range.length),
                  let textRange = textView.textRange(from: start, to: end) else { return }
            textView.replace(textRange, withText: replacement)
            textView.selectedRange = NSRange(location: caret, length: 0)
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

// MARK: - Keyboard accessory

/// Host for the formatting bar above the keyboard. The chrome follows the
/// KEYBOARD'S OWN SHAPE, which changed between eras:
///
/// * **iOS 18–25** — the keyboard is edge to edge, so the bar is too.
///   `UIInputView(inputViewStyle: .keyboard)` is the primitive Apple's own
///   accessory bars are built on: it paints the REAL keyboard background
///   rather than a material chosen to resemble one, so bar and keys read as
///   one continuous surface with no seam to tune.
/// * **iOS 26+** — the keyboard became a FLOATING, inset, rounded panel. A
///   full-bleed bar there overhangs it on both sides and meets its rounded
///   top with square corners. So the container goes styleless (`.default`
///   paints nothing) and `ComposerToolbar` draws a glass capsule inset to
///   match, floating just above the keys. Verified by screenshot on both —
///   full bleed looked right on 18 and wrong under Liquid Glass.
///
/// The sizing dance is common to both: `inputAccessoryView` takes UIKit's
/// default 44pt unless the view opts in with `.flexibleHeight`, and the height
/// must be re-derived rather than frozen so a Dynamic Type change grows the bar
/// instead of cropping it.
private final class ComposerAccessoryContainer: UIInputView {
    private let host: UIHostingController<ComposerAccessoryRoot>

    init(host: UIHostingController<ComposerAccessoryRoot>) {
        self.host = host
        // `.default` is the styleless one — on iOS 26+ the capsule is the
        // chrome, and a keyboard-styled container behind it would be a second
        // surface stacked under a floating element.
        let style: UIInputView.Style = if #available(iOS 26.0, *) { .default } else { .keyboard }
        super.init(frame: .zero, inputViewStyle: style)
        allowsSelfSizing = true
        autoresizingMask = .flexibleHeight
        // Without this the hosting controller pads the bar with the window's
        // bottom safe-area inset — 34pt of dead space between the bar and the
        // keyboard it is supposed to be sitting on. The keyboard already covers
        // the home indicator; the accessory must not inset for it too.
        host.safeAreaRegions = []
        // Clear so the container's own material shows through (pre-26). Do NOT
        // clear the container itself there — that is the material.
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: Self, _) in
            view.invalidateIntrinsicContentSize()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unused") }

    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
        let fitting = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: fitting.height)
    }
}
