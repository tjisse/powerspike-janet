#!/usr/bin/env bash
# Run only in a disposable Fedora container, never on the developer's host.
set -euo pipefail
test -f /run/.containerenv || test -f /.dockerenv
[[ $EUID -eq 0 ]]
repository_url=${PS_REPOSITORY_URL:-https://tjisse.github.io/powerspike-janet/rpm/powerspike.repo}
dnf -y install curl util-linux systemd
curl -fsSL "$repository_url" -o /etc/yum.repos.d/powerspike.repo
grep -qx 'gpgcheck=1' /etc/yum.repos.d/powerspike.repo
grep -qx 'repo_gpgcheck=1' /etc/yum.repos.d/powerspike.repo
dnf -y install powerspike
installed_version=$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' powerspike)
rpm -V powerspike
powerspike --version
systemd-analyze verify /usr/lib/systemd/system/powerspike.service
printf 'PS_HOST=127.0.0.1\nPS_PORT=8765\n# Preserve administrator configuration\n' > /etc/powerspike/powerspike.env
sha256sum /etc/powerspike/powerspike.env > /tmp/powerspike-config.sha256
runuser -u powerspike -- env PS_PORT=8765 powerspike > /tmp/powerspike.log 2>&1 &
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
dnf -y upgrade powerspike
test "$installed_version" = "$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' powerspike)"
dnf -y reinstall powerspike
sha256sum --check /tmp/powerspike-config.sha256
dnf -y remove powerspike
test ! -e /usr/bin/powerspike
grep -q 'Preserve administrator configuration' /etc/powerspike/powerspike.env.rpmsave
getent passwd powerspike
echo 'Signed DNF install, runtime, config preservation, reinstall and removal passed.'
