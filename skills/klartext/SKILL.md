---
name: klartext
description: Remove AI writing patterns from prose (the de-slop / unslop pass). Use when text "smells of AI", "sounds like ChatGPT", "reads robotic", or when asked to humanize, de-slop, unslop, clean up a draft, or review writing before publishing. Audit mode lists the tells and changes nothing; rewrite mode fixes them; voice mode matches the author's own writing. Genre-aware (reference docs, code) and voice-preserving. Not for code review.
license: MIT
compatibility: Any prose file or pasted text. English only; declines other languages. Works best with a sample of the author's own writing.
---

# Klartext

The de-slop pass for prose. *Klartext* is German for plain, unambiguous
speech: "Klartext reden" means to say it straight. This skill removes the
patterns that make writing read as machine-generated. It is not a
detector (it cannot prove who wrote the text), and it never adds a house
style of its own: adding a default voice to a de-sloped text just makes
the same slop in different font.

## Modes

- **audit** (default when in doubt): list the tells, one per line, with
  category and the suggested fix. Change nothing.
- **rewrite**: apply the moves below, then report what changed and what
  was left as a judgment call.
- **voice** (only when a sample of the author's own writing is at
  hand): match the author's rhythm, contractions, and where opinion
  sits. Never invent a persona. Without a sample, strip the tells and
  leave the voice alone.

## The tells, in the order an ear catches them

Ranked from an audit of ~90,000 Reddit posts about what people actually
flag (see [references/gamut.md](references/gamut.md) for the source and
the full phrase catalog).

1. **The em dash.** Default: zero. At most one per paragraph in prose;
   code comments are a different register. Replace with a comma, a
   colon, or a new sentence.
2. **Flat, uniform rhythm.** Every sentence the same length, every
   paragraph a topic plus qualifiers. Vary: a short sentence lands the
   point, a long one carries the detail. Read a paragraph aloud; if
   you can predict the beat, break it.
3. **"Not just X, it's Y"** and kin: negative parallelism, "No X, no
   Y, just Z", "X isn't a Y, it's a Z". Say the thing directly. Keep
   the form only when it corrects a real misconception ("Use pnpm, not
   npm").
4. **The wrap.** "In conclusion", "Ultimately, this reminds us that…",
   the summary sandwich (the intro previews, the ending recaps). End
   on the last real point, or cut the ending.
5. **The diction memes.** delve, leverage (as verb), seamless, tapestry,
   unlock, empower, elevate, "in today's fast-paced landscape", "in
   the dynamic world of". Replace with the concrete word, or cut the
   clause.
6. **Throat-clearing and forced sass.** "Here's the thing:", "Let me be
   clear", "Let that sink in.", "But here's the truth", "The struggle
   is real." Start with the claim.
7. **Sycophancy and the empty.** "Great question!", reader flattery,
   fluent paragraphs that make no claim. If a paragraph can be deleted
   and nothing is lost, it was filler.
8. **Boilerplate.** "As an AI language model", "I hope this helps".
   Delete.

## What not to touch

- **Genre.** Tables, numbered steps, and bold-label lists are *correct*
  in reference docs; staccato short lines are correct in chat and
  social copy. The tells above target prose.
- **Meaningful contrasts.** "A floor, not a proof", "supersede, don't
  rewrite": when a two-sided form distinguishes X from the adjacent
  concept it gets confused with, it carries information. It is not a
  tell.
- **Register words.** In legal, security, medical, and scientific text,
  hedges, negations, and scope words carry meaning ("must not", "does
  not establish causation").
- **Facts.** Numbers, names, dates, units, citations. Never change a
  magnitude: $47.3M does not become $47.3B, 150 km does not become
  150 miles.
- **Quoted examples and code fences.** When the text documents bad
  writing, the bad example is the content.

## Voice is the real fix

Stripping tells from an anonymous voice yields a cleaner anonymous
voice. All three of the sources in the gamut agree that the actual fix
is the author's voice: if samples of their own writing are available
(a few of their messages, an earlier draft), match them, sentence
length distribution and all. The final gate is a human reading a
paragraph out loud, because rhythm is the tell the ear catches before
the eye does.

## Limits (say them, don't hide them)

- Word lists over-flag. "However" matches about 6% of ordinary writing
  and is cited as a tell by 0% of people. Every flag here needs its
  context checked, and a clean pass is not proof of human authorship.
- The strongest tells (rhythm, fluent-but-empty, sycophancy) are
  judgment calls no scanner can make. The scan is a floor; the author's
  ear is the detector.

## Sources

- [90,000-post study of what people actually cite as AI tells](https://www.reddit.com/r/ClaudeAI/comments/1ucpw87/) (em dash leads; word lists point the wrong way)
- [theclaymethod/unslop](https://github.com/theclaymethod/unslop) (phrase/structure/silhouette scanners, the gamut, do-no-harm guards; its latest independent benchmark is a no-ship, which is why this skill keeps the human in the loop)
- [The 6 elements of robot style](https://huntingthemuse.net/library/how-to-tell-if-writing-is-ai)
- [Byk3y/no-slop](https://github.com/Byk3y/no-slop) (Wikipedia's [Signs of AI-generated writing](https://en.wikipedia.org/wiki/Signs_of_AI-generated_writing), as a linter)
