#!/usr/bin/env bash
# config-check.sh: audit + scan one config directory. Non-zero exit on
# findings. Wire into pre-push / pre-commit where a .env.schema exists.
#
# Usage: config-check.sh <config-dir>
#   config-dir must contain a .env.schema (a .env is optional: audit
#   runs against the schema and the code, scan runs against the repo).

set -euo pipefail

dir="${1:-}"
[[ -n "$dir" && -f "$dir/.env.schema" ]] || {
    echo "usage: config-check.sh <dir-with-.env.schema>" >&2
    exit 2
}
command -v varlock >/dev/null 2>&1 || {
    echo "varlock not installed (npm i -g varlock)" >&2
    exit 2
}

cd "$dir"
status=0

echo "--- audit (code env usage vs schema) ---"
aout=$(varlock audit 2>&1 || true)
echo "$aout"
# varlock exits 0 even with findings; the marker is the contract
echo "$aout" | grep -q "mismatch detected" && status=1

echo "--- scan (plaintext secrets in files) ---"
sout=$(varlock scan 2>&1 || true)
echo "$sout"
echo "$sout" | grep "sensitive" | grep -vq "No sensitive values found" && status=1

if [[ $status -eq 0 ]]; then
    echo "config-check: $dir clean"
fi
exit $status
