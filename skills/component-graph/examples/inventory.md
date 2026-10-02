# Example estate inventory (the minimal format)

One flat table is enough to start: every component as a row, its kind,
its site, its status, and (optionally) what it runs on.

| name | kind | site | status | runs_on |
|------|------|------|--------|---------|
| alpha  | host | main | running | |
| beta   | host | offsite | running | |
| ct-100 | guest | main | running | alpha |
| ct-200 | guest | main | stopped | alpha |
| vm-10  | guest | offsite | running | beta |

## Notes

- status is a closed vocabulary: running / stopped / decommissioned /
  migrated / removed. The Status column wins over prose.
- when a host is decommissioned, keep its table and re-home its rows
  (this example's format carries the new home directly in `runs_on`;
  in richer formats use a marked notes column).
