#!/usr/bin/env bash
# Pages contains signed metadata; immutable Releases contain the RPM payloads.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# -eq 3 ]] || { echo 'Usage: repository.sh OWNER/REPO PACKAGES_DIR OUTPUT_DIR' >&2; exit 2; }
repository=$1
[[ "$repository" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || { echo 'Invalid repository name.' >&2; exit 2; }
: "${RPM_SIGNING_KEY:?Set the PowerSpike signing key fingerprint}"
packages=$(realpath "$2")
output=$(realpath -m "$3")
key=packaging/RPM-GPG-KEY-powerspike
fingerprint=$(gpg --batch --with-colons --show-keys "$key" | awk -F: '$1 == "fpr" {print $10; exit}')
[[ "$fingerprint" == "$RPM_SIGNING_KEY" ]] || { echo 'Repository key does not match the checked-in public key.' >&2; exit 1; }
verify_dir=$(mktemp -d)
trap 'rm -rf "$verify_dir"' EXIT
rpmkeys --dbpath "$verify_dir" --import "$key"
mapfile -d '' rpms < <(find "$packages" -type f -name '*.rpm' -print0)
[[ ${#rpms[@]} -gt 0 ]] || { echo 'No release RPMs found.' >&2; exit 1; }
for package in "${rpms[@]}"; do
  relative=${package#"$packages/"}
  [[ "$relative" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)/powerspike-([0-9]+\.[0-9]+\.[0-9]+)-([0-9]+)\.x86_64\.rpm$ ]] \
    && [[ "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]] \
    || { echo "Invalid release RPM path: $relative" >&2; exit 1; }
  result=$(rpmkeys --dbpath "$verify_dir" --checksig --verbose "$package")
  [[ "$result" == *'Signature'*'OK'* ]] || { echo "Release RPM is unsigned: $relative" >&2; exit 1; }
done
mkdir -p "$output"
createrepo_c --checksum sha256 --unique-md-filenames \
  --baseurl "https://github.com/$repository/releases/download/" \
  --outputdir "$output" "$packages"
owner=${repository%/*}
repo=${repository#*/}
sed -e "s|@OWNER@|$owner|g" -e "s|@REPO@|$repo|g" packaging/powerspike.repo.in > "$output/powerspike.repo"
cp "$key" "$output/RPM-GPG-KEY-powerspike"
gpg --batch --yes --armor --detach-sign --local-user "$RPM_SIGNING_KEY" "$output/repodata/repomd.xml"
printf 'PowerSpike RPM repository: https://%s.github.io/%s/rpm/\n' "$owner" "$repo"
