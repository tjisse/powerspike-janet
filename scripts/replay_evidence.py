"""Index retained replay archives once; extract batches without replay playback.

Checkpoints preserve observed state, provenance, unknowns and buff lifecycle
issues. They are not exact server state or automatic semantic admission. Source
archives are immutable inputs: use `verify --sources` to check them again.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path
import sqlite3
import tempfile
import time
import zlib

from replay_attack_review import archive, continuity
from replay_buffs import BuffLedger, wire_key
from replay_gaps import SEMANTIC_GAPS
from replay_native import BUILD, PROTOCOL
from replay_recovery import digest, load
from replay_review_fields import fields as extra_fields
from replay_state import derived_stats, replication_records

VERSION = 1
ADAPTERS = ('replay_evidence.py', 'replay_attack_review.py', 'replay_buffs.py',
            'replay_state.py', 'replay_review_fields.py', 'replay_gaps.py', 'replay_recovery.py')
STREAMS = {'combat': {'state': 'state.jsonl.gz', 'damage': 'damage.jsonl.gz'},
           'audit': {'case': 'cases.jsonl.gz'},
           'actions': {'action': 'actions.jsonl.gz'},
           'buffs': {'buff': 'buffs.jsonl.gz'},
           'outcomes': {'outcome': 'damage-outcomes.jsonl.gz', 'action-slot': 'action-slots.jsonl.gz'},
           'attack-review': {'attack-context': 'attack-context.jsonl.gz'}}
LIMITS = ['Observed client state only; missing fields remain unknown.',
          'Buff presence, counters and durations do not establish effect behavior or completeness.',
          'Local event windows do not prove absence of earlier actions; query indexed history.',
          'API event times are a separate, coarse clock, not exact replay ordering.',
          'No semantic blockers are resolved and no model comparison is admitted by extraction.']


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False)


def fingerprint(value):
    return hashlib.sha256(encoded(value).encode()).hexdigest()


def packed(value):
    # Independent compressed records preserve indexed access; unlike a gzip
    # stream, reading a late record does not decompress its predecessors.
    return zlib.compress(encoded(value).encode(), level=1)


def unpacked(value):
    return json.loads(zlib.decompress(value))


def adapters():
    return {name: digest(Path(__file__).with_name(name)) for name in ADAPTERS}


def checked_key(event):
    key = wire_key(event)
    if min(key) < 0 or event != f'gameChunk:{key[0]}:{key[1]}':
        raise ValueError('Noncanonical gameplay event ID')
    return key


def receipt(folder, name, expected):
    if Path(name).name != name or not name:
        raise ValueError('Unsafe receipt path')
    path = folder / name
    if digest(path) != expected:
        raise ValueError(f'Archive receipt mismatch: {name}')
    return {'path': str(path.resolve()), 'sha256': expected}


def inputs(folders, match=None, timeline=None):
    reports = {label: load(folder / 'summary.json') for label, folder in folders.items()}
    combat = reports['combat']
    for report in reports.values():
        if (report.get('replay-sha256') != combat['replay-sha256']
                or report.get('client-build') != BUILD or report.get('protocol-digest') != PROTOCOL
                or report.get('failures')):
            raise ValueError('Source identity/build mismatch or incomplete extraction')
        for name in ('image-sha256', 'profile-sha256'):
            if name in report and report[name] != combat[name]:
                raise ValueError('Source native decoder identity mismatch')
    files = {label + '/summary.json': {'path': str((folder / 'summary.json').resolve()),
                                     'sha256': digest(folder / 'summary.json')}
             for label, folder in folders.items()}
    for label, report in reports.items():
        for group in ('archives', 'evidence-files'):
            for name, expected in report.get(group, {}).items():
                files[label + '/' + name] = receipt(folders[label], name, expected)
    for name, expected in reports['audit']['source-files'].items():
        files['combat/' + name] = receipt(folders['combat'], name, expected)
    aliases = {'gap-audit': 'audit'}
    for label in ('outcomes', 'attack-review'):
        for parent, expected in reports[label]['inputs'].items():
            if files[aliases.get(parent, parent) + '/summary.json']['sha256'] != expected:
                raise ValueError('Derived archive belongs to a different extraction revision')
    for label, streams in STREAMS.items():
        for name in streams.values():
            if label + '/' + name not in files:
                raise ValueError('Missing archive receipt')
    if (match is None) != (timeline is None):
        raise ValueError('Provide both API match and timeline, or neither')
    if match is not None:
        for label, path in (('match', match), ('timeline', timeline)):
            expected = combat.get('validation', {}).get(label + '-sha256')
            if expected is None or digest(path) != expected:
                raise ValueError('API source differs from combat validation receipt')
            files['api/' + label] = {'path': str(Path(path).resolve()), 'sha256': expected}
    return reports, files


def normalize(row, entities):
    observations = []
    for record in replication_records(bytes.fromhex(row['decoded-buffer-hex']), entities):
        if record['entity'] not in entities:
            continue
        values, issues, unknown = dict(record['fields']), [], []
        for component in record['components']:
            try:
                values.update(extra_fields(component))
            except ValueError as error:
                # Core fields were independently parsed above. An unsupported
                # extended encoding must not preserve an older resource value.
                names = (['primary-resource', 'primary-resource-max'] if component['group'] == 32 else
                         ['action-state-code', 'action-state2-code', 'status-flags-code',
                          'physical-damage-percentage-modifier', 'magical-damage-percentage-modifier'])
                unknown.extend(names)
                issues.append({'event-id': row['event-id'], 'group': component['group'],
                               'reason': str(error), 'unknown-fields': names})
        observations.append({'entity': record['entity'], 'fields': values,
                             'unknown-fields': unknown, 'issues': issues})
    return observations


class Reconstruction:
    def __init__(self, checkpoint=None):
        data = checkpoint or {}
        self.stats = data.get('stats', {})
        self.issues = data.get('issues', {})
        self.buffs = BuffLedger()
        for entity, active in data.get('buffs', {}).items():
            self.buffs.active[int(entity)] = {int(token): value for token, value in active.items()}
        for entity, issues in data.get('buff-issues', {}).items():
            self.buffs.issues[int(entity)] = issues
        self.buffs.counts = Counter(data.get('buff-counts', {}))
        previous = data.get('buff-previous')
        self.buffs.previous = tuple(previous) if previous is not None else None

    def apply(self, kind, row):
        if kind == 'buff':
            self.buffs.apply(row)
            return
        for record in row['observations']:
            entity = str(record['entity'])
            values = self.stats.setdefault(entity, {})
            self.issues.setdefault(entity, []).extend(record['issues'])
            for name in record['unknown-fields']:
                values.pop(name, None)
            for name, value in record['fields'].items():
                values[name] = {'value': value, 'event-id': row['event-id'],
                                'timestamp': row['timestamp'], 'wire-key': list(checked_key(row['event-id']))}

    def checkpoint(self):
        return {'stats': self.stats, 'issues': self.issues,
                'buffs': dict(self.buffs.active), 'buff-issues': dict(self.buffs.issues),
                'buff-counts': dict(self.buffs.counts), 'buff-previous': self.buffs.previous}

    def snapshot(self, roster, timestamp):
        result = {}
        for player in roster:
            entity = player['entity']
            observed = {name: {**sample, 'age-seconds': timestamp - sample['timestamp'],
                               'same-timestamp': timestamp == sample['timestamp']}
                        for name, sample in self.stats.get(str(entity), {}).items()}
            observed.update(derived_stats(observed))
            result[str(entity)] = {**player, 'last-observed': observed,
                                   'observation-issues': self.issues.get(str(entity), []),
                                   'buffs': self.buffs.snapshot(entity)}
        return result


def add_api(db, combat, match_path, timeline_path):
    if match_path is None:
        return
    match, timeline = load(match_path), load(timeline_path)
    players = {(p['championName'], p['teamId']): p for p in match['info']['participants']}
    entity_ids = {}
    for player in combat['roster']:
        p = players[player['champion'], player['team']]
        entity = combat['champion-entity-start'] + player['slot']
        entity_ids[p['participantId']] = entity
        # Intentionally omit account IDs, Riot IDs, player names and final builds.
        selection = {'champion': player['champion'], 'team': player['team'],
                     'runes': [s['perk'] for style in p['perks']['styles'] for s in style['selections']],
                     'stat-perks': p['perks'].get('statPerks', {}),
                     'summoner-spells': [p['summoner1Id'], p['summoner2Id']]}
        db.execute('INSERT INTO selections VALUES (?,?)', (entity, encoded(selection)))
    keys = ('timestamp', 'type', 'itemId', 'beforeId', 'afterId', 'goldGain', 'skillSlot',
            'levelUpType', 'wardType', 'monsterType', 'buildingType')
    actors = ('participantId', 'creatorId', 'killerId', 'victimId')
    for frame in timeline['info']['frames']:
        for event in frame['events']:
            if not (event['type'].startswith('ITEM_') or event['type'] in
                    ('SKILL_LEVEL_UP', 'CHAMPION_KILL', 'ELITE_MONSTER_KILL', 'BUILDING_KILL', 'WARD_PLACED')):
                continue
            safe = {k: event[k] for k in keys if k in event}
            safe['actors'] = {k: entity_ids.get(event[k]) for k in actors if k in event}
            safe['assisting-entities'] = [entity_ids.get(i) for i in event.get('assistingParticipantIds', [])]
            db.execute('INSERT INTO api_events (timestamp,row) VALUES (?,?)', (event['timestamp'], encoded(safe)))


def build(folders, output, checkpoint_every=256, match=None, timeline=None):
    started = time.monotonic()
    output = Path(output)
    if output.exists() or type(checkpoint_every) is not int or checkpoint_every < 1:
        raise ValueError('Choose a fresh output directory and positive checkpoint interval')
    folders = {label: Path(folders[label]) for label in STREAMS}
    reports, files = inputs(folders, match, timeline)
    combat = reports['combat']
    roster = [{**p, 'entity': combat['champion-entity-start'] + p['slot']} for p in combat['roster']]
    entities = {p['entity'] for p in roster}
    manifest = {'format': 'powerspike-replay-evidence-store', 'version': VERSION,
                'replay-sha256': combat['replay-sha256'], 'client-build': BUILD,
                'protocol-digest': PROTOCOL, 'roster': roster, 'sources': files,
                'adapters': adapters(), 'checkpoint-every': checkpoint_every, 'limits': LIMITS}
    manifest['identity'] = fingerprint({**manifest, 'sources': {k: v['sha256'] for k, v in files.items()}})
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.replay-evidence-', dir=output.parent) as temp:
        temp = Path(temp)
        db = sqlite3.connect(temp / 'events.sqlite')
        try:
            db.executescript('''
                CREATE TABLE events (kind TEXT, event TEXT, chunk INTEGER, offset INTEGER,
                    timestamp REAL, actor INTEGER, target INTEGER, row BLOB, PRIMARY KEY(kind,event));
                CREATE INDEX event_order ON events(kind,chunk,offset);
                CREATE INDEX actor_order ON events(kind,actor,chunk,offset);
                CREATE INDEX event_time ON events(kind,timestamp);
                CREATE TABLE mutations (chunk INTEGER, offset INTEGER, kind TEXT, event TEXT,
                    PRIMARY KEY(chunk,offset));
                CREATE TABLE checkpoints (chunk INTEGER, offset INTEGER, row BLOB,
                    PRIMARY KEY(chunk,offset));
                CREATE TABLE observations (entity INTEGER, field TEXT, chunk INTEGER, offset INTEGER,
                    timestamp REAL, row TEXT, PRIMARY KEY(entity,field,chunk,offset));
                CREATE TABLE selections (entity INTEGER PRIMARY KEY, row TEXT);
                CREATE TABLE api_events (timestamp INTEGER, row TEXT);
                CREATE INDEX api_time ON api_events(timestamp);
            ''')
            counts = Counter()
            for label, streams in STREAMS.items():
                for kind, name in streams.items():
                    for row in archive(folders[label] / name):
                        chunk, offset = checked_key(row['event-id'])
                        if not math.isfinite(row['timestamp']):
                            raise ValueError('Nonfinite event timestamp')
                        if kind == 'state':
                            row = {**row, 'observations': normalize(row, entities)}
                        db.execute('INSERT INTO events VALUES (?,?,?,?,?,?,?,?)',
                                   (kind, row['event-id'], chunk, offset, row['timestamp'],
                                    row.get('source', row.get('entity')), row.get('target'), packed(row)))
                        if kind in ('state', 'buff'):
                            db.execute('INSERT INTO mutations VALUES (?,?,?,?)', (chunk, offset, kind, row['event-id']))
                        if kind == 'state':
                            for record in row['observations']:
                                for name in set(record['fields']) | set(record['unknown-fields']):
                                    sample = {'event-id': row['event-id'], 'timestamp': row['timestamp'],
                                              'wire-key': [chunk, offset], 'known': name in record['fields']}
                                    if sample['known']:
                                        sample['value'] = record['fields'][name]
                                    db.execute('INSERT INTO observations VALUES (?,?,?,?,?,?)',
                                               (record['entity'], name, chunk, offset, row['timestamp'], encoded(sample)))
                        counts[kind] += 1
            for kind, expected in [('state', combat['counts']['state-accepted']),
                                   ('damage', combat['counts']['damage-accepted']),
                                   ('case', reports['audit']['counts']['champion-to-champion-events']),
                                   ('action', sum(reports['actions']['counts'].values())),
                                   ('buff', sum(reports['buffs']['counts'].values())),
                                   ('attack-context', reports['attack-review']['counts']['ordinary-candidates']),
                                   ('outcome', counts['case']), ('action-slot', counts['action'])]:
                if counts[kind] != expected:
                    raise ValueError(f'Incomplete indexed archive: {kind}')
            # Count equality alone cannot establish that two archives cover the same events.
            for left, right in [('case', 'outcome'), ('action', 'action-slot')]:
                missing = db.execute('SELECT event FROM events WHERE kind=? EXCEPT SELECT event FROM events WHERE kind=?',
                                     (left, right)).fetchone()
                if missing:
                    raise ValueError('Indexed event identities disagree')
            for raw, in db.execute("SELECT row FROM events WHERE kind='case'"):
                case = unpacked(raw)
                for kind in ('damage', 'outcome'):
                    other = db.execute('SELECT row FROM events WHERE kind=? AND event=?',
                                       (kind, case['event-id'])).fetchone()
                    if other is None:
                        raise ValueError('Case has no matching native damage observation')
                    other = unpacked(other[0])
                    for name in ('source', 'target', 'timestamp', 'damage-type'):
                        if other[name] != case[name]:
                            raise ValueError('Indexed damage observations disagree')
                    if other.get('amount', other.get('recorded-amount')) != case['recorded-amount']:
                        raise ValueError('Indexed damage amounts disagree')
            state = Reconstruction()
            db.execute('INSERT INTO checkpoints VALUES (-1,-1,?)', (packed(state.checkpoint()),))
            mutations = 0
            for chunk, offset, kind, raw in db.execute('SELECT m.chunk,m.offset,m.kind,e.row FROM mutations m '
                    'JOIN events e ON e.kind=m.kind AND e.event=m.event ORDER BY m.chunk,m.offset'):
                state.apply(kind, unpacked(raw))
                mutations += 1
                if mutations % checkpoint_every == 0:
                    db.execute('INSERT INTO checkpoints VALUES (?,?,?)', (chunk, offset, packed(state.checkpoint())))
            counts['checkpoints'] = db.execute('SELECT count(*) FROM checkpoints').fetchone()[0]
            add_api(db, combat, match, timeline)
            db.commit()
        finally:
            db.close()
        # Detect replacement during ingestion, before publishing a reusable cache.
        for value in files.values():
            if digest(value['path']) != value['sha256']:
                raise ValueError('Input changed during indexing')
        if adapters() != manifest['adapters']:
            raise ValueError('Evidence adapters changed during indexing')
        manifest['database-sha256'] = digest(temp / 'events.sqlite')
        manifest['counts'] = dict(counts)
        manifest['cost'] = {'wall-seconds': time.monotonic() - started,
                            'raw-replay-reads': 0, 'native-decode-calls': 0,
                            'archive-passes': len([k for streams in STREAMS.values() for k in streams])}
        (temp / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        temp.rename(output)
    return manifest


class EvidenceStore:
    def __init__(self, folder, verify_sources=False):
        started = time.monotonic()
        self.folder = Path(folder)
        self.manifest = load(self.folder / 'manifest.json')
        m = self.manifest
        if (m.get('format') != 'powerspike-replay-evidence-store' or m.get('version') != VERSION
                or m.get('adapters') != adapters() or m.get('client-build') != BUILD
                or m.get('protocol-digest') != PROTOCOL):
            raise ValueError('Evidence store schema/adapter revision is stale; rebuild it')
        identity = {k: v for k, v in m.items() if k not in ('identity', 'database-sha256', 'counts', 'cost')}
        identity['sources'] = {k: v['sha256'] for k, v in m['sources'].items()}
        if fingerprint(identity) != m['identity'] or digest(self.folder / 'events.sqlite') != m['database-sha256']:
            raise ValueError('Evidence store fingerprint mismatch')
        if verify_sources:
            for value in m['sources'].values():
                if digest(value['path']) != value['sha256']:
                    raise ValueError('Evidence source changed; build a new store')
        self.db = sqlite3.connect((self.folder / 'events.sqlite').resolve().as_uri() + '?mode=ro', uri=True)
        self.open_cost = {'wall-seconds': time.monotonic() - started,
                          'database-bytes-checked': (self.folder / 'events.sqlite').stat().st_size,
                          'source-archives-checked': verify_sources}

    def close(self):
        self.db.close()

    def event(self, kind, event):
        row = self.db.execute('SELECT row FROM events WHERE kind=? AND event=?', (kind, event)).fetchone()
        return unpacked(row[0]) if row else None

    def history(self, kind, before, entity=None, after=None):
        end = checked_key(before)
        sql = 'SELECT row FROM events WHERE kind=? AND (chunk,offset)<(?,?)'
        args = [kind, *end]
        if after is not None:
            sql += ' AND (chunk,offset)>(?,?)'; args.extend(checked_key(after))
        if entity is not None:
            sql += ' AND actor=?'; args.append(entity)
        sql += ' ORDER BY chunk,offset'
        return [unpacked(r[0]) for r in self.db.execute(sql, args)]

    def before(self, event):
        end = checked_key(event)
        chunk, offset, raw = self.db.execute(
            'SELECT * FROM checkpoints WHERE (chunk,offset)<(?,?) ORDER BY chunk DESC,offset DESC LIMIT 1', end).fetchone()
        state = Reconstruction(unpacked(raw))
        rows = self.db.execute('SELECT m.kind,e.row FROM mutations m JOIN events e '
                               'ON e.kind=m.kind AND e.event=m.event WHERE (m.chunk,m.offset)>(?,?) '
                               'AND (m.chunk,m.offset)<(?,?) ORDER BY m.chunk,m.offset', (chunk, offset, *end))
        applied = 0
        for kind, raw in rows:
            state.apply(kind, unpacked(raw)); applied += 1
        return state, {'checkpoint-after': None if chunk < 0 else f'gameChunk:{chunk}:{offset}',
                       'mutation-events-applied': applied}

    def observation(self, entity, field, event, after=False):
        operator, direction = ('>', 'ASC') if after else ('<', 'DESC')
        row = self.db.execute(f'SELECT row FROM observations WHERE entity=? AND field=? '
                              f'AND (chunk,offset){operator}(?,?) ORDER BY chunk {direction},offset {direction} LIMIT 1',
                              (entity, field, *checked_key(event))).fetchone()
        return json.loads(row[0]) if row else None

    def candidates(self):
        result = []
        for (raw,) in self.db.execute("SELECT row FROM events WHERE kind='case' ORDER BY chunk,offset"):
            case = unpacked(raw)
            context = self.event('attack-context', case['event-id'])
            if (case['effect-kind'] != 'basic-attack-candidate' or case['damage-type'] != 'physical'
                    or case['data-gaps'] or not context or context['status'] != 'unique-candidate'
                    or not context['stat-continuity']['observed-stable']):
                continue
            result.append({k: case[k] for k in ('event-id', 'source', 'target', 'timestamp')} | {
                'observed-armor': case['target-observed']['armor']['value'],
                'observed-ad': case['source-observed']['attack-damage']['value'],
                'observed-crit-chance': case['source-observed'].get('crit-chance', {}).get('value'),
                'model-admissible': False})
        return result

    def package(self, event, window=2):
        if not math.isfinite(window) or not 0 < window <= 10:
            raise ValueError('Event window must be positive and at most ten seconds')
        case = self.event('case', event)
        if case is None:
            raise ValueError('Unknown retained case: ' + event)
        state, cost = self.before(event)
        context = self.event('attack-context', event)
        actions = context['action-candidates'] if context else []
        action = actions[0] if len(actions) == 1 else None
        sampling = None
        if action:
            initial, initial_cost = self.before(action['event-id'])
            cost['action-checkpoint'] = initial_cost
            history = defaultdict(list)
            for role in ('source', 'target'):
                entity = case[role]
                for name, sample in initial.stats.get(str(entity), {}).items():
                    history[entity, name].append({**sample, 'wire-key': tuple(sample['wire-key'])})
            for row in self.history('state', event, after=action['event-id']):
                for record in row['observations']:
                    for name, value in record['fields'].items():
                        history[record['entity'], name].append({'event-id': row['event-id'],
                            'wire-key': checked_key(row['event-id']), 'timestamp': row['timestamp'], 'value': value})
            sampling = continuity(case, action, history)
        local = []
        for kind in ('action', 'damage', 'buff'):
            for chunk, offset, raw in self.db.execute(
                    'SELECT chunk,offset,row FROM events WHERE kind=? AND timestamp>=? AND timestamp<=? '
                    'ORDER BY chunk,offset', (kind, case['timestamp'] - window, case['timestamp'] + window)):
                local.append({'kind': kind, 'relative-order': 'before' if (chunk, offset) < checked_key(event)
                              else 'at' if (chunk, offset) == checked_key(event) else 'after', 'observation': unpacked(raw)})
        local.sort(key=lambda r: checked_key(r['observation']['event-id']))
        api = {'selections': {str(entity): json.loads(raw) for entity, raw in self.db.execute('SELECT * FROM selections')},
               'events-through-api-time': [json.loads(raw) for (raw,) in self.db.execute(
                   'SELECT row FROM api_events WHERE timestamp<=? ORDER BY timestamp,rowid', (case['timestamp'] * 1000,))],
               'exact-replay-alignment': False, 'inventory-and-ranks-reconstructed': False}
        snapshot = state.snapshot(self.manifest['roster'], case['timestamp'])
        health_before = self.observation(case['target'], 'health', event)
        health_after = self.observation(case['target'], 'health', event, after=True)
        health_interval = None
        if health_before and health_after:
            health_interval = {'before': health_before, 'after': health_after,
                               'damage-packets-between': [r for r in self.history(
                                   'damage', health_after['event-id'], after=health_before['event-id'])
                                   if r['target'] == case['target']],
                               'closure-reviewed': False}
        result = {'format': 'powerspike-replay-evidence-package', 'version': VERSION,
                  'store-identity': self.manifest['identity'], 'replay-sha256': self.manifest['replay-sha256'],
                  'client-build': BUILD, 'event-id': event, 'case': case,
                  'observed-before-hit': snapshot, 'attack-context': context,
                  'recomputed-continuity': sampling, 'damage-outcome': self.event('outcome', event),
                  'target-health-interval': health_interval,
                  'action-outcome': self.event('action-slot', action['event-id']) if action else None,
                  'local-events': local, 'local-window-seconds': window,
                  'history-query': {'before': event, 'available-kinds': list({k for s in STREAMS.values() for k in s})},
                  'api-context': api, 'remaining-semantic-blockers': list(SEMANTIC_GAPS),
                  'model-admissible': False, 'limits': LIMITS,
                  'retrieval': {**cost, 'raw-replay-reads': 0, 'source-archive-reads': 0, 'native-decode-calls': 0}}
        result['history-query']['available-kinds'].sort()
        result['evidence-sha256'] = fingerprint(result)
        return result


def batch(store, events, output):
    started = time.monotonic()
    output = Path(output)
    if output.exists() or not events or len(set(events)) != len(events):
        raise ValueError('Choose a fresh batch directory and distinct nonempty event IDs')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.replay-batch-', dir=output.parent) as temp:
        temp = Path(temp)
        records = []
        for event in sorted(events, key=checked_key):
            package = store.package(event)
            filename = event.replace(':', '-') + '.json'
            (temp / filename).write_text(json.dumps(package, indent=2) + '\n')
            records.append({'event-id': event, 'file': filename, 'sha256': digest(temp / filename),
                            'evidence-sha256': package['evidence-sha256'], 'retrieval': package['retrieval']})
        report = {'format': 'powerspike-replay-evidence-batch', 'version': VERSION,
                  'store-identity': store.manifest['identity'], 'replay-sha256': store.manifest['replay-sha256'],
                  'records': records, 'model-admitted': 0, 'resolved-semantic-blockers': [],
                  'cost': {'wall-seconds': time.monotonic() - started, 'raw-replay-reads': 0,
                           'source-archive-reads': 0, 'native-decode-calls': 0},
                  'store-open': store.open_cost, 'limits': LIMITS}
        (temp / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
        temp.rename(output)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    create = commands.add_parser('build')
    for label in STREAMS:
        create.add_argument('--' + label, type=Path, required=True)
    create.add_argument('--output', type=Path, required=True)
    create.add_argument('--checkpoint-every', type=int, default=256)
    create.add_argument('--match', type=Path)
    create.add_argument('--timeline', type=Path)
    for command in ('batch', 'verify', 'candidates', 'history'):
        sub = commands.add_parser(command)
        sub.add_argument('--store', type=Path, required=True)
        if command == 'verify':
            sub.add_argument('--sources', action='store_true')
        else:
            sub.add_argument('--output', type=Path, required=True)
        if command == 'batch':
            sub.add_argument('--event', action='append', required=True)
        if command == 'history':
            sub.add_argument('--kind', choices=[k for s in STREAMS.values() for k in s], required=True)
            sub.add_argument('--before', required=True)
            sub.add_argument('--after')
            sub.add_argument('--entity', type=int)
    args = parser.parse_args()
    if args.command == 'build':
        report = build({k: getattr(args, k.replace('-', '_')) for k in STREAMS}, args.output,
                       args.checkpoint_every, args.match, args.timeline)
        print(encoded({k: report[k] for k in ('identity', 'counts', 'cost')}))
        return
    store = EvidenceStore(args.store, verify_sources=getattr(args, 'sources', False))
    try:
        if args.command == 'batch':
            report = batch(store, args.event, args.output)
            print(encoded({'cases': len(report['records']), 'cost': report['cost']}))
        elif args.command == 'verify':
            print(encoded({'verified': True, 'identity': store.manifest['identity'],
                           'sources-checked': args.sources}))
        else:
            rows = store.candidates() if args.command == 'candidates' else store.history(
                args.kind, args.before, args.entity, args.after)
            with args.output.open('x') as handle:
                handle.write(json.dumps(rows, indent=2) + '\n')
            print(encoded({'records': len(rows)}))
    finally:
        store.close()


if __name__ == '__main__':
    main()
