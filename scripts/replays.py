"""Fetch a reproducible replay sample, extract bounded evidence, and check reviewed hits.

Raw replays and decoded candidates belong in observations/local/, outside Git.
Only extraction needs RoflLens 0.1.0 and its optional semantic dependencies.
"""
import argparse
from collections import Counter
import datetime
import hashlib
import importlib.metadata
import json
import math
from pathlib import Path
import random
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

from replay_framing import iter_blocks

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'observations/replays/sources.json'


def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def save(path, record):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + '.part')
    temporary.write_text(json.dumps(record, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    temporary.replace(path)


def sha256(path):
    with Path(path).open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def source_by_id(source_id, catalog=SOURCES):
    catalog = load(catalog)
    if catalog.get('format') != 'powerspike-replay-sources' or catalog.get('version') != 1:
        raise ValueError('Unsupported replay source catalog')
    return next(s for s in catalog['sources'] if s['id'] == source_id)


def select_sample(source, seed):
    samples = sorted(source['samples'], key=lambda sample: sample['filename'])
    names = [s['filename'] for s in samples]
    if not names or len(names) != len(set(names)):
        raise ValueError('Replay source needs distinct samples')
    if any(Path(name).name != name or '/' in name or '\\' in name for name in names):
        raise ValueError('Unsafe replay filename')
    return random.Random(seed).choice(samples), names


def fetch(source, seed, output, max_bytes):
    sample, population = select_sample(source, seed)
    if not 0 < sample['bytes'] <= max_bytes:
        raise ValueError('Selected replay exceeds download budget; selection was not changed')
    if not sample['url'].startswith('https://'):
        raise ValueError('Replay source must use HTTPS')
    output.mkdir(parents=True, exist_ok=False)
    path = output / sample['filename']
    partial = path.with_suffix('.rofl.part')
    started = time.monotonic()
    transferred = 0
    try:
        with urllib.request.urlopen(sample['url'], timeout=30) as response, partial.open('wb') as handle:
            while chunk := response.read(1024 * 1024):
                transferred += len(chunk)
                if transferred > min(max_bytes, sample['bytes']):
                    raise ValueError('Replay response exceeds declared size or budget')
                handle.write(chunk)
        if transferred != sample['bytes'] or sha256(partial) != sample['sha256']:
            raise ValueError('Replay size or SHA-256 differs from the pinned source')
        partial.replace(path)
    finally:
        partial.unlink(missing_ok=True)
    receipt = {
        'format': 'powerspike-replay-receipt', 'version': 1,
        'source-id': source['id'], 'source-url': source['url'],
        'sample': sample, 'seed': seed, 'population': population,
        'selection-method': 'Python Random(seed).choice(sorted filenames); uniform within this corpus only',
        'client-build': source['client-build'], 'protocol-digest': source['protocol-digest'],
        'client-sha256': source['client-sha256'], 'parser': source['parser'],
        'captured-at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'cost': {'download-bytes': transferred, 'download-seconds': time.monotonic() - started},
    }
    save(output / 'receipt.json', receipt)
    return receipt


def event_id(block):
    # Transport location is stable across decoder changes, unlike a row counter.
    return '%s:%s:%s' % (block.stream, block.chunk_id, block.block_offset)


def replay_header(path):
    from rofllens import ReplayReader
    with ReplayReader.open(path) as replay:
        return replay.header.as_dict()


def import_local(path, provenance, client_exe, output, max_bytes):
    """Register a participant-contributed file; this does not certify its contents."""
    if not provenance.strip():
        raise ValueError('Contributed replays need a provenance note or source URL')
    size = path.stat().st_size
    if not 0 < size <= max_bytes:
        raise ValueError('Contributed replay exceeds size budget')
    header = replay_header(path)
    client_digest = sha256(client_exe)
    replay_digest = sha256(path)
    output.mkdir(parents=True, exist_ok=False)
    destination = output / 'contributed.rofl'
    started = time.monotonic()
    shutil.copyfile(path, destination)
    if sha256(destination) != replay_digest:
        destination.unlink()
        raise ValueError('Contributed replay changed while copying')
    receipt = {
        'format': 'powerspike-replay-receipt', 'version': 1,
        'source-id': 'contributed-file', 'source-url': provenance,
        'sample': {'filename': destination.name, 'url': None, 'bytes': size, 'sha256': replay_digest},
        'seed': None, 'population': None,
        'selection-method': 'Operator-selected contribution; not a random population sample',
        'client-build': header['clientVersion'], 'protocol-digest': header['protocolDigest'],
        'client-sha256': client_digest,
        'parser': source_by_id('rofllens-v0.1.0')['parser'],
        'captured-at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'cost': {'download-bytes': 0, 'download-seconds': 0,
                 'import-seconds': time.monotonic() - started},
    }
    save(output / 'receipt.json', receipt)
    return receipt


def extract(receipt_path, profile_path, client_exe, max_events, max_seconds):
    from rofllens import ReplayReader
    from rofllens.decoders.base import DecoderContext
    from rofllens.decoders.combat import UnitApplyDamageDecoder
    from rofllens.decoders.emulator import UnicornDecoderEngine
    from rofllens.decoders.profile import load_profile

    if importlib.metadata.version('rofllens') != '0.1.0':
        raise ValueError('This adapter requires RoflLens 0.1.0')
    receipt_path = Path(receipt_path)
    receipt = load(receipt_path)
    output = receipt_path.parent
    replay_path = output / receipt['sample']['filename']
    if sha256(replay_path) != receipt['sample']['sha256']:
        raise ValueError('Replay checksum mismatch')
    if sha256(client_exe) != receipt['client-sha256']:
        raise ValueError('Exact client checksum mismatch; no patch substitution allowed')
    profile = load_profile(profile_path)
    if not profile.matches(client_version=receipt['client-build'],
                           protocol_digest=receipt['protocol-digest'],
                           client_sha256=receipt['client-sha256']):
        raise ValueError('Decoder profile does not match receipt')
    if profile.player_id_start is None:
        raise ValueError('Decoder has no player object range')
    opcode = profile.decoders['unitApplyDamage']['opcode']
    started, cpu_started = time.monotonic(), time.process_time()
    engine = UnicornDecoderEngine(profile_path, client_exe)
    decoder = UnitApplyDamageDecoder(engine)
    context = DecoderContext(profile, receipt['client-build'], receipt['protocol-digest'], receipt['client-sha256'])
    counts = Counter()
    failures = Counter()
    reasons = Counter()
    damage_types = Counter()
    rows = []
    bounded = None
    with ReplayReader.open(replay_path) as replay:
        if (replay.header.client_version != receipt['client-build'] or
                replay.header.protocol_digest != receipt['protocol-digest']):
            raise ValueError('Replay header disagrees with receipt')
        summary = replay.summary(verify=False).as_dict()
        champions = [p.get('SKIN') for p in replay.metadata.participants]
        # Keyframes restore state and MUST NOT be counted as new damage events.
        for block in iter_blocks(replay, streams={'gameChunk'}, opcodes={opcode}, include_payload=True):
            counts['damage-packets-seen'] += 1
            if len(rows) + counts['decode-failures'] >= max_events or time.monotonic() - started >= max_seconds:
                bounded = 'event-limit' if len(rows) + counts['decode-failures'] >= max_events else 'time-limit'
                break
            if not profile.player_id_start <= block.param < profile.player_id_start + len(champions):
                counts['non-player-target-packets-skipped'] += 1
                continue
            try:
                event = decoder.decode(block, context)
            except Exception as error:
                counts['decode-failures'] += 1
                failures[type(error).__name__] += 1
                continue
            fields = event.fields
            counts['decoded-damage-events'] += 1
            damage_types[fields['damageType']] += 1
            if fields.get('sourceIsPlayer') and fields.get('targetIsPlayer'):
                counts['candidate-player-to-player-events'] += 1
            reason = 'pre-hit-state-and-packet-semantics-unreviewed'
            reasons[reason] += 1
            rows.append({
                'event-id': event_id(block), 'replay-sha256': receipt['sample']['sha256'],
                'client-build': receipt['client-build'], 'timestamp': event.timestamp,
                'chunk-id': block.chunk_id, 'block-offset': block.block_offset,
                'opcode': opcode, 'decode-status': event.decode_status,
                'raw-payload-hex': block.payload.hex(), 'fields': fields,
                'verification-status': 'unreviewed', 'skip-reason': reason,
            })
        report = {
            'format': 'powerspike-replay-extraction', 'version': 1,
            'adapter-sha256': sha256(__file__),
            'framing-adapter-sha256': sha256(Path(__file__).with_name('replay_framing.py')),
            'relative-param-decoding': 'signed-int8',
            'source-id': receipt['source-id'], 'source-url': receipt['source-url'],
            'replay-sha256': receipt['sample']['sha256'], 'client-build': receipt['client-build'],
            'protocol-digest': receipt['protocol-digest'], 'client-sha256': receipt['client-sha256'],
            'parser': receipt['parser'], 'profile-sha256': sha256(profile_path),
            'dependency-versions': {name: importlib.metadata.version(name) for name in
                                    ('rofllens', 'zstandard', 'pefile', 'capstone', 'unicorn')},
            'champions': champions, 'game-duration-seconds': (replay.metadata.game_length or 0) / 1000,
            'counts': dict(counts), 'decode-failures': dict(failures), 'skip-reasons': dict(reasons),
            'candidate-damage-types': dict(damage_types),
            'bounded-by': bounded, 'scan-complete': bounded is None,
            'limits': {'max-events': max_events, 'max-seconds': max_seconds},
            'coverage': {'verified-comparisons': 0, 'consistent': 0, 'mismatch': 0,
                         'mechanics-verified': [], 'champions-verified': [],
                         'scope': 'Extracted candidates; no champion, mechanic or patch accuracy established.'},
            'cost': {**receipt['cost'], 'extract-wall-seconds': time.monotonic() - started,
                     'extract-cpu-seconds': time.process_time() - cpu_started,
                     'replay-bytes': replay_path.stat().st_size, 'client-bytes': Path(client_exe).stat().st_size,
                     'human-review-seconds': None},
            'container': {key: summary[key] for key in ('chunkCount', 'compressedBytes', 'uncompressedBytes')},
        }
    save(output / 'events.json', {'format': 'powerspike-replay-events', 'version': 1, 'events': rows})
    report['cost']['events-bytes'] = (output / 'events.json').stat().st_size
    report['events-sha256'] = sha256(output / 'events.json')
    save(output / 'extraction.json', report)
    return report


def patch_family(version):
    parts = version.removeprefix('lolpatch_').split('.')
    return tuple(parts[:2]) if len(parts) >= 2 and all(p.isdigit() for p in parts) else None


def finite(value):
    return not isinstance(value, bool) and isinstance(value, (int, float)) and math.isfinite(value)


def prepare_case(event, case):
    """Bind a reviewed scenario to the recorded number; never accept a hand-entered observation."""
    if case.get('reviewed') is not True:
        return 'unreviewed'
    if (case.get('replay-sha256') != event['replay-sha256'] or
            case.get('client-build') != event['client-build']):
        return 'evidence-identity-mismatch'
    if not all(isinstance(case.get('evidence', {}).get(key), str) and case['evidence'][key].strip()
               for key in ('packet-semantics', 'pre-hit-state', 'actions', 'patch-data')):
        return 'missing-review-evidence'
    document = case.get('scenario-document') or {}
    definition = document.get('scenario', {})
    if (patch_family(definition.get('patch', '')) is None or
            patch_family(definition.get('patch', '')) != patch_family(event['client-build'])):
        return 'patch-mismatch'
    if definition.get('samples') != 1:
        return 'single-observed-hit-requires-one-trial'
    tolerance = case.get('tolerance')
    amount = event['fields'].get('damageAmount')
    if not finite(tolerance) or tolerance < 0 or not finite(amount) or amount < 0:
        return 'invalid-measurement-or-tolerance'
    if not case.get('required-source') or not case.get('mechanic'):
        return 'missing-mechanic-or-source'
    return None


def compare_outcome(event, case, outcome):
    definition = case['scenario-document']['scenario']
    simulated = outcome.get('scenario', {})
    if any(definition.get(key) != simulated.get(key) for key in ('patch', 'snapshot', 'model')):
        return {'status': 'model-or-snapshot-mismatch', 'checked': False}
    if outcome.get('unsupported'):
        return {'status': 'unsupported-scenario', 'checked': False, 'unsupported': outcome['unsupported']}
    if outcome.get('samples') != 1:
        return {'status': 'single-observed-hit-requires-one-trial', 'checked': False}
    hits = [row for row in outcome.get('trace', []) if row.get('kind') == 'damage']
    if len(hits) != 1 or str(hits[0].get('source')) != case['required-source']:
        return {'status': 'scenario-does-not-isolate-recorded-hit', 'checked': False}
    hit = hits[0]
    if (hit.get('type') != event['fields'].get('damageType') or hit.get('absorbed', 0) != 0 or
            not finite(hit.get('health')) or hit['health'] <= 0):
        return {'status': 'damage-type-shield-or-overkill-unresolved', 'checked': False}
    predicted, observed = hit.get('damage'), event['fields']['damageAmount']
    if not finite(predicted):
        return {'status': 'missing-prediction', 'checked': False}
    error = predicted - observed
    return {'status': 'consistent' if abs(error) <= case['tolerance'] else 'mismatch',
            'checked': True, 'predicted': predicted, 'observed': observed, 'error': error,
            'tolerance': case['tolerance'], 'patch': simulated['patch'],
            'snapshot': simulated['snapshot'], 'model': simulated['model'],
            'mechanic': case['mechanic'], 'scope': 'One reviewed isolated hit only.'}


def compare(events_path, cases_path, executable, output, data_dir=None):
    events_document = load(events_path)
    if events_document.get('format') != 'powerspike-replay-events' or events_document.get('version') != 1:
        raise ValueError('Unsupported replay events document')
    events = {event['event-id']: event for event in events_document['events']}
    if len(events) != len(events_document['events']):
        raise ValueError('Duplicate replay event IDs')
    cases = load(cases_path)
    if cases.get('format') != 'powerspike-replay-reviews' or cases.get('version') != 1:
        raise ValueError('Unsupported replay reviews document')
    seen, rows = set(), []
    started = time.monotonic()
    for case in cases['cases']:
        key = case['event-id']
        if key in seen:
            raise ValueError('Duplicate review would count one event twice: ' + key)
        seen.add(key)
        event = events.get(key)
        reason = prepare_case(event, case) if event else 'event-not-found'
        result = {'status': reason, 'checked': False}
        if reason is None:
            with tempfile.TemporaryDirectory(prefix='powerspike-replay-') as temp:
                path = Path(temp) / 'scenario.json'
                save(path, case['scenario-document'])
                command = [str(Path(executable).resolve()), '--simulate', str(path)]
                if data_dir:
                    command += ['--data-dir', str(Path(data_dir).resolve())]
                try:
                    run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=30, check=True)
                    result = compare_outcome(event, case, json.loads(run.stdout))
                except (subprocess.SubprocessError, OSError, ValueError) as error:
                    result = {'status': 'simulation-unavailable', 'checked': False, 'reason': str(error)[:300]}
        rows.append({'event-id': key, 'replay-sha256': event['replay-sha256'] if event else None,
                     'client-build': event['client-build'] if event else None,
                     'mechanic': case.get('mechanic'),
                     'champion': case.get('scenario-document', {}).get('scenario', {}).get('player', {}).get('champion')
                     if case.get('scenario-document') else None, **result})
    statuses = Counter(row['status'] for row in rows)
    groups = {}
    for row in rows:
        if row['checked']:
            key = (row['patch'], row['mechanic'], row['champion'])
            group = groups.setdefault(key, {'patch': key[0], 'mechanic': key[1], 'champion': key[2],
                                             'checked': 0, 'consistent': 0, 'mismatch': 0})
            group['checked'] += 1
            group[row['status']] += 1
    report = {'format': 'powerspike-replay-comparison', 'version': 1,
              'adapter-sha256': sha256(__file__),
              'events-sha256': sha256(events_path), 'reviews-sha256': sha256(cases_path), 'rows': rows,
              'coverage': {'extracted-events': len(events), 'submitted-cases': len(rows),
                           'reviewed-cases': sum(case.get('reviewed') is True for case in cases['cases']),
                           'unsubmitted-events': len(set(events) - seen),
                           'verified-comparisons': sum(row['checked'] for row in rows),
                           'consistent': statuses['consistent'], 'mismatch': statuses['mismatch'],
                           'statuses': dict(statuses), 'by-patch-mechanic-champion': list(groups.values())},
              'cost': {'comparison-wall-seconds': time.monotonic() - started,
                       'human-review-seconds': cases.get('human-review-seconds')}}
    save(output, report)
    return report


