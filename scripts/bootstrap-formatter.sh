#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
read -r name repo revision < <(awk '$1 == "spork" {print; exit}' web/deps.lock)
checkout=build/web-deps/spork
mkdir -p build/web-deps
if [[ ! -d "$checkout/.git" ]]; then git clone --quiet "$repo.git" "$checkout"; fi
if ! git -C "$checkout" cat-file -e "$revision^{commit}" 2>/dev/null; then
  git -C "$checkout" fetch --quiet origin "$revision"
fi
git -C "$checkout" checkout --quiet "$revision"
[[ $(git -C "$checkout" rev-parse HEAD) == "$revision" ]]
touch build/formatter-ready
