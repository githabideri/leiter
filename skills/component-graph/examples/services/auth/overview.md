# auth service

Sits on `beta` (offsite). Its `runs_on` edge lives in the curation file
until a source of record that can see both sides is written; the node
itself has a home (this directory), so the lint nags about the staged
edge, not about the node. The curation's `host/gamma` finding, by
contrast, has no home at all and is the node-level nag.
