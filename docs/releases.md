# GitHub releases and the DNF repository

Source: <https://github.com/tjisse/powerspike-janet>.
Repository configuration: <https://tjisse.github.io/powerspike-janet/rpm/powerspike.repo>.

GitHub Actions builds on Ubuntu 24.04 for x86_64. The executable includes Janet,
native JSON bindings, current game data, identity-free observation fixtures and
browser assets. Raw Practice Tool captures, build caches and signing material
are excluded from Git. The initial runtime requires glibc 2.38 or newer.

## Publish a version

Update `VERSION` and the version in `packaging/NOTICE`, commit to `main`, then:

```sh
git tag v0.1.1
git push origin main v0.1.1
```

The tag must match `VERSION`. The publish workflow tests formatting, the core,
retained sources, frontend, runtime and RPM payload. It signs the RPM with the
dedicated PowerSpike key, recomputes its SHA-256 and creates a GitHub Release.
It gathers retained stable releases, verifies their signatures, builds rpm-md
metadata pointing to the immutable release assets, signs `repomd.xml` and
deploys the metadata to GitHub Pages. Finally a disposable Fedora container
installs through DNF with both package and metadata signature checks enabled,
checks HTTP behavior at a configured port, preserves edited configuration on
reinstall and removes the package.

Do not move published tags or replace release assets. Keep old releases so
clients using cached metadata and explicit rollback still work. The workflow
can be rerun manually with the same tag after a Pages failure: it reuses the
existing release assets instead of overwriting them. For corrections, publish
a new version.

Normal pushes and pull requests run the unsigned build/test workflow and retain
RPMs as Actions artifacts. They cannot access the signing key. The published
install test can also be rerun from its manual workflow.

## Signing and hosting configuration

Pages must use GitHub Actions as its build source. The public key is checked in
at `packaging/RPM-GPG-KEY-powerspike`. Automated signing requires:

- `RPM_GPG_PRIVATE_KEY`: encrypted Actions secret containing the dedicated
  ASCII-armored private signing key.
- `RPM_SIGNING_KEY`: Actions variable containing the public fingerprint
  `2E1412F7DE9B3CD117E6464A96632207707CD16D`.

The SQLite viewer's signing key is separate. Private key material is imported
only into a temporary runner directory and removed after publication. It is
never included in Git, release assets, Pages or the executable. Recovering or
rotating signing credentials is a maintainer operation; changing the public
key also requires an explicit trust migration for DNF clients.

For the published configuration, see [RPM deployment](rpm-hosting.md). These
workflows publish packages; they do not install on a production server or
change a Cloudflare route.
