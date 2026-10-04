#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/web-deps build/web-modules
while read -r task_name task_repo task_commit; do
    case "$task_name" in ''|'#'*) continue ;; esac
    task_checkout="build/web-deps/$task_name"
    if [ ! -d "$task_checkout/.git" ]; then
        git -c credential.helper='!gh auth git-credential' clone --quiet "$task_repo.git" "$task_checkout"
    fi
    if ! git -C "$task_checkout" cat-file -e "$task_commit^{commit}" 2>/dev/null; then
        git -C "$task_checkout" fetch --quiet origin "$task_commit"
    fi
    git -C "$task_checkout" checkout --quiet "$task_commit"
    test "$(git -C "$task_checkout" rev-parse HEAD)" = "$task_commit"
done < web/deps.lock
cp -R build/web-deps/spork/spork build/web-modules/
cp -R build/web-deps/datastar-janet/datastar build/web-modules/
cp build/web-deps/datastar-janet/datastar.janet build/web-modules/
cp build/web-deps/jayson/src/jayson.janet build/web-modules/
cp build/web-deps/janet-html/src/janet-html.janet build/web-modules/
cp -R build/web-deps/jurl/jurl build/web-modules/
mkdir -p build/web-modules/judge build/web-assets/licenses
cp build/web-deps/judge/src/*.janet build/web-modules/judge/
${CC:-cc} -O2 -fPIC -shared -Ibuild/janet-src/build build/web-deps/spork/src/json.c -o build/web-modules/spork/json.so
mkdir -p build/web-modules/jurl
${CC:-cc} -O2 -fPIC -shared -Ibuild/janet-src/build ${CURL_CFLAGS:-} build/web-deps/jurl/src/*.c -l:libcurl.so.4 -o build/web-modules/jurl/native.so
${CC:-cc} -O2 -fPIC -shared -Ibuild/janet-src/build native/hash.c -lcrypto -o build/web-modules/pshash.so
while read -r task_name task_repo task_commit; do
    case "$task_name" in ''|'#'*) continue ;; esac
    for task_license in LICENSE LICENSE.md LICENSE.txt UNLICENSE; do
        if [ -f "build/web-deps/$task_name/$task_license" ]; then
            cp "build/web-deps/$task_name/$task_license" "build/web-assets/licenses/$task_name-$task_license"
        fi
    done
done < web/deps.lock
${PYTHON:-python3} scripts/fetch_web_assets.py
JANET_PATH=build/web-modules build/janet scripts/seed-data.janet
touch build/web-ready
printf 'Frontend dependencies ready. Run make serve.\n'
