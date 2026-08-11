# Post rich text — one field, user-controlled formatting

**Status:** in progress on `feature/rich-text-posts`
**Supersedes:** the `title` + `description` two-field post schema

## Why

Posts currently require a title *and* a body. Both are `NOT NULL`, so every post
pays a metacognitive tax — summarise the thought before writing it — and naming
things is the hard part. Production shape as of 2026-08-06 (21 posts): median
title 16 characters, median body 44, zero empty bodies. That is not a title over
a body; it is a ~60-character thought bisected by the form.

This matters more here than for most apps: the board clears every Monday, so On
Board has 52 cold starts a year. Posting friction compounds against you every
single week.

The replacement is **one field plus opt-in formatting**. Nothing is inferred —
the user always chooses, and can always see why text looks the way it does.

## The syntax

Stored as readable plain text, never as archived attributed data: the LLM
moderation judge, the admin queue, and three clients all have to read it.

| Marker | Effect | Scope |
|---|---|---|
| `# ` | Title | block |
| `## ` | Subtitle | block |
| `* ` or `- ` | Bullet | block |
| `**` | Bold | inline |
| `*` | Italic | inline |
| `__` | Underline | inline |
| `~~` | Strikethrough | inline |

**The one rule that makes this predictable:**

> A block marker counts only at **column zero** of a line and only when
> **followed by a space**. Anywhere else those characters are literal text.

So `#finals` is text, `I got a #1 ranking` is text, `   # indented` is text, and
`# Finals week` is a Title. This is what keeps hashtag muscle memory from
colliding with headings, and it is why `* ` (bullet) never fights `*italic*`.

**Soft heading cap:** a `# `/`## ` line whose content exceeds **80
characters** demotes to body text with the marker rendered literally. A
heading is an anchor, not a container — past ~80 chars it's a paragraph in a
heading's font, and one such post owns a masonry column. Demotion is visible
by design: syntax that silently vanishes is a mystery; syntax that visibly
didn't count is a lesson. Bullets are exempt. Cross-client constant:
`PostMarkup.headingContentLimit`.

**Inline hashtags are tags** (decided 2026-08-06, after the picker era):
`#word` — where the token contains at least one letter, uses `[a-z0-9-]`, and
is not glued to a preceding word character — parses as a tag run. `Post.tags`
is DERIVED from content (lowercased, unique in order of appearance, silently
capped at 3 — never error on a 4th; extras render highlighted but uncounted).
Content is the single source of truth; the server's tags table is a
denormalized index the client feeds at write time. Do NOT parse markup in a
Postgres trigger — that's parser parity in SQL, the exact drift this spec
exists to prevent. The letter rule keeps `#1` literal; the glue rule keeps
`C#minor` literal; the space rule keeps `# heading` and `#tag` permanently
disjoint. Known conscious trade-off: the old picker's search-with-post-counts
was a tag-convergence nudge — free-typed tags can fragment (`econ201` vs
`econ-201`). Accepted at current scale; the future fix is composer
autocomplete, which is additive.

**Backslash escape** (added 2026-08-07): `\` before any syntax character
(`* _ ~ # -` or `\` itself) makes it literal. The backslash is consumed —
dimmed as a marker in the composer, stripped from rendered output. Before any
other character a backslash is plain text.

Inline markers work anywhere, and **stack**: `***x***` is bold + italic. To
avoid formatting ordinary punctuation (`5 * 3 * 2`), an inline run only opens
when the delimiter is immediately followed by a non-space, and only closes when
immediately preceded by a non-space.

### Deliberate deviations from CommonMark

- `__` is **underline**, not bold. This follows Discord, where the audience
  actually lives. Consequence: a stock CommonMark renderer cannot be used on
  web — it would render underlines as bold.
- Italic is `*` only, never `_`. A single underscore is never a delimiter, so
  `snake_case` and `some_file_name.txt` pass through untouched. Do not add `_`
  emphasis later "for compatibility"; that trades user safety for a spec we
  already don't follow.
- No links (`[]()`) and no images (`![]()`). Link text that lies about its
  destination is a phishing primitive, and a remote image embed bypasses the
  moderation pipeline entirely, since the URL never touches the upload path the
  judge inspects. Not "later" — these stay out.
- Known trade-off of `__`: a dunder name (`__init__`) is indistinguishable
  from underline markup and will render underlined. Far narrower than `_`
  italic would be — that breaks every snake_case identifier — and essentially
  absent from campus posts. Pinned by test, not wished away. If it ever
  matters, add an escape rather than change the delimiter.
- Ordered lists are deliberately omitted. Bare `1 ` at line start would capture
  ordinary writing ("5 dollars for parking??"), and renumbering is real editor
  work for a format that barely appears in a 60-character post. Adding them in
  v2 is easy; removing them after people use them is not.

