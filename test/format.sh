#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
probe=$(mktemp test/.format-probe.XXXXXX.janet)
format_check_tmp=$(mktemp -d)
trap 'rm -f "$probe"; rm -rf "$format_check_tmp"' EXIT
printf '(def answer   (+ 1  2))\n' > "$probe"
cp "$probe" "$format_check_tmp/original"
if bash scripts/format.sh --check > "$format_check_tmp/log" 2>&1; then
  echo 'Formatter check failed to detect the unformatted probe.' >&2
  exit 1
fi
cmp "$probe" "$format_check_tmp/original"
bash scripts/format.sh --write
bash scripts/format.sh --check
if cmp -s "$probe" "$format_check_tmp/original"; then
  echo 'Formatter write did not update the probe.' >&2
  exit 1
fi
echo 'Formatter detects differences without writing; write mode fixes them.'
