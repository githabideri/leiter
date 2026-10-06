# minicampaign: the whole loop in miniature in miniature

A two-claim comparison campaign with every mechanism and none of the
hardware:

- `charter.md`: goal, finish line, scope, primary sources.
- `claims-draft.md`: the table at campaign open: `predicted` (fixed
  goalposts) and `cited` only.
- `claims.md`: the same table resolved after the executors ran:
  `measured` / `refuted` / `not-established`, each with its data file.
- `data/`: the evidence the table points at.
- `run.sh`: runs `claimgate` three ways (red, red, green): on the draft (red,
  unresolved predictions), on a dead citation (red), on the resolved
  table (green). `--no-net` keeps it runnable offline; the real run
  fetches the cited URL.