## Rendering: one parse, two consumers

The parser returns ranges **in source coordinates**, each tagged as marker or
content. Both consumers read the same parse:

- **Composer** renders the full source, drawing marker ranges at reduced opacity
  and applying real formatting to content ranges.
- **Feed / detail** drops marker ranges and renders content only.

This is load-bearing. Dimming must be driven by the parser, never by scanning
for `#` and `*` characters — otherwise `I got a #1 ranking` greys out its own
punctuation. One parse for both is also what proves the preview and the final
render can't diverge.

## Composer

One text field. The keyboard toolbar carries:

- **leading** — style dropdown (Title / Subtitle / Body, default Body), which
  also reports the caret line's current style
- **middle** — Bold, Italic, Underline, Strikethrough
- **trailing** — keyboard dismiss

Applying a block style to a partial selection promotes the selection onto its
own line (splitting before and after as needed). Returning to Body strips the
marker and deliberately does **not** try to rejoin the lines it split — undo
symmetry is not worth the edge cases.

## DECIDED (research pass, 2026-08-06): one bridged `UITextView` on every OS version

The version split (iOS 26 `TextEditor(AttributedString)` + degraded 18–25) was
researched and rejected: maintaining two editors with divergent
selection/undo/IME behaviour is the worst option, iOS 26's rich TextEditor
still has an open selected-text-replacement bug (Apple forums 812759) and no
UndoManager access, and ~10–15% of users (Apple adoption stats, June 2026)
would get the degraded path anyway. One `UIViewRepresentable` UITextView gives
everyone the live preview with decade-old, well-documented failure modes.

**Composer implementation rules (each one is a real shipped bug somewhere):**

- Plain `UITextView`, TextKit 2 by default — **never touch `.layoutManager`**
  (any access permanently drops that instance to TextKit 1). No NSTextStorage
  subclass.
- Characters are the ONLY state; attributes are a pure derived function of
  them. Restyle in `textViewDidChange` by running the parser over the full
  text and applying attributes in one `textStorage.beginEditing()/endEditing()`
  transaction. **Never assign `textView.attributedText`** to restyle — that
  resets selection, kills IME composition, and scrolls.
- Skip restyling while `markedTextRange != nil` (CJK composition/dictation);
  restyle after commit.
- Reset `typingAttributes` to the base style in
  `textViewDidChangeSelection`, or typing after a bold run extends it.
- Attribute-only changes need no undo registration (undo restores characters,
  didChange re-derives). Any programmatic *character* edit (toolbar inserting
  markers) must route through `replace(_:withText:)` so UIKit registers it.
- Whole-text re-parse per keystroke is microseconds at post length; don't
  build incremental range patching.

**Renderer note from the same research:** `Text` concatenation and
`Text(AttributedString)` lay out identically; the difference is that an
AttributedString can be built once and cached per post while concatenation
rebuilds O(runs) Text values every body evaluation. At current board sizes
concatenation is fine; if profiling ever flags the grid, the refactor is
mechanical (same runs → one cached AttributedString, explicit
`Font.custom(_:size:relativeTo:)` per run since size can't compose with the
environment font, SwiftUI-scope attributes only — `paragraphStyle` is ignored
by SwiftUI Text, which is why bullets are layout, not attributes).

**When Apple fixes the TextEditor bugs:** the migration is
`.onChange(of: text)` guarded on character-equality →
`text.transform(updating: &selection)` batched via RangeSet → dimming via
`AttributedTextValueConstraint`, custom keys with
`inheritedByAddedText = false` and `invalidationConditions = [.textChanged]`
(WWDC25 session 280). Parser and attribute recipes carry over unchanged.

## Schema — two-phase migration (drafted, NOT applied)

Phase 1 (safe while 1.1.x clients still write two columns): add nullable
`content`, backfill `'# ' || title`, body, then a trailing hashtag line built
from the post's existing tags. Old columns stay writable; the serving
view/RPC exposes `coalesce(content, <join>)` so both client generations read
one shape.

Phase 2 (after `min_supported_version` retires 1.1.x — the version gate is the
retirement tool, and with the current user base that's a week, not a year):
drop `title`/`description`, make `content` NOT NULL.

Draft SQL lives in `supabase/migrations/` (gitignored working copy) — apply
via MCP with explicit go-ahead only.

The single length limit should be a remote-config key, not a compiled constant
(the old title cap was compiled at 50, and someone already hit it).

## Card treatment

Most posts will have no heading — at a 60-character median the whole post is its
own anchor, and headings earn their keep only on long posts. The grid therefore
needs two treatments, and the one to pressure-test is long-post-with-heading.
Cap what headings can do to card height, or one post with eight titles owns the
board.
