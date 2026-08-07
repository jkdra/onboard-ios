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

## Open decision: iOS 18 vs 26

`TextEditor` only accepts `Binding<AttributedString>` on iOS 26+. On 18–25 it is
`Binding<String>`, which supports the toolbar (selection ranges are available
from iOS 18) but **cannot** style ranges of editable text — so no dimmed-marker
preview, and Enter-to-continue-a-bullet fights the undo stack.

Two options: version-gate the live preview (18–25 sees literal markers, which is
what Discord looked like for years), or bridge `UITextView` for one consistent
experience at meaningfully more work. Bullets are the feature that should decide
this — they are the only part needing editor *behaviour* rather than text
transformation.

## Schema

`title` and `description` collapse to one column. Migration is cheap because
boards clear weekly — 21 live rows plus the archive, concatenated
`title || E'\n\n' || description`.

The single length limit should be a remote-config key, not a compiled constant
(the old title cap was compiled at 50, and someone already hit it).

## Card treatment

Most posts will have no heading — at a 60-character median the whole post is its
own anchor, and headings earn their keep only on long posts. The grid therefore
needs two treatments, and the one to pressure-test is long-post-with-heading.
Cap what headings can do to card height, or one post with eight titles owns the
board.
