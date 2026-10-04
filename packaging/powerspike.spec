%global debug_package %{nil}
%global _build_id_links none
%{!?app_version:%global app_version 0.1.0}
%{!?app_release:%global app_release 1}
%{!?min_glibc:%global min_glibc 2.38}
Name: powerspike
Version: %{app_version}
Release: %{app_release}
Summary: League of Legends build comparisons in Janet
License: LicenseRef-PowerSpike AND MIT AND LicenseRef-RiotGames
Source0: powerspike-%{version}-runtime.tar.gz
Requires: glibc >= %{min_glibc}
Requires: systemd
Requires(pre): shadow-utils
Requires(post): systemd
Requires(preun): systemd
Requires(postun): systemd
AutoReqProv: no

%description
PowerSpike Rift HUD with the current unvalidated champion and item catalog.
Bundles Janet, the application, native JSON bindings, game data and artwork
in one relocatable executable. No runtime downloads or installed Janet required.
The listen address and port are configured in /etc/powerspike/powerspike.env.

%prep
%setup -q -n powerspike-runtime

%build
# The runtime is built and tested before packaging, using pinned dependencies.

%install
mkdir -p %{buildroot}/usr/bin %{buildroot}/usr/lib/systemd/system
mkdir -p %{buildroot}/usr/lib/sysusers.d %{buildroot}/etc/powerspike
mkdir -p %{buildroot}/usr/share/licenses/powerspike %{buildroot}/usr/share/doc/powerspike
install -m 0755 bin/powerspike %{buildroot}/usr/bin/powerspike
cp -a share/licenses/. %{buildroot}/usr/share/licenses/powerspike/
install -m 0644 packaging/powerspike.service %{buildroot}/usr/lib/systemd/system/
install -m 0644 packaging/powerspike.sysusers %{buildroot}/usr/lib/sysusers.d/powerspike.conf
install -m 0640 packaging/powerspike.env %{buildroot}/etc/powerspike/
install -m 0644 README.md docs/rpm-hosting.md %{buildroot}/usr/share/doc/powerspike/

%pre
getent group powerspike >/dev/null || groupadd --system powerspike
getent passwd powerspike >/dev/null || useradd --system --gid powerspike --home-dir / --shell /usr/sbin/nologin powerspike

%post
systemctl daemon-reload >/dev/null 2>&1 || :
# The administrator chooses the port and enables the service after installation.

%preun
if [ "$1" -eq 0 ]; then
  systemctl disable --now powerspike.service >/dev/null 2>&1 || :
fi

%postun
systemctl daemon-reload >/dev/null 2>&1 || :
if [ "$1" -ge 1 ]; then
  systemctl try-restart powerspike.service >/dev/null 2>&1 || :
fi

%files
%defattr(0644,root,root,0755)
%attr(0755,root,root) /usr/bin/powerspike
/usr/lib/systemd/system/powerspike.service
/usr/lib/sysusers.d/powerspike.conf
%license /usr/share/licenses/powerspike
%doc /usr/share/doc/powerspike/README.md
%doc /usr/share/doc/powerspike/rpm-hosting.md
%dir %attr(0750,root,powerspike) /etc/powerspike
%config(noreplace) %attr(0640,root,powerspike) /etc/powerspike/powerspike.env

%changelog
* Sun Oct 04 2026 PowerSpike contributors - 0.1.0-1
- Bundle current Rift HUD, Janet, native bindings and local assets.
- Configure listener through PS_HOST and PS_PORT; add systemd service.
