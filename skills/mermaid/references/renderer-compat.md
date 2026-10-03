# Renderer compatibility and validation

## The breaker list (things that actually fail to render)

| breaker | symptom | fix |
|---|---|---|
| bare word `end` as node id/label | flowchart parse fails (reserved word) | rename (`done`, `end_`) or quote it |
| `%%{` / `%%}` inside a `%% ` comment | directive-like text in a comment | reword; `%% ` is a comment, `%%{...}%%` is a directive |
| unquoted label containing `;(){}[]` | parse error or truncated label | always quote: `A["label;with;semis"]` |
| nested shapes (`A[["x"]]`) | invalid in flowcharts | use a classDef for emphasis instead |
| semicolons in sequence labels | treated as statement separators | reword the label |
| init block not first line of the fence | theme silently not applied | init above `flowchart`; frontmatter above that |
| two diagrams in one host page | earlier init themeVariables leak into the later block | one diagram per file |

## Version drift

The consuming hosts (a Gitea web UI, Obsidian on a laptop) bundle
whatever mermaid version the maintainer last shipped; assume it is not
the newest. Both render the v8.7 floor in `theming.md`. Do not use
v11/v12-only syntax in committed docs until you have verified the
specific host parses it.

## You do not control placement

Dagre is the only layout you can rely on: no manual node placement, no
edge routing. Steer it structurally:

- `flowchart LR` vs `TB` (LR reads as a left-to-right dependency flow)
- subgraphs to cluster related nodes (max two levels)
- reduce edge count before adding labels; dedupe same-type edges into
  the same target (label only the first)
- keep node labels short (~24 chars)

## The validation ladder

1. **Breaker-check** (offline, always): `scripts/mermaid-check` lints a
   fence or a whole markdown file for the table above.
2. **Optional: mermaid-cli**: `npx @mermaid-js/mermaid-cli`
   (`mmdc -i in.mmd -o out.png`; pulls a Chromium, so it is heavy). Use
   for pixel-exact artifacts (report attachments).
3. **The consuming renderer (mandatory before "done")**: the host's
   rendered/preview view (for Gitea: the file view with the render
   toggle, logged in, **hard refresh after push**: browsers cache
   rendered SVGs aggressively; if you see the old version after a push,
   first suspect the push, then the cache). Plus your local markdown app
   for the other theme perspective. Validate in the renderer that will
   consume it, not just a local preview.

## Data hygiene (graph data files)

- Internal identifiers (container ids, hostnames) belong in the private
  repo's data files, never in public repos or public render services.
- If your repo runs a redactor with a hex-string heuristic, store
  content hashes as `sha256:<64-hex>`; bare 64-hex strings get mangled
  (this has burned a first graph commit).
- If the graph is generated, the data file is the source of truth:
  validation records are append-only, node status is computed from the
  latest record, never stored alongside the node.
