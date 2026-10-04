#!/bin/sh
set -eu

# Build only inside the project's ignored build directory.
task_version=v1.42.1
task_commit=e1963cdfe0148f83601907727e00bd672d798115
mkdir -p build
if [ ! -d build/janet-src/.git ]; then
    git clone --depth 1 --branch "$task_version" https://github.com/janet-lang/janet.git build/janet-src
fi
task_actual=$(git -C build/janet-src rev-parse HEAD)
if [ "$task_actual" != "$task_commit" ]; then
    echo "Janet source does not match the pinned commit." >&2
    exit 1
fi
make -C build/janet-src -j2
cp build/janet-src/build/janet build/janet
echo "Built Janet $task_version at build/janet"
