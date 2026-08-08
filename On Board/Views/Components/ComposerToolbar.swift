//
//  ComposerToolbar.swift
//  On Board
//
//  Split out of MarkupTextEditor.swift — the formatting bar hosted in the
//  keyboard's accessory (see `ComposerAccessoryContainer` there). See that
//  file's header for the composer's invariant and the five rules.
//

import SwiftUI

// MARK: - Toolbar

/// The bar's background and outer spacing, which follow the keyboard's shape
/// per era — see `ComposerAccessoryContainer` for why. Pre-26 this is a no-op:
/// the container itself is the surface, and the content runs full bleed on it.
private struct ComposerBarChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background {
                    GlassBackground(shape: Capsule(style: .continuous),
                                    fallback: AnyShapeStyle(.regularMaterial))
                }
                // Inset to clear the floating keyboard's own margins, and
                // lifted off its top edge so the capsule reads as hovering
                // above the keys rather than welded to them.
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        } else {
            content
        }
    }
}

/// What the accessory actually hosts. Exists so the hosting controller keeps a
/// concrete type (no `AnyView`) while still carrying the one environment value
/// that has to be handed across the boundary into the keyboard's hierarchy.
struct ComposerAccessoryRoot: View {
    let controller: MarkupEditorController
    var glassEnabled: Bool

    var body: some View {
        ComposerToolbar(controller: controller)
            .environment(\.glassEffectsEnabled, glassEnabled)
    }
}

/// The composer's formatting bar: style menu leading, inline styles center,
/// keyboard dismiss trailing.
///
/// Installed as the editor's `inputAccessoryView` (see `MarkupTextEditor`),
/// so it exists exactly while the field is being edited and never outlives
/// the keyboard. Don't hand it to a host screen as a `.safeAreaInset` again —
/// that's what left formatting controls sitting on screen with nothing
/// focused.
///
/// Its background is era-dependent and lives in `chrome` below: nothing at all
/// pre-26 (the container wears the keyboard's own material, and painting here
/// would stack a second surface on it), a glass capsule on 26+. Items are
/// pinned to `.primary` rather than taking the accent tint a system bar would
/// default to — this app's chrome is monochrome, and blue B/I/U/S reads as
/// someone else's toolbar.
///
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
                .padding(.vertical, 12)
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
                    .padding(.trailing, 16)
                    .padding(.leading, 10)
                    .padding(.vertical, 12)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Dismiss keyboard")
        }
        // Both: `foregroundStyle` colors the glyphs, `tint` stops the Menu and
        // the buttons from reverting to accent on press/highlight.
        .foregroundStyle(.primary)
        .tint(.primary)
        .modifier(ComposerBarChrome())
    }

    private func inlineButton(_ icon: String, _ label: String, _ delimiter: String) -> some View {
        let isActive = controller.activeTraits.contains(MarkupEditorController.trait(for: delimiter))
        return Button {
            controller.applyInline(delimiter)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 44)
                .background {
                    // Applied-state highlight; tapping again removes the
                    // modifier across the whole run. Deliberately stronger
                    // than it was on the old capsule — the keyboard's material
                    // is busier than a blurred panel, and the previous 0.14
                    // wash disappeared into it.
                    if isActive {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.primary.opacity(0.20))
                            .padding(.vertical, 5)
                    }
                }
                .contentShape(.rect)
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
