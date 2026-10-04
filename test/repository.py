"""Check signed rpm-md metadata, payload checksums and immutable release URLs."""
import argparse
import configparser
import gzip
import hashlib
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET


def verify(repository, packages, output):
    key = output / 'RPM-GPG-KEY-powerspike'
    metadata = output / 'repodata/repomd.xml'
    with tempfile.TemporaryDirectory(prefix='powerspike-repo-key-') as home:
        subprocess.run(['gpg', '--homedir', home, '--batch', '--import', str(key)],
                       check=True, capture_output=True)
        subprocess.run(['gpg', '--homedir', home, '--batch', '--verify',
                        str(metadata) + '.asc', str(metadata)], check=True, capture_output=True)
        modified = Path(home) / 'modified.xml'
        modified.write_bytes(metadata.read_bytes() + b'\n<!-- modified -->\n')
        result = subprocess.run(['gpg', '--homedir', home, '--batch', '--verify',
                                 str(metadata) + '.asc', str(modified)], capture_output=True)
        assert result.returncode != 0, 'Modified metadata must fail signature verification'
    config = configparser.ConfigParser()
    config.read(output / 'powerspike.repo')
    owner, repo = repository.split('/')
    section = config['powerspike']
    assert section['gpgcheck'] == section['repo_gpgcheck'] == '1'
    assert section['baseurl'] == f'https://{owner}.github.io/{repo}/rpm/'
    assert section['gpgkey'] == section['baseurl'] + key.name
    namespaces = {'r': 'http://linux.duke.edu/metadata/repo',
                  'p': 'http://linux.duke.edu/metadata/common'}
    root = ET.parse(metadata).getroot()
    primary = None
    for data in root.findall('r:data', namespaces):
        location = data.find('r:location', namespaces).get('href')
        path = output / location
        assert path.is_relative_to(output) and path.is_file()
        checksum = data.find('r:checksum', namespaces)
        assert checksum.get('type') == 'sha256'
        assert hashlib.sha256(path.read_bytes()).hexdigest() == checksum.text
        if data.get('type') == 'primary':
            primary = ET.fromstring(gzip.decompress(path.read_bytes()))
    assert primary is not None
    entries = primary.findall('p:package', namespaces)
    assert len(entries) == len(list(packages.rglob('*.rpm'))) > 0
    for entry in entries:
        assert entry.find('p:name', namespaces).text == 'powerspike'
        assert entry.find('p:arch', namespaces).text == 'x86_64'
        location = entry.find('p:location', namespaces)
        assert location.get('{http://www.w3.org/XML/1998/namespace}base') == f'https://github.com/{repository}/releases/download/'
        payload = packages / location.get('href')
        checksum = entry.find('p:checksum', namespaces)
        assert payload.is_relative_to(packages) and payload.is_file()
        assert checksum.get('type') == 'sha256'
        assert hashlib.sha256(payload.read_bytes()).hexdigest() == checksum.text
    assert not list(output.rglob('*.rpm')), 'Pages must contain metadata, not payloads'
    print('Signed metadata, tamper rejection, release URLs and payload checksums verified.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repository')
    parser.add_argument('packages', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    verify(args.repository, args.packages.resolve(), args.output.resolve())
