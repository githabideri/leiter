#!/usr/bin/env python3
"""Extractor: the example inventory table -> normalized JSONL.

This is the pattern for any tabular source of record: find the table
whose header contains the columns you need, read the rows, emit one
JSON node per row. The estate's real extractors are per-format
(markdown sections per site, per-host guest tables, per-service
docs); this one is deliberately small.
"""
import json, os, re, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
path = os.path.join(root, "inventory.md")


def rows(text):
    out, in_table, header = [], False, None
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("|"):
            cells = [c.strip() for c in s.strip("|").split("|")]
            if header is None:
                header = cells
                in_table = "name" in header
                continue
            if in_table and not set(s.replace("|", "").strip()) <= {"-", " ", ":"}:
                row = dict(zip(header, cells))
                out.append(row)
        else:
            in_table, header = False, None
    return out


for r in rows(open(path).read()):
    if not r.get("name") or r["name"] in ("name",):
        continue
    node = {"id": f"{r.get('kind', 'node')}/{r['name']}",
            "kind": r.get("kind", "unknown"), "name": r["name"],
            "status": (r.get("status") or "unknown").lower(),
            "source": "extractors/inventory.py"}
    if r.get("site"):
        node["site"] = r["site"]
    if r.get("runs_on"):
        node["edges"] = {"runs_on": [f"host/{r['runs_on']}"]}
    print(json.dumps(node))
