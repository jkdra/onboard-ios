//
//  PostMarkupTests.swift
//  On BoardTests
//
//  Pins the syntax contract in
//  docs/superpowers/specs/2026-08-06-post-rich-text.md. These are cross-client
//  rules — Android and web implement the same table — so a failure here means
//  the same post would render differently on different platforms.
//

import Testing
@testable import On_Board

@MainActor
struct PostMarkupTests {

    // MARK: - Block markers require column zero AND a trailing space

    @Test func titleNeedsHashSpaceAtLineStart() {
        let markup = PostMarkup.parse("# Finals week")
        #expect(markup.blocks.count == 1)
        #expect(markup.blocks[0].kind == .title)
        #expect(markup.blocks[0].plainText == "Finals week")
    }

    @Test func subtitleUsesDoubleHash() {
        let markup = PostMarkup.parse("## Study group")
        #expect(markup.blocks[0].kind == .subtitle)
        #expect(markup.blocks[0].plainText == "Study group")
    }

    /// The whole reason for the space rule: hashtag muscle memory must not
    /// produce a surprise headline.
    @Test func hashtagWithoutSpaceIsPlainText() {
        let markup = PostMarkup.parse("#finals anyone?")
        #expect(markup.blocks[0].kind == .body)
        #expect(markup.blocks[0].plainText == "#finals anyone?")
    }

    @Test func hashMidLineIsPlainText() {
        let markup = PostMarkup.parse("I got a #1 ranking")
        #expect(markup.blocks[0].kind == .body)
        #expect(markup.blocks[0].plainText == "I got a #1 ranking")
        // Nothing to dim — the composer must not grey out ordinary punctuation.
        #expect(markup.spans.allSatisfy { !$0.isMarker })
    }

    @Test func indentedHashIsPlainText() {
        let markup = PostMarkup.parse("   # not a title")
        #expect(markup.blocks[0].kind == .body)
        #expect(markup.blocks[0].plainText == "   # not a title")
    }

    // MARK: - Bullets vs italic

    @Test func asteriskSpaceIsBullet() {
        let markup = PostMarkup.parse("* milk")
        #expect(markup.blocks[0].kind == .bullet)
        #expect(markup.blocks[0].plainText == "milk")
    }

    /// `*italic*` at line start must stay italic — no space after the `*`, so
    /// it is not a bullet. This is the collision the space rule resolves.
    @Test func asteriskWithoutSpaceAtLineStartIsItalicNotBullet() {
        let markup = PostMarkup.parse("*emphasis* here")
        #expect(markup.blocks[0].kind == .body)
        #expect(markup.blocks[0].plainText == "emphasis here")
        #expect(markup.blocks[0].runs.first?.traits == .italic)
    }

    // MARK: - Inline traits

    @Test func boldItalicUnderlineStrikethrough() {
        #expect(PostMarkup.parse("**b**").blocks[0].runs[0].traits == .bold)
        #expect(PostMarkup.parse("*i*").blocks[0].runs[0].traits == .italic)
        #expect(PostMarkup.parse("__u__").blocks[0].runs[0].traits == .underline)
        #expect(PostMarkup.parse("~~s~~").blocks[0].runs[0].traits == .strikethrough)
    }

    @Test func tripleAsteriskStacksBoldAndItalic() {
        let run = PostMarkup.parse("***both***").blocks[0].runs[0]
        #expect(run.traits == [.bold, .italic])
        #expect(run.text == "both")
    }

    @Test func traitsNest() {
        let markup = PostMarkup.parse("**bold __and underlined__**")
        let underlined = markup.blocks[0].runs.first { $0.traits.contains(.underline) }
        #expect(underlined?.traits == [.bold, .underline])
    }

    // MARK: - False positives the flanking rule must reject

    @Test func arithmeticIsNotItalic() {
        let markup = PostMarkup.parse("5 * 3 * 2 = 30")
        #expect(markup.blocks[0].plainText == "5 * 3 * 2 = 30")
        #expect(markup.spans.allSatisfy { !$0.isMarker })
    }

    /// Italic is `*` only, never `_` — this is what keeps snake_case safe.
    /// A single underscore is never a delimiter, so ordinary identifiers and
    /// filenames pass through untouched.
    @Test func snakeCaseSurvivesIntact() {
        for sample in ["snake_case_word", "some_file_name.txt", "a_b_c_d"] {
            #expect(PostMarkup.parse(sample).blocks[0].plainText == sample,
                    "mangled: \(sample)")
        }
    }

    /// KNOWN, ACCEPTED TRADE-OFF of `__` meaning underline: a dunder name is
    /// indistinguishable from underline markup, so `__init__` underlines
    /// "init". Far narrower than `_single_` italic would be (that would break
    /// every snake_case identifier), and vanishingly rare in a campus post —
    /// but it is real, so it is pinned rather than wished away. If this ever
    /// becomes a problem the fix is an escape, not a delimiter change.
    @Test func doubleUnderscoreUnderlinesEvenInDunderNames() {
        let markup = PostMarkup.parse("__init__ method")
        #expect(markup.blocks[0].plainText == "init method")
        #expect(markup.blocks[0].runs.first?.traits == .underline)
    }

    @Test func unmatchedDelimiterIsLiteral() {
        let markup = PostMarkup.parse("**never closed")
        #expect(markup.blocks[0].plainText == "**never closed")
    }

    // MARK: - Multi-line

    @Test func linesBecomeSeparateBlocks() {
        let markup = PostMarkup.parse("# Title\nbody text\n* one\n* two")
        #expect(markup.blocks.map(\.kind) == [.title, .body, .bullet, .bullet])
        #expect(markup.plainText == "Title\nbody text\none\ntwo")
    }

    @Test func blankLinesArePreserved() {
        let markup = PostMarkup.parse("first\n\nsecond")
        #expect(markup.blocks.count == 3)
        #expect(markup.blocks[1].plainText.isEmpty)
    }

    // MARK: - Source spans drive the composer

    /// Marker spans must cover exactly the delimiters and nothing else — the
    /// composer dims these, so an off-by-one greys out real text.
    @Test func markerSpansCoverOnlyDelimiters() {
        let source = "# Hey **there**"
        let markup = PostMarkup.parse(source)
        let dimmed = markup.spans.filter(\.isMarker).map { String(source[$0.range]) }
        #expect(dimmed == ["# ", "**", "**"])
    }

    @Test func contentSpansReconstructTheSourceWithoutMarkers() {
        let source = "## Plans\n~~cancelled~~ moved"
        let markup = PostMarkup.parse(source)
        let content = markup.spans.filter { !$0.isMarker }
            .map { String(source[$0.range]) }.joined()
        #expect(content == "Plans\ncancelled moved")
    }

    /// The composer renders by walking spans in order, so every character of
    /// the source — including newlines — must be covered exactly once. A gap
    /// silently drops text from the live preview.
    @Test func spansTileTheSourceExactly() {
        let source = "# Title\n**bold** and *it*\n* bullet"
        let markup = PostMarkup.parse(source)
        let rebuilt = markup.spans.map { String(source[$0.range]) }.joined()
        #expect(rebuilt == source)
    }

    @Test func emptySourceProducesOneEmptyBody() {
        let markup = PostMarkup.parse("")
        #expect(markup.blocks.count == 1)
        #expect(markup.blocks[0].kind == .body)
        #expect(markup.plainText.isEmpty)
    }
}
