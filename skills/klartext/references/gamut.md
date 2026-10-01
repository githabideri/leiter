# The gamut

The phrase and structure families that make prose read as
machine-generated, with examples and the move for each. Compiled from
the sources listed in [SKILL.md](../SKILL.md); the family list follows
theclaymethod/unslop, the ranking follows the 90k-post study.

Severity: **hard** = always a tell in prose; **soft** = a register
guard that a real author's voice can override. Quoted spans,
blockquotes, and code fences are out of scope everywhere.

## Openers, emphasis, inflation

| Family (severity) | Caught examples | The move |
|---|---|---|
| Throat-clearing openers (hard) | "Here's the thing:", "The uncomfortable truth is", "Let me be clear", "It turns out", "Let's dive in", "Let's unpack" | Start with the claim |
| Emphasis crutches (hard) | "Full stop.", "Let that sink in.", "Make no mistake", "Read that again.", "This cannot be overstated." | Delete; say the thing once, plainly |
| The "X is real" closer (hard) | "The struggle is real.", "The stakes are real." | Delete (spare the literal "is this genuine?" sense) |
| Significance inflation (hard) | "stands as a testament to", "a pivotal moment", "an enduring legacy", "a rich tapestry", "the cornerstone of", "holds great promise" | Name the specific thing, or cut the clause |
| False agency (hard) | "the numbers speak for themselves", "the data tells a story", "paints a clear picture" | Make the subject human: "the numbers show" |

## Contrast, questions, drama

| Family (severity) | Caught examples | The move |
|---|---|---|
| Negative parallelism (hard) | "It's not X, it's Y", "Not only… but also", "Not merely X, but Y", "No X, no Y, just Z" | Say the positive claim; keep only when correcting a real misconception |
| Contrastive definitions (soft) | "X isn't a Y, it's a Z" | Keep when it distinguishes X from the thing readers actually confuse it with |
| Wh-opener self-Q&A (hard) | "Why does this matter? Because…", "What does this mean for…?", "Why should you care?" | State the answer, drop the question |
| Cliffhanger fragments (soft) | "[Noun]. That's it. That's the [thing].", "X things. One thing." | Keep only in chat/social cadence |
| Hedge stacks (soft) | "(and perhaps more importantly, …)", "(arguably …)", "While X is promising, Y remains a challenge" | Take the side, or cut the hedge |

## Attribution, flattery, jargon

| Family (severity) | Caught examples | The move |
|---|---|---|
| Vague attribution (hard) | "Experts argue", "Studies show", "Some critics" (attribution forms stay clean: "Smith argues") | Name the source, or make the claim and own it |
| Reader-addressing flattery (hard) | "Here's what's interesting", "worth reading", "worth your time", "Whether you're a seasoned X or just starting out" | Delete |
| Business-jargon collocations (soft) | "navigate challenges", "leverage synergies", "deep dive", "circle back", "move the needle", "low-hanging fruit" | Concrete verb, or plain words |
| Marketing/headline cadence (hard) | "world-class", "state-of-the-art", "a hidden gem", two-beat imperative slogans, three or more short-line headers in a row | State the property ("fast", "current"), not the halo |

## Residue

| Family (severity) | Caught examples | The move |
|---|---|---|
| Chatbot artifacts (hard) | "I hope this helps", "Certainly!", "Great question!", "as an AI language model", "as of my knowledge cutoff" | Delete |
| Em-dash overuse (hard) | Two or more em dashes in one paragraph; also the tight unspaced "word—word" habit | Zero by default; comma, colon, or new sentence |
| Reasoning-chain leaks (hard) | "Let me think step by step", "Breaking this down", "Here's my thought process" | Delete |
| Decorative emoji as section headers (hard) | 🚩, ✅, 🧵 standing in for headings | Replace with words |

## Structural (the scanners' territory; the ear's domain)

Document-shape tells, each measurable but easily faked in both
directions, so treat them as flags to read, not rules to auto-fix:

- **Uniform sentence rhythm** (`sentence_burstiness`, `paragraph_cv`):
  the metronome. Fix by varying length around the point.
- **Triad density**: the rule of three added when only two elements
  exist. Keep triads where three things really are the case.
- **Connective scaffolds**: paragraphs opening with "However,"
  "Moreover," "Furthermore," "It's worth noting". Open with the
  paragraph's own claim.
- **Bold-label listicles standing in for prose** (soft): correct in
  reference docs, a tell in an essay.
- **Conclusion codas**: "Ultimately, …", "In the end, …" moralizing
  wrap-ups; the summary sandwich (end recaps the intro).
- **Silhouette tells** (unslop's top layer): the document following its
  own outline (headings that restate the intro), body paragraphs
  opening on discourse cues instead of claims, intro vocabulary that
  vanishes and returns at the end (the recap loop). The fix is to let
  the structure follow the argument.

## What a word list gets wrong

The lesson the 90k-post study keeps repeating: the cheap signal and the
real signal point in different directions. "However", "thus", "hence"
are the single highest keyword matches in the corpus and are cited as a
tell by no one, because they are just people writing. Meanwhile the
top-cited tells (the em dash excepted) are structural and invisible to
any keyword pass. So: use this list to *focus reading*, never to auto-
replace, and never to score a document as "human" or "AI".

## Sources

- [90,000-post study, part 2](https://www.reddit.com/r/ClaudeAI/comments/1ucpw87/i_pulled_90000_reddit_posts_about_what_makes/) (ranking, the keyword-vs-cited correction, the "stop letting the model pick the voice" fix); corpus and scanner: JCarterJohnson/vibecoded-design-tells
- [theclaymethod/unslop](https://github.com/theclaymethod/unslop), esp. `references/taboo-phrases.md` and the three scanner layers; [its benchmark results](https://github.com/theclaymethod/unslop) (latest independent run: no-ship)
- [The 6 elements of robot style](https://huntingthemuse.net/library/how-to-tell-if-writing-is-ai) (em dashes, forced sass, diction memes incl. the Helsinki student-essay surge, landscape openers, rule-of-three, boilerplate)
- Wikipedia: [Signs of AI-generated writing](https://en.wikipedia.org/wiki/Signs_of_AI-generated_writing) (community-maintained list)
- [Byk3y/no-slop](https://github.com/Byk3y/no-slop) (the Wikipedia list as a prose linter)
