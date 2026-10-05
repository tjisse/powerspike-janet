#!/usr/bin/env bash
# Run only in a disposable Fedora container, never on the developer's host.
set -euo pipefail
test -f /run/.containerenv || test -f /.dockerenv
[[ $EUID -eq 0 ]]
repository_url=${PS_REPOSITORY_URL:-https://tjisse.github.io/powerspike-janet/rpm/powerspike.repo}
dnf -y install curl util-linux systemd
curl -fsSL --retry 8 --retry-delay 5 --retry-all-errors "$repository_url" -o /etc/yum.repos.d/powerspike.repo
grep -qx 'gpgcheck=1' /etc/yum.repos.d/powerspike.repo
grep -qx 'repo_gpgcheck=1' /etc/yum.repos.d/powerspike.repo
upgrade_from=${PS_UPGRADE_FROM:-0.4.0-1}
dnf -y install "powerspike-$upgrade_from.x86_64"
installed_version=$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' powerspike)
rpm -V powerspike
powerspike --version
systemd-analyze verify /usr/lib/systemd/system/powerspike.service
printf 'PS_HOST=127.0.0.1\nPS_PORT=8765\n# Preserve administrator configuration\n' > /etc/powerspike/powerspike.env
sha256sum /etc/powerspike/powerspike.env > /tmp/powerspike-config.sha256
# StateDirectory is created by systemd on a real host; mirror it in this container.
install -d -o powerspike -g powerspike -m 0750 /var/lib/powerspike
runuser -u powerspike -- env PS_PORT=8765 PS_DATA_DIR=/var/lib/powerspike powerspike > /tmp/powerspike.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
for attempt in {1..30}; do
  if curl -fsS http://127.0.0.1:8765/healthz; then break; fi
  sleep 1
done
curl -fsS http://127.0.0.1:8765/healthz
curl -fsS http://127.0.0.1:8765/ -o /tmp/powerspike.html
grep -q '173 champions' /tmp/powerspike.html
curl -fsS http://127.0.0.1:8765/assets/champion/Ahri.png -o /tmp/ahri.png
test -s /tmp/ahri.png
kill "$server_pid"
wait "$server_pid" || true
trap - EXIT
find /var/lib/powerspike/patches -type f \( -name current -o -name package.jdn -o -name manifest.json \) -print0 | sort -z | xargs -0 sha256sum > /tmp/powerspike-cache.sha256
dnf -y upgrade powerspike
upgraded_version=$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' powerspike)
test "$installed_version" != "$upgraded_version"
test "$upgraded_version" = "$(cat /source/VERSION)-1.x86_64"
sha256sum --check /tmp/powerspike-config.sha256
sha256sum --check /tmp/powerspike-cache.sha256
runuser -u powerspike -- env PS_PORT=8765 PS_DATA_DIR=/var/lib/powerspike powerspike > /tmp/powerspike-upgraded.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
for attempt in {1..30}; do
  if curl -fsS http://127.0.0.1:8765/healthz; then break; fi
  sleep 1
done
curl -fsS http://127.0.0.1:8765/healthz
curl -fsS http://127.0.0.1:8765/ -o /tmp/powerspike-upgraded.html
grep -q 'Save locally' /tmp/powerspike-upgraded.html
kill "$server_pid"
wait "$server_pid" || true
trap - EXIT
dnf -y reinstall powerspike
sha256sum --check /tmp/powerspike-config.sha256
test -s /var/lib/powerspike/patches/16.19.1/current
dnf -y remove powerspike
test ! -e /usr/bin/powerspike
grep -q 'Preserve administrator configuration' /etc/powerspike/powerspike.env.rpmsave
getent passwd powerspike
echo 'Signed DNF install, real version upgrade, preserved config/cache, upgraded runtime, reinstall and removal passed.'
