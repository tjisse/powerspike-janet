"""Verify RPM metadata and run its extracted binary without installing on this host."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from runtime import verify


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    package = parser.parse_args().package.resolve()
    assert package.is_file(), 'Expected a built RPM'
    rpm = os.environ.get('RPM_BIN', 'rpm')
    rpmkeys = os.environ.get('RPMKEYS', str(Path(rpm).with_name('rpmkeys')))
    rpm2cpio = os.environ.get('RPM2CPIO', 'rpm2cpio')
    with tempfile.TemporaryDirectory(prefix='powerspike-rpm-') as temp:
        root = Path(temp)
        args = [rpm, '--dbpath', str(root / 'db'), '-qp']
        subprocess.run([rpmkeys, '--dbpath', str(root / 'db'), '--checksig', '--nosignature', str(package)], check=True)
        records = subprocess.check_output([*args, '--qf',
            '[%{FILENAMES}\t%{FILEMODES:octal}\t%{FILEUSERNAME}\t%{FILEGROUPNAME}\t%{FILEFLAGS}\n]', str(package)], text=True)
        files = {}
        for line in records.splitlines():
            path, mode, owner, group, flags = line.split('\t')
            permission = int(mode, 8) & 0o777
            assert permission & 0o022 == 0, 'Group/world-writable: ' + path
            assert owner == 'root', 'Unexpected owner: ' + path
            files[path] = (permission, group, int(flags))
        assert files['/usr/bin/powerspike'][0] == 0o755
        assert files['/etc/powerspike/powerspike.env'][:2] == (0o640, 'powerspike')
        assert files['/etc/powerspike/powerspike.env'][2] & 17 == 17, 'Config must be noreplace'
        assert '/usr/lib/systemd/system/powerspike.service' in files
        assert '/usr/lib/sysusers.d/powerspike.conf' in files
        assert not any(path.endswith(('.so', '.janet', '.c', '.h', '.jdn', '.pem', '.key')) for path in files)
        requires = subprocess.check_output([*args, '--requires', str(package)], text=True)
        assert 'glibc >=' in requires and 'systemd' in requires and 'shadow-utils' in requires
        scripts = subprocess.check_output([*args, '--scripts', str(package)], text=True)
        assert 'try-restart powerspike.service' in scripts and 'disable --now powerspike.service' in scripts
        with (root / 'payload.cpio').open('wb') as output:
            subprocess.run([rpm2cpio, str(package)], stdout=output, check=True)
        payload = root / 'payload'
        payload.mkdir()
        subprocess.run(['bsdtar', '-xf', str(root / 'payload.cpio'), '-C', str(payload)], check=True)
        unit = (payload / 'usr/lib/systemd/system/powerspike.service').read_text()
        assert 'EnvironmentFile=/etc/powerspike/powerspike.env' in unit
        assert 'ExecStart=/usr/bin/powerspike' in unit
        assert 'User=powerspike' in unit and 'ProtectSystem=strict' in unit
        assert 'PS_PORT=8090' in (payload / 'etc/powerspike/powerspike.env').read_text()
        if shutil.which('systemd-analyze'):
            check_unit = root / 'powerspike.service'
            check_unit.write_text(unit.replace('ExecStart=/usr/bin/powerspike',
                'ExecStart=' + str(payload / 'usr/bin/powerspike')))
            check_unit.chmod(0o644)
            subprocess.run(['systemd-analyze', 'verify', str(check_unit)], check=True)
        verify(payload / 'usr/bin/powerspike')
        print('RPM payload, digests, permissions, preserved config, service and lifecycle scripts verified.')


if __name__ == '__main__':
    main()
