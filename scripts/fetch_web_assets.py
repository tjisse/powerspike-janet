"""Fetch pinned frontend assets into ignored build output; no runtime CDN requests."""
import hashlib
import json
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import urllib.request


def retrieve(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'Powerspike-asset-setup/1'})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--record-catalog-hashes', action='store_true')
    args = parser.parse_args()
    root = Path('build/web-assets')
    root.mkdir(parents=True, exist_ok=True)
    bundle_url = 'https://cdn.jsdelivr.net/gh/starfederation/datastar@v1.0.2/bundles/datastar.js'
    expected = '2837d87acf6ee0ba8e4e63765926c25a98d63883b02f88be194a86b81d3fd24a'
    destination = root / 'datastar.js'
    data = destination.read_bytes() if destination.exists() else retrieve(bundle_url)
    if hashlib.sha256(data).hexdigest() != expected:
        raise ValueError('Datastar browser bundle does not match the pinned SDK-compatible asset')
    destination.write_bytes(data)
    manifest = json.loads(Path('docs/design/art-assets.json').read_text())
    for asset in manifest['assets']:
        destination = root / asset['path']
        destination.parent.mkdir(parents=True, exist_ok=True)
        data = destination.read_bytes() if destination.exists() else retrieve(manifest['cdn_base'] + asset['path'])
        if not data.startswith(b'\x89PNG\r\n\x1a\n'):
            raise ValueError('Expected a PNG image for ' + asset['path'])
        expected_blob = asset.get('git_blob_sha')
        actual_blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        if expected_blob and actual_blob != expected_blob:
            raise ValueError('Artwork does not match pinned repository blob: ' + asset['path'])
        destination.write_bytes(data)
    catalog_root = Path('data/16.19.1/catalog')
    catalog_assets = set()
    for group, filename in [('champion', 'champions-ddragon.json'), ('item', 'items-ddragon.json')]:
        source = json.loads((catalog_root / 'sources' / filename).read_text())
        for entry in source['data'].values():
            catalog_assets.add(group + '/' + entry['image']['full'])
    hashes_path = catalog_root / 'art-manifest.json'
    expected_hashes = {} if args.record_catalog_hashes else json.loads(hashes_path.read_text())['sha256']
    if not args.record_catalog_hashes and set(expected_hashes) != catalog_assets:
        raise ValueError('Catalog artwork coverage differs from the pinned source')
    def fetch_catalog(path):
        destination = root / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        data = destination.read_bytes() if destination.exists() else retrieve(
            'https://ddragon.leagueoflegends.com/cdn/16.19.1/img/' + path)
        if not data.startswith(b'\x89PNG\r\n\x1a\n'):
            raise ValueError('Expected catalog PNG: ' + path)
        actual = hashlib.sha256(data).hexdigest()
        if not args.record_catalog_hashes and actual != expected_hashes[path]:
            raise ValueError('Catalog artwork hash mismatch: ' + path)
        destination.write_bytes(data)
        return path, actual
    actual_hashes = {}
    with ThreadPoolExecutor(max_workers=8) as pool:
        jobs = [pool.submit(fetch_catalog, path) for path in sorted(catalog_assets)]
        for index, job in enumerate(as_completed(jobs), 1):
            path, sha = job.result()
            actual_hashes[path] = sha
            if index % 200 == 0:
                print('Catalog artwork:', index, '/', len(jobs), flush=True)
    if args.record_catalog_hashes:
        hashes_path.write_text(json.dumps({'patch': '16.19.1',
            'base_url': 'https://ddragon.leagueoflegends.com/cdn/16.19.1/img/',
            'sha256': dict(sorted(actual_hashes.items()))}, indent=2) + '\n')
    license_path = root / 'licenses/datastar-browser-LICENSE'
    license_path.parent.mkdir(parents=True, exist_ok=True)
    if not license_path.exists():
        license_path.write_bytes(retrieve('https://cdn.jsdelivr.net/gh/starfederation/datastar@v1.0.2/LICENSE.md'))
    print('Pinned Datastar and Riot artwork ready; all frontend requests stay local.')


if __name__ == '__main__':
    main()
