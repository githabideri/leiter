#!/usr/bin/env python3
"""Extractor: one node per subdirectory of services/ (a service's home
is its directory; the doc inside is the source of record, the directory
is the node). Trivial on purpose: this is the cheapest source kind
there is, and it is what makes 'unmapped service' a checkable thing."""
import json, os, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
svc_root = os.path.join(root, "services")

for d in sorted(os.listdir(svc_root)) if os.path.isdir(svc_root) else []:
    full = os.path.join(svc_root, d)
    if not os.path.isdir(full):
        continue
    has_doc = any(f.endswith(".md") for f in os.listdir(full))
    print(json.dumps({
        "id": f"service/{d}",
        "kind": "service",
        "name": d,
        "status": "running",
        # a service with no runs_on edge anywhere (curation or another
        # extractor) is exactly the lint finding we want: unmapped
        "source": "extractors/services.py" + ("" if has_doc else " (no doc)"),
    }))
