#!/bin/sh
# The minicampaign in three runs: red (draft), red (dead citation), green (resolved).
set -e
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -r "$here/." "$tmp/campaign"
gate="$here/../../scripts/claimgate"

echo '=== 1: the draft table (goalposts registered, work not yet done) -> RED'
cp "$here/claims-draft.md" "$tmp/campaign/claims.md"
python3 "$gate" "$tmp/campaign" --no-net || true
echo
echo '=== 2: resolved table, but the cited source never resolves (.invalid is a'
echo '     reserved TLD that no DNS returns) -> RED (works offline)'
cp "$here/claims.md" "$tmp/campaign/claims.md"
sed -i 's#https://www.example.org/#https://this-citation-was-wrong.invalid/#' "$tmp/campaign/claims.md"
python3 "$gate" "$tmp/campaign" || true
echo
echo '=== 3: the resolved table (rows settled, citation alive) -> GREEN'
cp "$here/claims.md" "$tmp/campaign/claims.md"
python3 "$gate" "$tmp/campaign"
echo
echo 'Note: the citation check is a live fetch. Run without --no-net to see it'
echo 'resolve; with --no-net it is reported SKIP (never a failure).'
