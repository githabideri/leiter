# Claims: minicampaign (resolved, at the gate)

After the executors ran: every `predicted` row is resolved against
its data, and the table is what `claimgate` sees.

| # | Claim | Label | Evidence |
|---|---|---|---|
| C1 | build B decodes 12.4 t/s on the test prompt | measured | data/b.log |
| C2 | the vendor documents a 12 t/s class result | cited | https://www.example.org/ |
| C3 | build A is unchanged from the 01-01 baseline | refuted | data/a.log |
| C4 | the difference is explained by the quantization | not-established | data/quant-note.md |
