#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${RPM_SIGNING_KEY:?Set the PowerSpike signing key fingerprint}"
: "${GNUPGHOME:?Use a dedicated GnuPG directory}"
key=packaging/RPM-GPG-KEY-powerspike
fingerprint=$(gpg --batch --with-colons --show-keys "$key" | awk -F: '$1 == "fpr" {print $10; exit}')
[[ "$fingerprint" == "$RPM_SIGNING_KEY" ]] || { echo 'Signing key does not match the checked-in public key.' >&2; exit 1; }
shopt -s nullglob
packages=(dist/*.rpm)
[[ ${#packages[@]} -gt 0 ]] || { echo 'No RPMs to sign.' >&2; exit 1; }
verify_dir=$(mktemp -d)
trap 'rm -rf "$verify_dir"' EXIT
rpmkeys --dbpath "$verify_dir" --import "$key"
for package in "${packages[@]}"; do
  rpmsign --define '__gpg /usr/bin/gpg' --define "_gpg_name $RPM_SIGNING_KEY" \
    --define "_gpg_path $GNUPGHOME" --addsign "$package"
  rpmkeys --dbpath "$verify_dir" --checksig "$package"
  (cd dist && sha256sum "$(basename "$package")" > "$(basename "$package").sha256")
done
