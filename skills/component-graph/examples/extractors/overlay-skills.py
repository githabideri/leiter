#!/usr/bin/env python3
"""Extractor: overlay-rendered agent skills -> normalized JSONL.

An estate that runs the leiter overlay on its skills corpus
(docs/overlay-contract.md, worked example 2) has skills the agent
loads by *estate name* (like `truenas`) that do not exist in the
private skills directory: the body lives in the public shape
tree, the values in the private overlay directory, and the rendered
instance lands in the gitignored skills root. A skills-directory scan
misses the whole class: in the graph those capabilities vanish or
show up as orphan tools, and per-skill curation nodes are a band-aid
over the missing class.

This extractor derives one node per overlay shape:
    id     skill/<estate name>   (the name the agent actually loads)
    source <shape tree>/<shape> + <overlay>/estates/<shape>
           (the two owners, never the disposable rendered copy)

The estate name comes from the mapping file's <SHAPE>_NAME value
(the contract's multi-line note keeps long descriptions in the
estate file; the short name stays in the mapping). A shape without
a mapping name falls back to its directory name.

Defaults assume the contract's layout relative to the repo root
(copy examples/ to <repo>/graph/ and the root resolves to the repo
root); override with the environment:
    GRAPH_ROOT   repo root (default: this directory's parent)
    OVERLAY_DIR  overlay directory (default: $GRAPH_ROOT/configs/overlay)
    OVERLAY_MAP  the mapping file (default: $OVERLAY_DIR/mapping.env)
    SHAPE_ROOT   the public shape tree (default: $GRAPH_ROOT/submodules/
                 leiter/skills, the provider this pattern ships with)

No overlay directory => no output, no warning: a plain estate is
simply not overlaid, and the example estate stays clean.
"""
import json, os, re, sys


def load_names(mapfile):
    """Mapping file, contract grammar: KEY=value or KEY: value, key
    with or without the @@ wrappers, value optionally double-quoted
    (env convention). Returns shape-key (lowercase, dashes) -> value."""
    names = {}
    if not os.path.isfile(mapfile):
        return names
    for line in open(mapfile):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^@*([A-Z][A-Z0-9_]*)@*\s*[:=]\s*(.*)$", line)
        if not m or not m.group(1).endswith("_NAME"):
            continue
        v = m.group(2).strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in ("\"", "'"):
            v = v[1:-1]
        names[m.group(1)[:-5].lower().replace("_", "-")] = v
    return names


def main():
    root = os.environ.get("GRAPH_ROOT") or \
        os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    overlay = os.environ.get("OVERLAY_DIR") or os.path.join(root, "configs", "overlay")
    mapfile = os.environ.get("OVERLAY_MAP") or os.path.join(overlay, "mapping.env")
    estates = os.path.join(overlay, "estates")
    shape_root = os.environ.get("SHAPE_ROOT") or \
        os.path.join(root, "submodules", "leiter", "skills")

    if not os.path.isdir(estates):
        return  # no overlay in this estate: nothing to emit

    names = load_names(mapfile)
    for d in sorted(os.listdir(estates)):
        p = os.path.join(estates, d)
        if not (os.path.isdir(p) and os.path.exists(os.path.join(p, "estate.md"))):
            continue
        name = names.get(d.replace("-", "_"), names.get(d, d))
        print(json.dumps({
            "id": f"skill/{name}",
            "kind": "skill",
            "name": name,
            "status": "running",
            "source": (f"overlay: {os.path.relpath(os.path.join(shape_root, d), root)}"
                       f" + {os.path.relpath(p, root)} (estate name {name})"),
        }))


if __name__ == "__main__":
    main()
