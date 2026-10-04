#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode=${1:---write}
if [[ "$mode" != --write && "$mode" != --check ]] || [[ $# -gt 1 ]]; then
  echo 'Usage: bash scripts/format.sh [--write|--check]' >&2
  exit 2
fi
janet=${JANET:-$PWD/build/janet}
formatter=$PWD/build/web-deps/spork/bin/janet-format
if [[ ! -x "$janet" || ! -f "$formatter" ]]; then
  echo 'Run make web-setup first to prepare the pinned Janet and Spork formatter.' >&2
  exit 2
fi
export JANET_PATH="$PWD/build/web-deps/spork"
format_tmp=$(mktemp -d)
trap 'rm -f "$format_tmp/formatted" "$format_tmp/sources"; rmdir "$format_tmp"' EXIT
status=0
rg --files --hidden -0 -g '*.janet' -g '!build/**' -g '!dist/**' \
  -g '!cache/**' -g '!.git/**' -g '!observations/local/**' > "$format_tmp/sources"
while IFS= read -r -d '' source; do
  "$janet" "$formatter" --no-config --input "$source" --output "$format_tmp/formatted"
  if ! cmp -s "$source" "$format_tmp/formatted"; then
    if [[ "$mode" == --check ]]; then
      echo "Needs formatting: $source" >&2
      status=1
    else
      cp "$format_tmp/formatted" "$source"
      echo "Formatted $source"
    fi
  fi
done < "$format_tmp/sources"
if [[ "$status" != 0 ]]; then echo 'Run: bash scripts/format.sh --write' >&2; fi
exit "$status"
