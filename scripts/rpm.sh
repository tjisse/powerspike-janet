#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
rpm_build=${RPMBUILD:-rpmbuild}
command -v "$rpm_build" >/dev/null || { echo 'Install the rpm build tools (rpmbuild), or set RPMBUILD.' >&2; exit 2; }
[[ -x dist/bin/powerspike ]] || { echo 'Run make build first.' >&2; exit 2; }
version=$(cat VERSION)
release=${RPM_RELEASE:-1}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$release" =~ ^[0-9]+$ ]] || { echo 'Invalid RPM version/release.' >&2; exit 2; }
minimum_glibc=$(readelf --version-info dist/bin/powerspike | sed -n 's/.*Name: GLIBC_\([0-9.]*\).*/\1/p' | sort -V | tail -1)
[[ -n "$minimum_glibc" ]] || { echo 'Could not identify the executable glibc baseline.' >&2; exit 2; }
top=$root/build/rpm
mkdir -p "$top"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS,tmp,db}
package_dir=$(mktemp -d "$root/build/package.XXXXXX")
trap 'rm -rf "$package_dir"' EXIT
stage=$package_dir/powerspike-runtime
mkdir -p "$stage/docs"
cp -R dist/bin dist/share packaging README.md "$stage/"
cp docs/rpm-hosting.md "$stage/docs/"
# Normalize WSL checkout permissions instead of inheriting its 0777 mount modes.
find "$stage" -type d -exec chmod 0755 {} +
find "$stage" -type f -exec chmod 0644 {} +
chmod 0755 "$stage/bin/powerspike"
tar -czf "$top/SOURCES/powerspike-$version-runtime.tar.gz" -C "$package_dir" powerspike-runtime
"$rpm_build" -bb --nodeps --define "_topdir $top" \
  --define "_tmppath $top/tmp" --define "_dbpath $top/db" \
  --define "app_version $version" --define "app_release $release" \
  --define "min_glibc $minimum_glibc" \
  --define '_unpackaged_files_terminate_build 1' \
  --define '__os_install_post %{nil}' packaging/powerspike.spec
arch=$(uname -m)
cp "$top/RPMS/$arch/powerspike-$version-$release.$arch.rpm" dist/
(cd dist && sha256sum "powerspike-$version-$release.$arch.rpm" > "powerspike-$version-$release.$arch.rpm.sha256")
printf 'RPM: %s/dist/powerspike-%s-%s.%s.rpm (glibc >= %s)\n' "$root" "$version" "$release" "$arch" "$minimum_glibc"
