# Build and deploy the RPM

The package follows `tjisse/sqlite-viewer-janet`: one executable containing the
Janet runtime, native JSON bindings, application code, game data, measurements
and browser assets. No installed Janet, module directory, CDN or build tools
are needed on the deployment host. Runtime libraries are glibc/libm; the RPM
records the minimum glibc version used by the actual executable. Build on the
target architecture and a compatible distribution baseline. This project does
not cross-compile an x86_64 binary into an ARM RPM by changing the package tag.

The first x86_64 build requires **glibc 2.38 or newer**. It is not compatible
with the glibc 2.34 baseline of Enterprise Linux 9; build on an older compatible
baseline if that is your target.

## Build

On Ubuntu, build prerequisites are Git, C compiler, Make, Python 3, ripgrep and
RPM build tools (`build-essential git python3 ripgrep rpm`). Use authenticated
GitHub access is sufficient; all dependencies, including the Datastar SDK, are
public and pinned.

```sh
make format
make test
make test-web
make build
make test-runtime
make rpm
make test-package RPM=dist/powerspike-0.1.0-1.x86_64.rpm
```

`VERSION` sets the application/package version; `RPM_RELEASE` defaults to `1`.
Build output stays under ignored `build/` and `dist/`. The formatter is the same
pinned Spork `janet-format` as the SQLite viewer. `make format-check` reports
differences without rewriting files. Both core and frontend checks run it.

The generated RPM is unsigned. Local installation instructions below use the
explicit local-package signature exception; verify its SHA-256 through your
trusted transfer. Signing and a public RPM repository are separate publication
steps. The package does not reuse the SQLite viewer's signing identity.

The build writes a matching `.rpm.sha256` file. After transferring both files,
run `sha256sum -c powerspike-0.1.0-1.x86_64.rpm.sha256`.

Package checks verify digests, permissions, dependencies, preserved configuration,
service syntax and the extracted executable's HTTP/live-update behavior without
project files. Installation and service lifecycle still need a smoke check on
the target RPM/systemd host.

## Install from the signed DNF repository

On a compatible RPM/systemd host with glibc 2.38 or newer:

```sh
sudo curl -fsSL https://tjisse.github.io/powerspike-janet/rpm/powerspike.repo \
  -o /etc/yum.repos.d/powerspike.repo
sudo dnf install powerspike
```

Both `gpgcheck=1` and `repo_gpgcheck=1` are enabled. Packages are stored in
versioned GitHub Releases; GitHub Pages serves signed repository metadata and
the public key. The PowerSpike signing fingerprint is:

```text
2E14 12F7 DE9B 3CD1 17E6 464A 9663 2207 707C D16D
```

Verify the fingerprint when DNF first asks to import the key. Later releases
are installed with `sudo dnf upgrade powerspike`. The port configuration is
preserved and an already-running service restarts during upgrade.

## Install a local build

Copy the compatible RPM to your RPM/systemd host, then:

```sh
sudo dnf --setopt=localpkg_gpgcheck=0 install ./powerspike-0.1.0-1.x86_64.rpm
```

This exception is only for an unsigned local build. Published packages use the
signed repository above and require no signature exception.

## Choose a port

Edit `/etc/powerspike/powerspike.env` with `sudoedit`.

For example:

```ini
PS_HOST=127.0.0.1
PS_PORT=8765
```

```sh
sudo systemctl enable --now powerspike
curl --fail http://127.0.0.1:8765/healthz
journalctl -u powerspike -n 50
```

The package creates a dedicated `powerspike` account and installs a hardened
systemd unit. It does not start on initial installation. Configuration is marked
`noreplace`: package upgrades preserve your chosen port. Upgrades restart an
already-running service; uninstall stops/disables it and retains the account
and modified configuration according to RPM's normal `.rpmsave` behavior.

After editing the port, run `sudo systemctl restart powerspike`. No unit-file
edit or `daemon-reload` is needed for an environment change.

## Cloudflare Tunnel

When `cloudflared` runs on the same host, set the published application route's
service type to **HTTP**, and its URL to **`http://127.0.0.1:8765`** (use your
chosen `PS_PORT`). The browser uses your public HTTPS hostname; Cloudflare
forwards to this local HTTP listener. See Cloudflare's
[published application routing](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/routing-to-tunnel/protocols/).

If the tunnel connector runs in another container or host, loopback refers to
that connector. Bind `PS_HOST` to the reachable private interface and configure
the route to that host/address and the same port instead.

PowerSpike currently has no application login or Access JWT verification.
An Access policy can protect the public route if desired; this package does
not copy the SQLite viewer's identity/database authorization behavior.

## Run without systemd

```sh
PS_PORT=8765 dist/bin/powerspike
dist/bin/powerspike --host 127.0.0.1 --port 8765
dist/bin/powerspike --help
dist/bin/powerspike --version
```

Command-line flags override the environment. Ports must be decimal integers
from 1024 to 65535; invalid values fail startup. The executable runs from any
working directory, with no project files beside it. Keep the accompanying
dependency license notices when redistributing the runtime.
