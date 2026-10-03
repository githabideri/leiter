# Theming

The rule that fixes every host-theme problem: **contrast is defined
inside the node** (text colour against the node's own fill), never text
against the page background. Hosts (dark/light Gitea, any Obsidian
theme) control the page, not your diagram; any diagram that relies on
the host theme for text colour breaks on half of them. This has bitten
diagrams on dark-themed hosts repeatedly.

## The init block (paste as-is)

```
%%{init: {"theme": "base", "themeVariables": {
  "primaryColor": "#37474f", "primaryTextColor": "#eceff1",
  "primaryBorderColor": "#263238", "lineColor": "#90a4ae",
  "textColor": "#eceff1", "edgeLabelBackground": "#263238"
}}}%%
```

- First line inside the ```mermaid fence (file frontmatter, if any, must
  be line 1 of the file; the init goes above `flowchart`).
- `base` is the only modifiable theme; the directive works from v8.7+,
  so this is safe on Gitea and Obsidian regardless of their bundled
  versions or page themes.
- `textColor` + `edgeLabelBackground` make edge-label pills dark with
  light text: legible on any page theme.
- Multiple mermaid blocks on one Gitea page: a directive's
  themeVariables can leak into later blocks on that page. Keep one
  diagram per file.

## classDef recipes

Mid-dark fills with white/light text read on both light and dark pages.
**Never pastel fills**; that is the failure mode (light text on light
fill).

Health/state convention:

```
classDef neutral fill:#37474f,stroke:#263238,color:#eceff1
classDef ok      fill:#2e7d32,stroke:#1b5e20,color:#ffffff
classDef bad     fill:#c62828,stroke:#7f0000,color:#ffffff
classDef na      fill:#546e7a,stroke:#37474f,color:#eceff1
class nodeA,nodeB ok
```

Semantic families (adapted from the public mgranberry/WH-2099 mermaid
skills; use ONE family per diagram; mixing a health and a semantic
palette violates contract rule 3):

- trigger / start: amber `#ef6c00`
- success: green `#2e7d32`
- error / failure: red `#c62828`
- decision / gate: purple `#6a1b9a`
- AI / model component: teal `#00695c`

(all with `stroke:` one notch darker and `color:#ffffff`)

## Shapes by kind (flowchart)

```
A["label"]    rectangle  - consumer / component
B{"label"}    diamond    - decision / gate / classifier
C{{"label"}}  hexagon    - model / transformation
D[("label")]  cylinder   - data store / corpus
E(["label"])  stadium    - service / entry point
```

Labels always quoted; node IDs sanitized (alnum + underscore); never raw
hostnames or dotted names in IDs (they become part of the generated
mermaid identifier).

## Version-safe floor

Assume the host is not running the newest mermaid. Safe everywhere
(v8.7+): the init block above, classDef/class/style/linkStyle,
subgraphs, all standard diagram types. **Avoid in committed docs**: ELK
layout selection, `look: neo` / hand-drawn, swimlane,
usecase/venn/agentflow. All are v11/v12-only, and ELK needs the host to
bundle the package (they do not). Use those only after verifying the
specific host parses them.