def positive_int(value):
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError('must be positive')
    return parsed


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    fetch_parser = commands.add_parser('fetch')
    fetch_parser.add_argument('--source', default='rofllens-v0.1.0')
    fetch_parser.add_argument('--seed', type=int, help='recorded automatically when omitted')
    fetch_parser.add_argument('--output', type=Path, required=True, help='new directory under observations/local/')
    fetch_parser.add_argument('--max-download-mib', type=positive_int, default=32)
    import_parser = commands.add_parser('import')
    import_parser.add_argument('--input', type=Path, required=True)
    import_parser.add_argument('--provenance', required=True, help='source URL or contribution origin; stored locally')
    import_parser.add_argument('--client-exe', type=Path, required=True)
    import_parser.add_argument('--output', type=Path, required=True)
    import_parser.add_argument('--max-replay-mib', type=positive_int, default=32)
    extract_parser = commands.add_parser('extract')
    extract_parser.add_argument('--receipt', type=Path, required=True)
    extract_parser.add_argument('--profile', type=Path, required=True)
    extract_parser.add_argument('--client-exe', type=Path, required=True)
    extract_parser.add_argument('--max-events', type=positive_int, default=500)
    extract_parser.add_argument('--max-seconds', type=positive_int, default=30)
    compare_parser = commands.add_parser('compare')
    compare_parser.add_argument('--events', type=Path, required=True)
    compare_parser.add_argument('--reviews', type=Path, required=True)
    compare_parser.add_argument('--executable', type=Path, default=ROOT / 'dist/bin/powerspike')
    compare_parser.add_argument('--data-dir', type=Path)
    compare_parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    if args.command == 'fetch':
        seed = args.seed if args.seed is not None else random.SystemRandom().randrange(2**32)
        result = fetch(source_by_id(args.source), seed, args.output, args.max_download_mib * 1024**2)
        print('Saved %s; seed %s; checksum verified.' % (result['sample']['filename'], seed))
    elif args.command == 'import':
        result = import_local(args.input, args.provenance, args.client_exe, args.output,
                              args.max_replay_mib * 1024**2)
        print('Registered contribution for %s; context remains unreviewed.' % result['client-build'])
    elif args.command == 'extract':
        result = extract(args.receipt, args.profile, args.client_exe, args.max_events, args.max_seconds)
        print(json.dumps({'counts': result['counts'], 'coverage': result['coverage'], 'cost': result['cost']}))
    else:
        result = compare(args.events, args.reviews, args.executable, args.output, args.data_dir)
        print(json.dumps(result['coverage']))
        return 1 if result['coverage']['mismatch'] else (2 if not result['coverage']['verified-comparisons'] else 0)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, KeyError, StopIteration, OSError, ImportError) as error:
        print('Replay verification failed: %s' % error, file=sys.stderr)
        sys.exit(1)
