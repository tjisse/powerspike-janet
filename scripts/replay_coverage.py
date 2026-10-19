"""Append-only replay evidence ledger and reproducible coverage reports.

Raw cases stay under observations/local. Only the registry and aggregate report
need shipping. Hash chaining detects edits; it is not a signature or an oracle.
Imports never turn a provisional diagnostic into an admitted comparison.
"""
import argparse
from collections import Counter, defaultdict
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import gzip
import hashlib
import itertools
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile
import time

from replays import prepare_case

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_REGISTRY = ROOT / 'observations/verification/registry.json'
DEFAULT_LEDGER = ROOT / 'observations/local/verification/ledger.jsonl'
FAMILIES = ('isolated-damage', 'mitigation', 'timing', 'on-hit',
            'healing-shields', 'control', 'objectives', 'combinations')
LAYERS = ('stat-generation', 'conditional-damage', 'single-hit', 'sequence')


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False)


def identity(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def digest(path):
    with Path(path).open('rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


def load(path):
    def invalid(value):
        raise ValueError('Nonfinite JSON value: ' + value)
    return json.loads(Path(path).read_text(), parse_constant=invalid)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(value):
    return isinstance(value, str) and len(value) == 64 and all(c in '0123456789abcdef' for c in value)


def finite(value):
    return type(value) in (float, int) and math.isfinite(value)


def text(value):
    return isinstance(value, str) and bool(value.strip())


def registry_check(registry):
    require(registry.get('format') == 'powerspike-verification-registry' and registry.get('version') == 1,
            'Unsupported verification registry')
    require(len(registry['families']) == 8 and {f['id'] for f in registry['families']} == set(FAMILIES),
            'Registry must retain all eight distinct families')
    obligations = registry['obligations']
    require(len({o['id'] for o in obligations}) == len(obligations), 'Duplicate obligation')
    for row in obligations:
        require(row['family'] in (*FAMILIES, None) and row['layer'] in LAYERS, 'Unknown family/layer')
        require(row['scope'] in ('current', 'historical') and row['model-support'] in
                ('implemented', 'partial', 'unsupported'), 'Invalid scope/support')
        require(bool(row['required-evidence']), 'Obligation requires evidence gates')
        require(all(type(row['diversity'][k]) is int and row['diversity'][k] > 0
                    for k in ('games', 'encounters', 'actors')), 'Invalid diversity target')
    ids = {o['id'] for o in obligations}
    for interaction in registry['interactions']:
        require(set(interaction['requires-obligations']) <= ids, 'Unknown interaction obligation')
        require(bool(interaction['dimensions']) and all(interaction['dimensions'].values()), 'Empty interaction')
    return registry


def context_case_state(state, game):
    return identity([state.cases[key] for key in sorted(state.cases) if state.cases[key]['game'] == game])


class Ledger:
    def __init__(self):
        self.registry = None
        self.registry_hash = None
        self.games, self.cases, self.freezes = {}, {}, {}
        self.results, self.admissions, self.invalidated = [], [], set()
        self.diagnostics, self.costs = [], []
        self.context_reviews = {}
        self.annotations = {}
        self.estimates = {}
        self.imports = {}
        self.operations = {}
        self.head, self.length = '0' * 64, 0

    @classmethod
    def read(cls, path):
        state = cls()
        if not Path(path).exists():
            return state
        with Path(path).open() as handle:
            for line in handle:
                require(line.endswith('\n'), 'Truncated ledger record; preserve and repair explicitly')
                envelope = json.loads(line)
                unsigned = {k: v for k, v in envelope.items() if k != 'hash'}
                require(envelope['sequence'] == state.length + 1 and envelope['previous'] == state.head
                        and envelope['hash'] == identity(unsigned), 'Ledger chain integrity failure')
                state.apply(envelope['data'], envelope['hash'])
                state.head, state.length = envelope['hash'], envelope['sequence']
        return state

    def active_results(self):
        return [row for row in self.results if row['ledger-record'] not in self.invalidated]

    def active_admissions(self):
        return [row for row in self.admissions if row['ledger-record'] not in self.invalidated]

    def apply(self, data, record_hash):
        operation = data['operation']
        require(operation not in self.operations, 'Duplicate ledger operation')
        kind = data['kind']
        if kind == 'registry':
            if self.registry is not None and identity(data['registry']) != self.registry_hash:
                require(data['registry']['revision'] != self.registry['revision'], 'Bump catalogue revision when changing scope')
            self.registry = registry_check(data['registry'])
            self.registry_hash = identity(self.registry)
        else:
            require(self.registry is not None, 'Register the coverage catalogue first')
            if kind == 'freeze':
                require(sha(data['model']) and text(data['selection-policy']), 'Freeze requires model and selection policy')
                require(data['registry'] == self.registry_hash, 'Freeze registry mismatch')
                require(text(data['id']) and data['id'] not in self.freezes, 'Freeze identities are immutable')
                self.freezes[data['id']] = data
            elif kind == 'game':
                require(sha(data['id']) and text(data['build']), 'Invalid game identity')
                require(data['id'] not in self.games, 'Game already registered')
                require(data['role'] in ('development', 'audit'), 'Invalid game role')
                if data['role'] == 'audit':
                    require(data.get('freeze') in self.freezes and text(data.get('selection-receipt')),
                            'Reserve audit games after a freeze with a selection receipt')
                self.games[data['id']] = dict(data)
            elif kind == 'development':
                require(data['game'] in self.games and text(data['reason']), 'Unknown game or missing reason')
                self.games[data['game']]['role'] = 'development'
            elif kind == 'case':
                require(data['game'] in self.games, 'Register game before cases')
                require(data['id'] == data['game'] + ':' + data['event-id'], 'Case identity mismatch')
                require(data['id'] not in self.cases, 'Duplicate case identity')
                require(finite(data['recorded']) and data['recorded'] >= 0 and finite(data['timestamp']), 'Invalid measurement')
                require(set(data['obligations']) <= {o['id'] for o in self.registry['obligations']}, 'Unknown obligation')
                require(data['population'] == 'champion-to-champion', 'Unsupported case population')
                self.cases[data['id']] = data
            elif kind == 'case-import':
                require(data['game'] in self.games and sha(data['source'])
                        and data['cases'] == sum(c['game'] == data['game'] for c in self.cases.values()),
                        'Case import is incomplete or has duplicate records')
                self.imports[data['game']] = data
            elif kind == 'annotation':
                require(data['case'] in self.cases and sha(data['source']) and text(data['reason']),
                        'Annotation requires a case, evidence fingerprint and reason')
                changes = data['changes']
                require(bool(changes) and set(changes) <= {
                    'features', 'effect-kind', 'numeric-ready', 'obligations', 'blockers'},
                    'Annotations cannot rewrite packet measurements or identities')
                if 'obligations' in changes:
                    require(set(changes['obligations']) <= {o['id'] for o in self.registry['obligations']},
                            'Unknown annotation obligation')
                if 'features' in changes:
                    require(isinstance(changes['features'], dict) and
                            changes['features'].get('damage-type') == self.cases[data['case']]['features']['damage-type'],
                            'Annotations cannot rewrite decoded damage type')
                if 'numeric-ready' in changes:
                    require(type(changes['numeric-ready']) is bool, 'Numeric readiness must be explicit')
                if 'blockers' in changes:
                    require(isinstance(changes['blockers'], list) and all(text(b) for b in changes['blockers']),
                            'Invalid blocker annotation')
                if 'effect-kind' in changes:
                    require(changes['effect-kind'] in ('basic-attack-candidate', 'critical-attack-candidate',
                            'other-effect', 'unknown-effect', 'ambiguous-effect'), 'Unknown candidate classification')
                self.cases[data['case']] = {**self.cases[data['case']], **changes,
                                            'classification-revision': record_hash}
                self.annotations[data['case']] = {**data, 'ledger-record': record_hash}
                self.invalidated.update(r['ledger-record'] for r in self.results + self.admissions
                                        if r['case'] == data['case'])
            elif kind == 'admission':
                self.check_comparison(data)
                require(not any(self.result_key(r) == self.result_key(data) for r in self.active_admissions()),
                        'Review already admitted')
                self.admissions.append({**data, 'ledger-record': record_hash})
            elif kind == 'comparison':
                self.check_comparison(data)
                key = self.result_key(data)
                require(not any(self.result_key(r) == key for r in self.active_results()),
                        'Conflicting/repeated result; invalidate the old record explicitly')
                game = self.games[self.cases[data['case']]['game']]
                freeze = self.freezes.get(game.get('freeze'), {})
                fresh = (game['role'] == 'audit' and freeze.get('model') == data['model']
                         and freeze.get('registry') == data['registry'])
                self.results.append({**data, 'ledger-record': record_hash, 'fresh-game': fresh})
            elif kind == 'invalidate':
                require(any(r['ledger-record'] == data['record'] for r in self.results + self.admissions) and text(data['reason']),
                        'Unknown comparison or missing invalidation reason')
                self.invalidated.add(data['record'])
                for admission in self.admissions:
                    if admission['ledger-record'] == data['record']:
                        self.invalidated.update(r['ledger-record'] for r in self.results
                                                if self.result_key(r) == self.result_key(admission))
            elif kind == 'context-review':
                require(data['game'] in self.games and data.get('admitted') is False,
                        'Context reviews require a known game and cannot admit evidence')
                require(sha(data['source']) and data['build'] == self.games[data['game']]['build'],
                        'Context review identity/build mismatch')
                require(all(type(value) is int and value >= 0 for value in data['counts'].values()),
                        'Invalid context review counts')
                require(set(data['adapters']) == {'replay_attack_review.py', 'replay_actions.py', 'replay_state.py'}
                        and all(sha(value) for value in data['adapters'].values()), 'Context adapter receipts required')
                require(all(type(data[key]) is int and data[key] >= 0 for key in ('decoded-actions', 'decode-failures'))
                        and finite(data['search-window-seconds']) and 0 < data['search-window-seconds'] <= 10,
                        'Invalid context extraction counts or window')
                require(data.get('case-state') is None or data['case-state'] == context_case_state(self, data['game']),
                        'Context review case revision mismatch')
                self.context_reviews[data['game']] = data
            elif kind == 'diagnostic':
                require(data.get('admitted') is False, 'Diagnostics cannot admit cases')
                self.diagnostics.append(data)
            elif kind == 'cost':
                require(data['category'] in ('review', 'compute', 'maintenance'), 'Unknown cost category')
                require(data.get('lane', 'shared') in ('discovery', 'audit', 'shared'), 'Unknown review lane')
                require(all(finite(data.get(k, 0)) and data.get(k, 0) >= 0
                            for k in ('seconds', 'bytes', 'requests')), 'Invalid resource cost')
                require(text(data['label']), 'Label the measured work')
                self.costs.append(data)
            elif kind == 'work-estimate':
                require(data['blockers'] and all(text(b) for b in data['blockers'])
                        and finite(data['hours']) and data['hours'] > 0 and text(data['rationale']),
                        'Estimate requires blockers, positive hours and rationale')
                self.estimates[tuple(sorted(set(data['blockers'])))] = data
            else:
                raise ValueError('Unsupported ledger event: ' + kind)
        self.operations[operation] = identity(data)

    @staticmethod
    def result_key(row):
        return row['case'], row['model'], row['snapshot'], row['registry']

    def check_comparison(self, row):
        require(row['case'] in self.cases, 'Unknown comparison case')
        case = self.cases[row['case']]
        require(case['features'].get('damage-type') in ('physical', 'magic', 'true'),
                'Damage type must be independently decoded before admission')
        require(row['registry'] == self.registry_hash, 'Comparison registry mismatch')
        require(self.games[case['game']]['build'] == self.registry['client-build'], 'Comparison build mismatch')
        require(sha(row['model']) and sha(row['snapshot']), 'Exact model and snapshot hashes required')
        require(all(finite(row[k]) for k in ('observed', 'tolerance'))
                and row['tolerance'] >= 0 and row['observed'] == case['recorded'], 'Invalid or substituted observation')
        if row['kind'] == 'comparison':
            require(finite(row['predicted']) and row['status'] == (
                'consistent' if abs(row['predicted'] - row['observed']) <= row['tolerance'] else 'mismatch'),
                'Result status disagrees with values')
        require(set(case['blockers']) <= set(row['resolved-blockers']), 'Unresolved case blockers')
        require(text(row.get('encounter')), 'Reviewed encounter identity required')
        obligations = {o['id']: o for o in self.registry['obligations']}
        require(bool(row['obligations']) and set(row['obligations']) <= obligations.keys(), 'Unknown/empty obligations')
        for oid in row['obligations']:
            obligation = obligations[oid]
            require(obligation['layer'] == 'conditional-damage', 'Current comparator supports isolated damage only')
            require(obligation['scope'] == 'current' and obligation['model-support'] != 'unsupported', 'Unsupported obligation')
            require(all(text(row['evidence'].get(k)) for k in obligation['required-evidence']), 'Missing independent review evidence')
            if oid in ('ordinary-physical', 'positive-armor', 'critical-attacks'):
                require(case['features']['damage-type'] == 'physical', 'Physical obligation/type mismatch')
            if oid == 'ordinary-physical':
                require(case['effect-kind'] == 'basic-attack-candidate', 'Ordinary attack identity must be established')
            if oid == 'critical-attacks':
                require(case['effect-kind'] == 'critical-attack-candidate', 'Critical attack identity must be established')
            if oid == 'simple-magic':
                require(case['features']['damage-type'] == 'magic', 'Magic obligation/type mismatch')
            if oid in ('positive-armor', 'positive-mr'):
                require(case['features'].get('resistance-band') in ('low', 'medium', 'high'), 'Positive resistance required')
            if oid == 'positive-mr':
                require(case['features']['damage-type'] == 'magic', 'Magic resistance/type mismatch')
            if oid == 'negative-resistance':
                require(case['features'].get('resistance-band') in ('negative', 'zero'), 'Boundary resistance required')
            if oid in ('negative-resistance', 'penetration', 'resistance-reduction'):
                require(case['features']['damage-type'] in ('physical', 'magic'), 'Resistance obligations do not apply to true damage')
            if oid == 'true-damage':
                require(case['features']['damage-type'] == 'true', 'True damage obligation/type mismatch')
        for feature, value in case['features'].items():
            if feature in row['conditions']:
                require(row['conditions'][feature] == value, 'Reviewed condition contradicts archived state')


@contextmanager
def locked(path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with Path(str(path) + '.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def append(path, events):
    """Validate the whole transaction before writing; retries are idempotent."""
    path = Path(path)
    with locked(path):
        state = Ledger.read(path)
        encoded = []
        for data in events:
            operation = data['operation']
            if operation in state.operations:
                require(state.operations[operation] == identity(data), 'Operation retry changed its content')
                continue
            unsigned = {'sequence': state.length + 1, 'previous': state.head,
                        'recorded-at': datetime.now(timezone.utc).isoformat(), 'data': data}
            record_hash = identity(unsigned)
            state.apply(data, record_hash)
            encoded.append(canonical({**unsigned, 'hash': record_hash}) + '\n')
            state.head, state.length = record_hash, unsigned['sequence']
        if encoded:
            with path.open('a') as handle:
                handle.writelines(encoded)
                handle.flush()
                os.fsync(handle.fileno())
        return len(encoded)


def event(kind, **values):
    data = {'kind': kind, **values}
    return {**data, 'operation': identity(data)}


def band(value):
    if value < 0:
        return 'negative'
    if value == 0:
        return 'zero'
    return 'low' if value <= 50 else 'medium' if value <= 100 else 'high'


def import_audit(folder, ledger, frozen_audit=False):
    folder = Path(folder)
    summary = load(folder / 'summary.json')
    require(summary.get('format') == 'powerspike-replay-gap-audit', 'Expected native gap audit')
    archive = folder / 'cases.jsonl.gz'
    require(digest(archive) == summary['evidence-files']['cases.jsonl.gz'], 'Case archive receipt mismatch')
    # Unreserved post-hoc imports are development data. A frozen audit needs
    # prior registration; the tool cannot infer unlogged human inspection.
    state = Ledger.read(ledger)
    require(state.registry is not None, 'Initialize registry first')
    game_id = summary['replay-sha256']
    events = []
    if game_id not in state.games:
        events.append(event('game', id=game_id, build=summary['client-build'], role='development',
                            source=digest(folder / 'summary.json')))
    elif state.games[game_id]['role'] == 'audit':
        require(frozen_audit and state.freezes[state.games[game_id]['freeze']]['registry'] == state.registry_hash,
                'Reserved audit import requires --frozen-audit and its unchanged preregistered catalogue')
    require(not frozen_audit or game_id in state.games and state.games[game_id]['role'] == 'audit',
            'Reserve a new game after freezing before using --frozen-audit')
    # Resolve roster through the source extraction identified by the gap receipt.
    extraction = None
    for candidate in folder.parent.glob('*/summary.json'):
        if digest(candidate) == summary['source-files']['summary.json']:
            extraction = load(candidate)
            break
    require(extraction is not None, 'Matching source extraction/roster receipt unavailable')
    roster = {extraction['champion-entity-start'] + p['slot']: p['champion'] for p in extraction['roster']}
    count = 0
    with gzip.open(archive, 'rt') as handle:
        for line in handle:
            row = json.loads(line)
            require(row['replay-sha256'] == game_id, 'Mixed replay case archive')
            source, target = row['source'], row['target']
            features = {'damage-type': row['damage-type']}
            resistance_key = 'armor' if row['damage-type'] == 'physical' else 'magic-resist'
            if row['damage-type'] != 'true' and resistance_key in row['target-observed']:
                features['resistance-band'] = band(row['target-observed'][resistance_key]['value'])
                if row['damage-type'] == 'physical':
                    features['armor-band'] = features['resistance-band']
            obligations = []
            if row['effect-kind'] == 'basic-attack-candidate' and row['damage-type'] == 'physical':
                obligations = ['ordinary-physical']
                if features.get('resistance-band') in ('low', 'medium', 'high'):
                    obligations.append('positive-armor')
            elif row['effect-kind'] == 'critical-attack-candidate' and row['damage-type'] == 'physical':
                obligations = ['critical-attacks']
            elif row['candidate-names'] and row['damage-type'] in ('magic', 'true'):
                obligations = ['simple-magic' if row['damage-type'] == 'magic' else 'true-damage']
            events.append(event('case', id=game_id + ':' + row['event-id'], game=game_id,
                                population='champion-to-champion', **{'event-id': row['event-id']},
                                timestamp=row['timestamp'], recorded=row['recorded-amount'],
                                actor=roster[source], target=roster[target], features=features,
                                **{'effect-kind': row['effect-kind'], 'numeric-ready': not row['data-gaps']},
                                blockers=sorted(set(row['data-gaps'] + row['semantic-gaps'])),
                                obligations=obligations, source=summary['evidence-files']['cases.jsonl.gz']))
            count += 1
    require(count == summary['counts']['champion-to-champion-events'], 'Incomplete case archive')
    events.append(event('case-import', game=game_id, source=summary['evidence-files']['cases.jsonl.gz'], cases=count))
    return append(ledger, events)


def import_context(path, ledger):
    report = load(path)
    require(report.get('format') == 'powerspike-replay-context-study', 'Expected context study')
    require(report['coverage']['admitted-damage-cases'] == 0, 'Use reviewed comparison import for admission')
    return append(ledger, [event('diagnostic', source=digest(path), admitted=False,
                                 build=report['replays'][0]['client-build'],
                                 games=[r['replay-sha256'] for r in report['replays']],
                                 **{'stat-game': report['replay-sha256']},
                                 **{'stat-checks': report['stat-checks'],
                                    'damage-check': report['conditional-damage-check'],
                                    'model-components': report['model'],
                                    'resources': report['resource-cost'],
                                    'buff-records': report['coverage']['buff-records']})])


def import_attack_review(folder, ledger):
    from replay_attack_review import archive
    from replay_actions import candidates
    folder = Path(folder)
    report = load(folder / 'summary.json')
    require(report.get('format') == 'powerspike-replay-attack-review' and report.get('version') == 1,
            'Expected attack context dossier')
    require(report['model-admissible-cases'] == 0 and report['resolved-semantic-blockers'] == [],
            'Context analysis cannot discharge semantic review or admit comparisons')
    state = Ledger.read(ledger)
    game = report['replay-sha256']
    require(game in state.games, 'Import the source game/cases first')
    for name, expected in report['evidence-files'].items():
        require(Path(name).name == name and digest(folder / name) == expected, 'Context evidence receipt mismatch')
    counts = Counter()
    for row in archive(folder / 'attack-context.jsonl.gz'):
        case = state.cases.get(game + ':' + row['event-id'])
        require(case is not None and row['timestamp'] == case['timestamp'], 'Unknown or rebound context case')
        require(case['effect-kind'] == 'basic-attack-candidate' and case['features']['damage-type'] == 'physical',
                'Context case outside ordinary physical candidate scope')
        require(row['model-admissible'] is False and row['resolved-semantic-blockers'] == [],
                'Context analysis is not admission')
        found = row['action-candidates']
        require(candidates(row, found, report['candidate-search-window-seconds']) == found,
                'Context contains noncausal or differently targeted action candidates')
        status = 'no-candidate' if not found else 'unique-candidate' if len(found) == 1 else 'ambiguous'
        require(row['status'] == status, 'Action candidate count/status mismatch')
        counts['ordinary-candidates'] += 1
        counts[status] += 1
        if case['numeric-ready']:
            counts['numeric-ready'] += 1
            counts['numeric-ready:' + status] += 1
        if len(found) == 1:
            stable = row['stat-continuity']['observed-stable']
            require(type(stable) is bool and row['stat-continuity']['server-sampling-resolved'] is False,
                    'Observed continuity does not prove server sampling')
            counts['observed-stable'] += stable
            if case['numeric-ready']: counts['numeric-ready:observed-stable'] += stable
    require(dict(counts) == report['counts'], 'Incomplete or inconsistent context archive')
    return append(ledger, [event('context-review', game=game, source=digest(folder / 'summary.json'),
        build=report['client-build'], admitted=False, counts=dict(counts), adapters=report['adapters'],
        **{'case-state': context_case_state(state, game)},
        **{'decoded-actions': report['action-packets-decoded'], 'decode-failures': report['action-failures'],
           'search-window-seconds': report['candidate-search-window-seconds']})])


def import_comparison(report_path, events_path, reviews_path, ledger):
    report, exported, reviews = load(report_path), load(events_path), load(reviews_path)
    require(report.get('format') == 'powerspike-replay-comparison' and report.get('version') == 1,
            'Expected production replay comparison report')
    require(report.get('adapter-sha256') == digest(ROOT / 'scripts/replays.py'),
            'Use a report from the current reviewed-hit comparator')
    require(report['events-sha256'] == digest(events_path) and report['reviews-sha256'] == digest(reviews_path),
            'Comparison input fingerprints mismatch')
    observations = {r['event-id']: r for r in exported['events']}
    review_map = {r['event-id']: r for r in reviews['cases']}
    require(len(observations) == len(exported['events']) and len(review_map) == len(reviews['cases']), 'Duplicate input IDs')
    require(len({r['event-id'] for r in report['rows']}) == len(report['rows']), 'Duplicate comparison rows')
    state = Ledger.read(ledger)
    additions = []
    for row in report['rows']:
        if not row.get('checked'):
            continue
        original, review = observations[row['event-id']], review_map[row['event-id']]
        require(prepare_case(original, review) is None, 'Comparison is not independently reviewed')
        case_id = original['replay-sha256'] + ':' + row['event-id']
        require(case_id in state.cases and row['replay-sha256'] == original['replay-sha256']
                and row['client-build'] == original['client-build'], 'Comparison identity mismatch')
        archived = state.cases[case_id]
        require(original['client-build'] == state.games[archived['game']]['build']
                and original['fields']['damageType'] == archived['features']['damage-type'],
                'Event build/type differs from archived packet')
        scenario = review['scenario-document']['scenario']
        require(row['model'] == scenario['model'] and row['snapshot'] == scenario['snapshot']
                and row['patch'] == scenario['patch'] and row['tolerance'] == review['tolerance'], 'Scenario identity/tolerance mismatch')
        require(row['observed'] == original['fields']['damageAmount'], 'Substituted packet observation')
        verification = review.get('verification', {})
        data = event('comparison', case=case_id, registry=verification.get('registry'),
                     model=row['model'], snapshot=row['snapshot'], observed=row['observed'],
                     predicted=row['predicted'], tolerance=row['tolerance'], status=row['status'],
                     obligations=verification.get('obligations', []),
                     evidence={**review['evidence'], 'independent-oracle': verification.get('independent-oracle')},
                     **{'resolved-blockers': verification.get('resolved-blockers', [])},
                     encounter=verification.get('encounter'), conditions=verification.get('conditions', {}),
                     source=digest(report_path))
        state.check_comparison(data)
        same = [r for r in state.active_results() if state.result_key(r) == state.result_key(data)]
        if same:
            require(all(same[0][k] == data[k] for k in ('observed', 'predicted', 'tolerance', 'status', 'obligations')),
                    'Changed result requires explicit invalidation')
        else:
            additions.append(data)
    return append(ledger, additions)


def import_reviews(events_path, reviews_path, ledger):
    exported, reviews = load(events_path), load(reviews_path)
    require(exported.get('format') == 'powerspike-replay-events' and reviews.get('format') == 'powerspike-replay-reviews',
            'Expected replay events and reviews')
    observations = {r['event-id']: r for r in exported['events']}
    require(len(observations) == len(exported['events']) and
            len({r['event-id'] for r in reviews['cases']}) == len(reviews['cases']), 'Duplicate review/input ID')
    state = Ledger.read(ledger)
    additions = []
    for review in reviews['cases']:
        original = observations.get(review['event-id'])
        require(original is not None and prepare_case(original, review) is None, 'Unreviewed or invalid admission')
        spec, verification = review['scenario-document']['scenario'], review.get('verification', {})
        data = event('admission', case=original['replay-sha256'] + ':' + original['event-id'],
                     registry=verification.get('registry'), model=spec.get('model'), snapshot=spec.get('snapshot'),
                     observed=original['fields']['damageAmount'], tolerance=review['tolerance'],
                     obligations=verification.get('obligations', []),
                     evidence={**review['evidence'], 'independent-oracle': verification.get('independent-oracle')},
                     **{'resolved-blockers': verification.get('resolved-blockers', [])},
                     encounter=verification.get('encounter'), conditions=verification.get('conditions', {}),
                     source=digest(reviews_path))
        require(data['case'] in state.cases and original['client-build'] ==
                state.games[state.cases[data['case']]['game']]['build'] and
                original['fields']['damageType'] == state.cases[data['case']]['features']['damage-type'],
                'Review build/type differs from archived packet')
        state.check_comparison(data)
        if not any(state.result_key(r) == state.result_key(data) for r in state.active_admissions()):
            additions.append(data)
    return append(ledger, additions)


def model_identity():
    env = {**os.environ, 'JANET_PATH': str(ROOT / 'build/web-modules')}
    run = subprocess.run([str(ROOT / 'build/janet'), '-e',
                          '(import ./src/powerspike/engine :as e) (print e/identity)'],
                         cwd=ROOT, env=env, text=True, capture_output=True, check=True, timeout=30)
    value = run.stdout.strip()
    require(sha(value), 'Could not determine production model identity; supply --model')
    return value


def coverage_report(state, model):
    require(state.registry is not None and sha(model), 'Registry and model identity required')
    context_reviews = [row for row in state.context_reviews.values()
                       if row['build'] == state.registry['client-build']
                       and row.get('case-state') == context_case_state(state, row['game'])
                       and all((ROOT / 'scripts' / name).is_file() and digest(ROOT / 'scripts' / name) == value
                               for name, value in row['adapters'].items())]
    context_counts = Counter()
    for row in context_reviews: context_counts.update(row['counts'])
    registry = state.registry
    cases = [c for c in state.cases.values() if state.games[c['game']]['build'] == registry['client-build']]
    case_ids = {c['id'] for c in cases}
    imported_games = {c['game'] for c in cases if c.get('source')}
    require(all(g in state.imports and state.imports[g]['cases'] == sum(c['game'] == g for c in cases)
                for g in imported_games), 'Incomplete ledger import; retry the source audit before reporting')
    results = [r for r in state.active_results() if r['model'] == model
               and r['registry'] == state.registry_hash and r['case'] in case_ids]
    admissions = [r for r in state.active_admissions() if r['model'] == model
                  and r['registry'] == state.registry_hash and r['case'] in case_ids]
    admitted_cases = {r['case'] for r in results + admissions}
    diagnostic = [d for d in state.diagnostics if d['build'] == registry['client-build']]
    latest_diagnostic = diagnostic[-1] if diagnostic else None
    rows = []
    for obligation in registry['obligations']:
        selected = [r for r in results if obligation['id'] in r['obligations']]
        candidates = [c for c in cases if obligation['id'] in c['obligations']]
        games = {state.cases[r['case']]['game'] for r in selected}
        actors = {state.cases[r['case']]['actor'] for r in selected}
        encounters = {(state.cases[r['case']]['game'], r['encounter']) for r in selected}
        conditions = {key: sorted({r['conditions'][key] for r in selected if key in r['conditions']})
                      for key in obligation['diversity']['conditions']}
        target = obligation['diversity']
        varied = (len(games) >= target['games'] and len(actors) >= target['actors']
                  and len(encounters) >= target['encounters']
                  and all(set(values) <= set(conditions[key]) for key, values in target['conditions'].items()))
        admitted = {r['case'] for r in results + admissions if obligation['id'] in r['obligations']}
        provisional = latest_diagnostic['stat-checks'] if latest_diagnostic and obligation['id'] == 'flat-loadout-stats' else []
        provisional_snapshots = len({row['timestamp'] for row in provisional})
        stage = ('fresh-game checked' if varied and any(r['fresh-game'] for r in selected)
                 else 'varied' if varied else 'checked' if selected else 'admitted, pending' if admitted
                 else 'observed, blocked' if candidates else 'observed, provisional' if provisional else 'unseen')
        rows.append({**obligation, 'stage': stage, 'candidates': len(candidates) + provisional_snapshots,
                     'candidate-unit': 'stat snapshots' if obligation['layer'] == 'stat-generation' else 'damage events',
                     'provisional-field-checks': len(provisional),
                     'admitted': len(admitted), 'checked': len(selected), 'mismatches': sum(r['status'] == 'mismatch' for r in selected),
                     'games': len(games), 'actors': len(actors), 'encounters': len(encounters),
                     'conditions-seen': conditions, 'fresh-game-comparisons': sum(r['fresh-game'] for r in selected)})
    families = []
    for family in registry['families']:
        group = [r for r in rows if r['family'] == family['id'] and r['scope'] == 'current']
        families.append({**family, 'total': len(group), 'checked': sum(r['checked'] > 0 for r in group),
                         'blocked': sum(r['stage'] == 'observed, blocked' for r in group),
                         'varied': sum(r['stage'] in ('varied', 'fresh-game checked') for r in group),
                         'fresh': sum(r['stage'] == 'fresh-game checked' for r in group),
                         'open-mismatches': sum(r['mismatches'] for r in group)})
    combat = [r for r in rows if r['family'] and r['scope'] == 'current']
    implemented = [r for r in combat if r['model-support'] == 'implemented']
    fractions = [f['checked'] / f['total'] if f['total'] else 0 for f in families]
    interactions = []
    for interaction in registry['interactions']:
        keys = list(interaction['dimensions'])
        covered = {tuple(r['conditions'].get(key) for key in keys) for r in results
                   if set(r['obligations']) & set(interaction['requires-obligations'])}
        cells = [{'values': dict(zip(keys, values)), 'checked': tuple(values) in covered}
                 for values in itertools.product(*(interaction['dimensions'][key] for key in keys))]
        interactions.append({**interaction, 'cells': cells, 'total': len(cells), 'checked': sum(c['checked'] for c in cells)})
    # AND dependencies: a complete blocker bundle, not each blocker in isolation.
    bundles = defaultdict(list)
    for case in cases:
        if case['obligations'] and case['id'] not in admitted_cases:
            bundles[tuple(case['blockers'])].append(case)
    unlocks = []
    for blockers, group in bundles.items():
        ids = {o for c in group for o in c['obligations']}
        estimate = state.estimates.get(blockers)
        new = [r for r in rows if r['id'] in ids and r['checked'] == 0]
        family_ids = {r['family'] for r in new if r['family']}
        floor = min((f['checked'] / f['total'] for f in families if f['id'] in family_ids), default=1)
        primary = any(c['effect-kind'] == 'basic-attack-candidate' and c['numeric-ready'] for c in group)
        unlocks.append({'blockers': list(blockers), 'candidates': len(group),
                        'games': len({c['game'] for c in group}),
                        'obligations': sorted(ids), 'new-obligations': len(new), 'family-floor': floor,
                        'bootstrap-ready': primary,
                        'estimated-review-hours': estimate['hours'] if estimate else None,
                        'estimated-obligations-per-hour': len(new) / estimate['hours'] if estimate else None,
                        'note': 'Potential review candidates only; every listed blocker must be discharged. Counts are not additive across overlapping work.'})
    counts = Counter(c['effect-kind'] for c in cases)
    basic = [c for c in cases if c['effect-kind'] == 'basic-attack-candidate']
    checked_cases = {r['case'] for r in results}
    current_games = [g for g in state.games.values() if g['build'] == registry['client-build']]
    costs = {category: sum(r['seconds'] for r in state.costs if r['category'] == category and 'seconds' in r)
             if any(r['category'] == category and 'seconds' in r for r in state.costs) else None
             for category in ('review', 'compute', 'maintenance')}
    review_lanes = {lane: sum(r.get('seconds', 0) for r in state.costs if r['category'] == 'review'
                              and r.get('lane', 'shared') == lane) for lane in ('discovery', 'audit', 'shared')}
    allocated_review = review_lanes['audit'] + review_lanes['discovery']
    errors = [abs(r['predicted'] - r['observed']) for r in results]
    ordinary = [r for r in results if 'ordinary-physical' in r['obligations']]
    champion_slices = []
    for champion in sorted({c['actor'] for c in cases}):
        source_cases = [c for c in cases if c['actor'] == champion]
        source_results = [r for r in results if state.cases[r['case']]['actor'] == champion]
        champion_slices.append({'champion': champion, 'observed-events': len(source_cases),
                               'games': len({c['game'] for c in source_cases}),
                               'checked': len(source_results),
                               'mismatches': sum(r['status'] == 'mismatch' for r in source_results)})
    report = {'format': 'powerspike-verification-progress', 'version': 1,
              'generated-at': datetime.now(timezone.utc).isoformat(),
              'registry': state.registry_hash, 'registry-revision': registry['revision'],
              'reporter-sha256': digest(__file__),
              'model': model, 'client-build': registry['client-build'], 'patch': registry['patch'],
              'ledger': {'head': state.head, 'records': state.length},
              'scope': registry['scope-note'],
              'pipeline': {'games': len(current_games), 'events': len(cases), 'ordinary-candidates': len(basic),
                           'numeric-ready': sum(c['numeric-ready'] for c in basic),
                           'admitted': len(admitted_cases), 'evaluated': len(checked_cases),
                           'unknown-effects': counts['unknown-effect']},
              'pending-evaluations': len(admitted_cases - checked_cases),
              'coverage': {'combat-checked': sum(r['checked'] > 0 for r in combat), 'combat-total': len(combat),
                           'implemented-checked': sum(r['checked'] > 0 for r in implemented),
                           'implemented-total': len(implemented),
                           'balanced-fraction': sum(fractions) / len(fractions), 'minimum-family-fraction': min(fractions),
                           'replay-reach': len(admitted_cases) / len(cases) if cases else None,
                           'evaluated-reach': len(checked_cases) / len(cases) if cases else None,
                           'overall-league-coverage': None},
              'agreement': {'checked': len(results), 'consistent': sum(r['status'] == 'consistent' for r in results),
                            'mismatches': sum(r['status'] == 'mismatch' for r in results),
                            'fraction': sum(r['status'] == 'consistent' for r in results) / len(results) if results else None,
                            'max-absolute-error': max(errors) if errors else None,
                            'confidence': None, 'note': 'No independent-trial confidence inferred from correlated replay hits.'},
              'diagnostics': {'stat-checks': len(latest_diagnostic['stat-checks']) if latest_diagnostic else 0,
                              'attack-context': {'games': len(context_reviews),
                                  'decoded-actions': sum(r['decoded-actions'] for r in context_reviews),
                                  'decode-failures': sum(r['decode-failures'] for r in context_reviews),
                                  'counts': dict(context_counts),
                                  'note': 'Provisional action associations and client stat continuity; no semantic blocker or admission credit.'},
                              'stat-mismatches': sum(not r['consistent'] for r in latest_diagnostic['stat-checks']) if latest_diagnostic else 0,
                              'damage-checks': 1 if latest_diagnostic else 0,
                              'source': latest_diagnostic['source'] if latest_diagnostic else None,
                              'components-current': all(digest(ROOT / 'src/powerspike' / name) == value
                                 for name, value in latest_diagnostic['model-components'].items()) if latest_diagnostic else False,
                              'note': 'Latest conditional study, not additive reruns and not admitted evidence.'},
              'audit': {'reserved-games': sum(g['role'] == 'audit' for g in current_games),
                        'fresh-evaluated-games': len({state.cases[r['case']]['game'] for r in results if r['fresh-game']}),
                        'representative-reach': None},
              'bootstrap': {'target': registry['bootstrap'], 'checked-attacks': len(ordinary),
                            'games': len({state.cases[r['case']]['game'] for r in ordinary}),
                            'source-champions': len({state.cases[r['case']]['actor'] for r in ordinary}),
                            'armor-bands': len({r['conditions'].get('armor-band') for r in ordinary
                                                if r['conditions'].get('armor-band') in ('low', 'medium', 'high')})},
              'slices': {'source-champions': champion_slices,
                         'damage-types': dict(Counter(c['features']['damage-type'] for c in cases)),
                         'items-and-runes': None,
                         'note': 'Observed champion counts do not establish champion-wide verification. Item/rune slices await sufficient reconstructed context.'},
              'history': {'comparisons': len(state.results), 'admissions': len(state.admissions), 'invalidated': len(state.invalidated),
                          'all-revision-mismatches': sum(r['status'] == 'mismatch' for r in state.results),
                          'outside-current-view': len(state.active_results()) - len(results)},
              'families': families, 'obligations': rows, 'interactions': interactions,
              'next-unlocks': sorted(unlocks, key=lambda r: (
                  r['family-floor'], not r['bootstrap-ready'],
                  -(r['estimated-obligations-per-hour'] or 0), -r['new-obligations'], -r['candidates'], r['blockers']))[:10],
              'resources': {'recorded-seconds': costs,
                            'review-seconds-by-lane': review_lanes,
                            'audit-review-fraction': review_lanes['audit'] / allocated_review if allocated_review else None,
                            'audit-review-target': registry['selection-policy']['audit-effort-fraction'],
                            'recorded-bytes': sum(r.get('bytes', 0) for r in state.costs),
                            'recorded-requests': sum(r.get('requests', 0) for r in state.costs),
                            'review-seconds-per-admitted-case': costs['review'] / len(checked_cases)
                            if costs['review'] is not None and checked_cases else None,
                            'setup-research': latest_diagnostic.get('resources') if latest_diagnostic else None}}
    return report


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile('w', dir=path.parent, delete=False) as handle:
        temp = Path(handle.name)
        json.dump(value, handle, indent=2, allow_nan=False)
        handle.write('\n')
    os.replace(temp, path)


def export_review(state, case_id, directory):
    case = state.cases[case_id]
    game = state.games[case['game']]
    directory = Path(directory)
    require(not directory.exists(), 'Choose a fresh review directory')
    directory.mkdir(parents=True)
    observation = {'event-id': case['event-id'], 'replay-sha256': case['game'], 'client-build': game['build'],
                   'timestamp': case['timestamp'], 'source-champion': case['actor'], 'target-champion': case['target'],
                   'case-source-sha256': case.get('source'),
                   'fields': {'damageAmount': case['recorded'], 'damageType': case['features']['damage-type']}}
    atomic_json(directory / 'events.json', {'format': 'powerspike-replay-events', 'version': 1, 'events': [observation]})
    atomic_json(directory / 'reviews.json', {'format': 'powerspike-replay-reviews', 'version': 1,
                'human-review-seconds': None, 'cases': [{'event-id': case['event-id'], 'replay-sha256': case['game'],
                'client-build': game['build'], 'reviewed': False, 'mechanic': None, 'required-source': None,
                'tolerance': None, 'scenario-document': None,
                'evidence': {key: None for key in ('packet-semantics', 'pre-hit-state', 'actions', 'patch-data')},
                'verification': {'registry': state.registry_hash, 'obligations': case['obligations'],
                    'encounter': None, 'independent-oracle': None, 'conditions': case['features'],
                    'resolved-blockers': [], 'remaining-blockers': case['blockers']}}]})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ledger', type=Path, default=DEFAULT_LEDGER)
    sub = parser.add_subparsers(dest='command', required=True)
    init = sub.add_parser('init'); init.add_argument('--registry', type=Path, default=DEFAULT_REGISTRY)
    audit = sub.add_parser('import-audit'); audit.add_argument('folder', type=Path); audit.add_argument('--frozen-audit', action='store_true')
    context = sub.add_parser('import-context'); context.add_argument('report', type=Path)
    attack_context = sub.add_parser('import-attack-review'); attack_context.add_argument('folder', type=Path)
    compare = sub.add_parser('import-comparison')
    for key in ('report', 'events', 'reviews'): compare.add_argument('--' + key, type=Path, required=True)
    review = sub.add_parser('import-reviews')
    for key in ('events', 'reviews'): review.add_argument('--' + key, type=Path, required=True)
    report = sub.add_parser('report'); report.add_argument('--model'); report.add_argument('--output', type=Path, required=True)
    export = sub.add_parser('export-review'); export.add_argument('--case', required=True); export.add_argument('--directory', type=Path, required=True)
    freeze = sub.add_parser('freeze'); freeze.add_argument('--id', required=True); freeze.add_argument('--model'); freeze.add_argument('--selection-policy', required=True)
    reserve = sub.add_parser('reserve-game'); reserve.add_argument('--replay-sha256', required=True); reserve.add_argument('--freeze', required=True); reserve.add_argument('--selection-receipt', required=True)
    develop = sub.add_parser('mark-development'); develop.add_argument('--game', required=True); develop.add_argument('--reason', required=True)
    invalidate = sub.add_parser('invalidate'); invalidate.add_argument('--record', required=True); invalidate.add_argument('--reason', required=True)
    annotation = sub.add_parser('annotate'); annotation.add_argument('--case', required=True); annotation.add_argument('--file', type=Path, required=True)
    cost = sub.add_parser('cost'); cost.add_argument('--category', choices=['review', 'compute', 'maintenance'], required=True); cost.add_argument('--label', required=True); cost.add_argument('--seconds', type=float, required=True); cost.add_argument('--bytes', type=int, default=0); cost.add_argument('--requests', type=int, default=0)
    cost.add_argument('--lane', choices=['discovery', 'audit', 'shared'], default='shared')
    estimate = sub.add_parser('estimate-work'); estimate.add_argument('--blockers', nargs='+', required=True); estimate.add_argument('--hours', type=float, required=True); estimate.add_argument('--rationale', required=True)
    args = parser.parse_args()
    ledger, command = args.ledger, args.command
    started = time.monotonic()
    if command == 'init':
        count = append(ledger, [event('registry', registry=registry_check(load(args.registry)))])
    elif command == 'import-audit': count = import_audit(args.folder, ledger, args.frozen_audit)
    elif command == 'import-context': count = import_context(args.report, ledger)
    elif command == 'import-attack-review': count = import_attack_review(args.folder, ledger)
    elif command == 'import-comparison': count = import_comparison(args.report, args.events, args.reviews, ledger)
    elif command == 'import-reviews': count = import_reviews(args.events, args.reviews, ledger)
    else:
        state = Ledger.read(ledger)
        if command == 'report':
            result = coverage_report(state, args.model or model_identity())
            if args.output.exists():
                previous = load(args.output)
                if all(previous.get(k) == result[k] for k in ('registry', 'model', 'ledger', 'reporter-sha256')):
                    print(json.dumps({'unchanged': True, 'pipeline': previous['pipeline']})); return
                result['previous-report'] = {'sha256': digest(args.output), 'registry': previous.get('registry'),
                    'model': previous.get('model'), 'generated-at': previous.get('generated-at'),
                    'pipeline': previous.get('pipeline'), 'coverage': previous.get('coverage'),
                    'scope-changed': previous.get('registry') != result['registry'],
                    'model-changed': previous.get('model') != result['model']}
                if not result['previous-report']['scope-changed'] and not result['previous-report']['model-changed']:
                    result['previous-report']['delta'] = {
                        'evaluated-cases': result['pipeline']['evaluated'] - previous['pipeline']['evaluated'],
                        'checked-conditions': result['coverage']['combat-checked'] - previous['coverage']['combat-checked']}
                history = args.output.parent / 'history' / (digest(args.output) + '.json')
                if not history.exists(): atomic_json(history, previous)
            atomic_json(args.output, result)
            print(json.dumps({'pipeline': result['pipeline'], 'coverage': result['coverage']})); return
        if command == 'export-review': export_review(state, args.case, args.directory); return
        if command == 'freeze': data = event('freeze', id=args.id, model=args.model or model_identity(), registry=state.registry_hash, **{'selection-policy': args.selection_policy})
        elif command == 'reserve-game': data = event('game', id=args.replay_sha256, build=state.registry['client-build'], role='audit', freeze=args.freeze, **{'selection-receipt': args.selection_receipt})
        elif command == 'mark-development': data = event('development', game=args.game, reason=args.reason)
        elif command == 'invalidate': data = event('invalidate', record=args.record, reason=args.reason)
        elif command == 'annotate':
            annotation = load(args.file)
            data = event('annotation', case=args.case, changes=annotation['changes'], reason=annotation['reason'], source=digest(args.file))
        elif command == 'cost': data = event('cost', category=args.category, label=args.label, seconds=args.seconds, bytes=args.bytes, requests=args.requests, lane=args.lane, recorded_at=datetime.now(timezone.utc).isoformat())
        elif command == 'estimate-work': data = event('work-estimate', blockers=sorted(set(args.blockers)), hours=args.hours, rationale=args.rationale)
        count = append(ledger, [data])
    if command in ('import-audit', 'import-context', 'import-attack-review', 'import-reviews', 'import-comparison') and count:
        count += append(ledger, [event('cost', category='compute', label=command,
                                      seconds=time.monotonic() - started,
                                      recorded_at=datetime.now(timezone.utc).isoformat())])
    print(json.dumps({'appended-records': count}))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error))
