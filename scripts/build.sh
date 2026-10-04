#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
make web-setup
mkdir -p dist/bin dist/share/licenses
export JANET_PATH="$root/build/web-deps/jpm"
export JANET_HEADERPATH="$root/build/janet-src/build"
export JANET_LIBPATH="$root/build/janet-src/build"
export JANET_MODPATH="$root/build/web-modules"
export JANET_BUILDPATH="$root/build/executable"
export JANET_JPM_CONFIG="$root/scripts/jpm-config.janet"
${PYTHON:-python3} - <<'PY'
from pathlib import Path
import sys
sys.path.insert(0, 'scripts')
from jdn import dumps
paths = {'VERSION', 'project.janet', 'web/deps.lock', 'scripts/jpm-config.janet'}
for folder in ('web', 'src', 'data', 'observations/16.19.1', 'build/web-modules', 'build/web-assets'):
    paths.update(str(p) for p in Path(folder).rglob('*') if p.is_file())
Path('build/executable-inputs.jdn').write_text(dumps(sorted(paths)) + '\n')
PY
"$root/build/janet" "$root/build/web-deps/jpm/jpm/cli.janet" --build-type=release build
install -m 0755 build/executable/powerspike dist/bin/powerspike
cp -R build/web-assets/licenses/. dist/share/licenses/
cp build/janet-src/LICENSE dist/share/licenses/janet-LICENSE
cp web/deps.lock dist/share/licenses/deps.lock
cp packaging/NOTICE dist/share/licenses/powerspike-NOTICE
printf 'Built %s/dist/bin/powerspike\n' "$root"
