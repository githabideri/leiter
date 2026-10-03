# hello — the worked example

The minimal case of `docs/overlay-contract.md`: one template
(`SKILL.md`), one mapping (`mapping.env`), one render target.

    mkdir -p .out && \
    python3 ../../scripts/overlay-apply/overlay-apply render mapping.env SKILL.md --out .out/SKILL.md
    python3 ../../scripts/overlay-apply/overlay-apply check .out/SKILL.md

`NAME` is double-quoted in the mapping (the value needs quotes in YAML
frontmatter); `PORT` is plain. The quote pair is stripped by the tool,
not by the template.
