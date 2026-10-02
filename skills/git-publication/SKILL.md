---
name: git-publication
description: >-
  Publish a private git repo to the world: one-shot history sanitization
  (git-filter-repo), pre-sanitize bundles, the archive-and-rename swap,
  re-pointing clones. Use for "make repo X public", "sanitize git
  history", "remove internal identifiers from a repo", "filter-repo",
  "git bundle backup", "swap the Gitea repo". Covers the mechanics and the
  footguns (the == > no-op, micro-testing, binary blobs, gc-prune on
  re-pointed clones); which content counts as internal is the caller's
  judgment.
---

# Git Publication Skill

Making a repo with internal-identifier-laden history publishable, without
losing the original history. Run this once per repo; it is deliberately a
one-shot, not an ongoing pipeline.

## The sequence (order matters)

1. **Freeze + bundle the pre-sanitize state.** `git bundle create <f> <ref>`
   bundles **the repo of your current working directory** — a wrong CWD once
   produced a bundle of the wrong repo entirely. Verify with
   `git bundle verify` (it lists the refs) and by commit count against
   `git rev-list --count`. Store the bundle somewhere durable and private
   (convention: `backups/<repo>-pre-sanitize-<date>.bundle`). The bundle is
   the ground truth — never start the rewrite before it exists.
2. **Clean the working tree first** (normal commits): the final tip should
   already read as the publication would. The history rewrite then mostly
   just has to catch the older versions.
3. **Micro-test the replacement map** on a throwaway repo containing one
   line with every target string. This catches map-format errors that a
   real run swallows (see footguns).
4. **Fresh clone → one `git-filter-repo` run** combining:
   - `--invert-paths --path <p>` for files that must vanish entirely
     (repeated `--path` for several); pathspecs go through `--path`, not
     as bare positional arguments,
   - `--replace-text <map>` for file contents,
   - `--replace-message <map>` for commit messages — **a separate option**;
     `--replace-text` does not touch messages,
   - `--path-rename old:new` to neutralize revealing file *names*
     (e.g. data files named after hosts).
5. **Verify over the whole new history** (not the tip):
   `git grep -lIE '<pattern>' $(git rev-list --all) -- '*.md' '*.py' ...`
   per identifier class; separately check binaries (git grep reports them),
   filenames (`git ls-files | grep`), and messages
   (`git log --all --format=%B | grep`). Iterate until all classes are
   zero (or consciously accepted, e.g. a generic Unix command name).
6. **Publish** (works the same on Gitea, Gogs, and most self-hosted forges;
   GitHub differs — see below):
   - **Push-to-create works** on forges with that feature:
     `git push <remote>:<user>/<new-name>.git main` creates the repo in
     your namespace. Use a staging name if the final name is still
     occupied.
   - **The human does the name dance in the UI**: archive (or rename) the
     old tainted repo, then rename the new one to the canonical name.
     Never force-push a rewrite into the old repo — old objects would
     linger server-side; a fresh repo + rename is clean.
   - On GitHub specifically: create the repo first (empty, no README),
     `git push --force` the rewritten history to it; if a same-named repo
     exists, it must be deleted/recreated (GitHub has no archive-then-
     rename-with-new-history path that avoids the old objects).
7. **Re-point every clone** (workstation, containers): `git remote set-url
   origin <new url>`, `git fetch`, `git reset --hard origin/main`, then
   **`git gc --prune=now`** — otherwise the tainted objects stay on disk
   and any future bundle of that clone re-leaks them.

## git-filter-repo footguns (Debian 2.38, learned the hard way)

- **The `--replace-text` / `--replace-message` map file uses `==>` as the
  rule separator. The ` => ` form found in some write-ups silently no-ops
  the entire file** — the run "succeeds" and changes nothing (or changes
  only the parts a later option handled). This is the #1 reason a
  sanitization "ran" but left everything behind. Always micro-test (step 3).
  Rule lines: `literal:text==>repl`, `regex:pat==>repl`, `glob:pat==>repl`,
  `### <path>` to delete a file; a line ending `==>` with no replacement
  deletes the match.
- Regex rules are Python `re` over the **whole file content**; use `(?m)`
  for line-based rules, e.g.
  `regex:(?m)^.*?(pct exec|/etc/pve/)[^\n]*\n==>` to delete whole lines.
- Rules apply in file order — put specific rules before general ones
  (full endpoint before bare IP; a filename before a hostname substring).
- `--replace-text` skips binary blobs (and `--invert-paths` is the tool
  for those, e.g. world saves containing a player name).
- The `--*-callback` FILE options in this build were observed to be
  no-ops (import quirks) — use the map-file options; if a callback is
  truly needed, verify it fires with a marker first.

## Map discipline

- **Deletion first**: if a line/sentence exists only to describe internal
  infrastructure, delete it (a pure-ops regex line) rather than
  placeholder-izing it. No meaningless `<placeholder>` tokens.
- Where an environment *is* part of the record (a measurement ran on a
  specific box), substitute the **role** the machine plays
  ("the CPU batch box", "the 3060 card", "the game testbed") — readable in
  public, meaningless internally (the private repo + bundle hold the
  mapping).
- **Exclude vocabularies/tokenizers/dictionaries** from regex maps: generic
  word patterns over-match BPE subwords and corrupt the files. Verify
  them after the run.
- **Never collapse whitespace across a whole file** (`re.sub('  +',' ')`)
  — it destroys Python/Make indentation. If you tidy, do it on the
  non-leading part of each line only.
- After substitution, repair artifacts: doubled articles ("the the"),
  orphan punctuation, dangling parentheses — a small second pass over the
  changed files.

## The boundary this skill owns

The mechanics are here; **the judgment of what is internal is the
caller's**. Each sanitized repo typically gets its own private skill or
doc listing what its map replaced — the public repo never needs to say
what it used to say.
