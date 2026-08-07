//
//  PostMarkup.swift
//  On Board
//
//  Parser for the post body's user-controlled formatting. See
//  docs/superpowers/specs/2026-08-06-post-rich-text.md — that spec is the
//  contract iOS, Android, and web all implement, so behaviour changes here are
//  cross-client changes.
//
//  ONE PARSE, TWO CONSUMERS. `blocks` is what the feed and detail views
//  render (markers already removed). `spans` is the same parse in *source*
//  coordinates, tagged marker-vs-content, which is what the composer uses to
//  dim the markers in place while showing the real formatting.
//
//  That split is deliberate: the composer must never dim by scanning for `#`
//  and `*` characters, or `I got a #1 ranking` greys out its own punctuation.
//  Driving both from one parse is also what guarantees the live preview and
//  the posted result cannot disagree.
//

import Foundation

struct InlineTraits: OptionSet, Hashable, Sendable {
    let rawValue: Int
    static let bold          = InlineTraits(rawValue: 1 << 0)
    static let italic        = InlineTraits(rawValue: 1 << 1)
    static let underline     = InlineTraits(rawValue: 1 << 2)
    static let strikethrough = InlineTraits(rawValue: 1 << 3)
}

enum PostBlockKind: Equatable, Sendable {
    case body, title, subtitle, bullet
}

struct PostMarkup: Equatable, Sendable {

    /// A styled slice of one block, markers already stripped.
    struct Run: Equatable, Sendable {
        let text: String
        let traits: InlineTraits
    }

    /// One line of the post. Blocks stack vertically.
    struct Block: Equatable, Sendable {
        let kind: PostBlockKind
        let runs: [Run]
        var plainText: String { runs.map(\.text).joined() }
    }

    /// A slice of the ORIGINAL string, for the composer's in-place rendering.
    struct Span: Equatable, Sendable {
        let range: Range<String.Index>
        /// Markers render dimmed; content renders with `traits` applied.
        let isMarker: Bool
        let blockKind: PostBlockKind
        let traits: InlineTraits
    }

    let blocks: [Block]
    let spans: [Span]

    /// What the post reads as with every marker removed.
    var plainText: String {
        blocks.map(\.plainText).joined(separator: "\n")
    }
}

// MARK: - Parsing

extension PostMarkup {

    /// Block markers. Only ever recognised at column zero AND followed by a
    /// space — that single rule is what stops `#finals` (hashtag muscle
    /// memory) from becoming a heading, and what stops `* ` (bullet) from
    /// fighting `*italic*`.
    private static let blockMarkers: [(prefix: String, kind: PostBlockKind)] = [
        ("## ", .subtitle),
        ("# ",  .title),
        ("* ",  .bullet),
        ("- ",  .bullet),
    ]

    /// Inline delimiters, longest first — `**` must be tried before `*`, or
    /// bold parses as two empty italics.
    private static let inlineDelimiters: [(token: [Character], traits: InlineTraits)] = [
        (Array("***"), [.bold, .italic]),
        (Array("~~"),  [.strikethrough]),
        (Array("__"),  [.underline]),
        (Array("**"),  [.bold]),
        (Array("*"),   [.italic]),
    ]

    static func parse(_ source: String) -> PostMarkup {
        // Character/Int indexing throughout, converted to String.Index once at
        // the end — String.Index arithmetic mid-parse is a correctness trap.
        let chars = Array(source)
        var positions = Array(source.indices)
        positions.append(source.endIndex)

        var blocks: [Block] = []
        var spans: [Span] = []

        var lineStart = 0
        while lineStart <= chars.count {
            var lineEnd = lineStart
            while lineEnd < chars.count, chars[lineEnd] != "\n" { lineEnd += 1 }

            var kind = PostBlockKind.body
            var contentStart = lineStart

            // Column zero only: a leading space means this is ordinary text.
            for marker in blockMarkers {
                let token = Array(marker.prefix)
                guard lineStart + token.count <= lineEnd,
                      Array(chars[lineStart..<(lineStart + token.count)]) == token
                else { continue }
                kind = marker.kind
                contentStart = lineStart + token.count
                spans.append(Span(range: positions[lineStart]..<positions[contentStart],
                                  isMarker: true, blockKind: kind, traits: []))
                break
            }

            var runs: [Run] = []
            parseInline(chars, contentStart, lineEnd, [], positions, kind, &runs, &spans)
            blocks.append(Block(kind: kind, runs: runs))

            if lineEnd >= chars.count { break }
            // The newline itself is a content span, so `spans` tiles the source
            // exactly. The composer renders by walking spans in order; a gap
            // here would silently drop line breaks from the live preview.
            spans.append(Span(range: positions[lineEnd]..<positions[lineEnd + 1],
                              isMarker: false, blockKind: kind, traits: []))
            lineStart = lineEnd + 1
        }

        return PostMarkup(blocks: blocks, spans: spans)
    }

    /// Recursive-descent inline scan over `chars[start..<end]`.
    private static func parseInline(
        _ chars: [Character],
        _ start: Int,
        _ end: Int,
        _ inherited: InlineTraits,
        _ positions: [String.Index],
        _ blockKind: PostBlockKind,
        _ runs: inout [Run],
        _ spans: inout [Span]
    ) {
        var i = start
        var literalStart = start

        func flushLiteral(upTo stop: Int) {
            guard stop > literalStart else { return }
            runs.append(Run(text: String(chars[literalStart..<stop]), traits: inherited))
            spans.append(Span(range: positions[literalStart]..<positions[stop],
                              isMarker: false, blockKind: blockKind, traits: inherited))
        }

        while i < end {
            guard let match = openerAt(chars, i, end) else { i += 1; continue }
            guard let close = closerFor(chars, match.token, after: i + match.token.count, end: end)
            else { i += 1; continue }

            flushLiteral(upTo: i)

            let openEnd = i + match.token.count
            spans.append(Span(range: positions[i]..<positions[openEnd],
                              isMarker: true, blockKind: blockKind, traits: inherited))

            parseInline(chars, openEnd, close, inherited.union(match.traits),
                        positions, blockKind, &runs, &spans)

            let closeEnd = close + match.token.count
            spans.append(Span(range: positions[close]..<positions[closeEnd],
                              isMarker: true, blockKind: blockKind, traits: inherited))

            i = closeEnd
            literalStart = i
        }
        flushLiteral(upTo: end)
    }

    /// A delimiter opens only when immediately followed by a non-space. This is
    /// what keeps `5 * 3 * 2` from italicising and `f*** ` from half-matching.
    private static func openerAt(_ chars: [Character], _ i: Int, _ end: Int)
        -> (token: [Character], traits: InlineTraits)? {
        for delimiter in inlineDelimiters {
            let stop = i + delimiter.token.count
            guard stop < end,
                  Array(chars[i..<stop]) == delimiter.token,
                  !chars[stop].isWhitespace
            else { continue }
            return (delimiter.token, delimiter.traits)
        }
        return nil
    }

    /// ...and closes only when immediately preceded by a non-space.
    private static func closerFor(_ chars: [Character], _ token: [Character],
                                  after: Int, end: Int) -> Int? {
        var j = after
        while j + token.count <= end {
            if Array(chars[j..<(j + token.count)]) == token,
               j > after, !chars[j - 1].isWhitespace {
                return j
            }
            j += 1
        }
        return nil
    }
}
