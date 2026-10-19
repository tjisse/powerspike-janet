"""Replay checkpoints must preserve causal state and unknowns without archive reads."""
import copy
import gzip
import heapq
import json
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import replay_evidence as evidence
from replay_recovery import digest
from replay_state import ObservedState


def event(offset, timestamp=1, **values):
    return {'event-id': f'gameChunk:3:{offset}', 'timestamp': timestamp, **values}


def record(entity, groups):
    data = struct.pack('<BI', sum(groups), entity)
    for group, values in sorted(groups.items()):
        mask = sum(1 << bit for bit in values)
        body = b''.join(value if isinstance(value, bytes) else struct.pack('<f', value)
                        for bit, value in sorted(values.items()))
        data += struct.pack('<IB', mask, len(body)) + body
    return data


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.folders = {label: self.root / label for label in evidence.STREAMS}
        for folder in self.folders.values():
            folder.mkdir()
        self.identity = {'replay-sha256': 'a' * 64, 'client-build': evidence.BUILD,
                         'protocol-digest': evidence.PROTOCOL}
        self.common = {**self.identity, 'image-sha256': 'b' * 64, 'profile-sha256': 'c' * 64}
        initial = record(100, {4: {3: 68., 6: 0., 7: 36., 12: 10., 13: 0., 23: 0., 24: 1.},
                               8: {0: 1., 4: 0., 19: 0., 20: 0.}, 32: {15: 2., 16: 4.}})
        initial += record(101, {4: {7: 44.}, 32: {0: 775.}})
        self.states = [event(2, 0, **{'decoded-buffer-hex': initial.hex()}),
                       event(6, **{'decoded-buffer-hex': record(101, {4: {7: 70.}, 32: {0: 720.}}).hex()}),
                       event(8, 2, **{'decoded-buffer-hex': record(100, {32: {10: b'\x01', 15: 3.}}).hex()}),
                       event(10, 3, **{'decoded-buffer-hex': record(100, {4: {3: 70.}}).hex()}),
                       event(13, 3, **{'decoded-buffer-hex': record(101, {32: {0: 650.}}).hex()}),
                       event(14, 4, **{'decoded-buffer-hex': record(100, {32: {15: 0., 16: 4.}}).hex()})]
        self.actions = [event(i, t, source=100, target=101, kind='basic-attack-announcement-candidate')
                        for i, t in [(3, 1), (9, 3), (15, 4)]]
        self.buffs = [event(1, 0, entity=101, kind='add', **{'name-hash': 99, 'slot-token': 2, 'duration-seconds': .1}),
                      event(4, entity=101, kind='counter', **{'name-hash': 99, 'slot-token': 2, 'counter': 2}),
                      event(7, entity=101, kind='remove', **{'name-hash': 99, 'slot-token': 2}),
                      event(11, 3, entity=101, kind='counter', **{'name-hash': 99, 'slot-token': 2, 'counter': 5})]
        self.cases = []
        self.contexts = []
        for offset, timestamp, action in zip((5, 12, 16), (1, 3, 4), self.actions):
            case = event(offset, timestamp, source=100, target=101, **{
                'replay-sha256': 'a' * 64, 'effect-kind': 'basic-attack-candidate',
                'damage-type': 'physical', 'data-gaps': [], 'recorded-amount': 54.,
                'source-observed': {'attack-damage': {'value': 78.}},
                'target-observed': {'armor': {'value': 44.}}})
            self.cases.append(case)
            self.contexts.append({**case, 'action-candidates': [action], 'status': 'unique-candidate',
                                  'stat-continuity': {'observed-stable': offset != 12}})
        self.rows = {'state': self.states, 'damage': self.cases, 'case': self.cases,
                     'action': self.actions, 'buff': self.buffs, 'outcome': self.cases,
                     'action-slot': self.actions, 'attack-context': self.contexts}
        self.write_sources()

    def write_sources(self):
        for label, streams in evidence.STREAMS.items():
            for kind, filename in streams.items():
                with gzip.open(self.folders[label] / filename, 'wt') as handle:
                    for row in self.rows[kind]:
                        handle.write(json.dumps(row) + '\n')
        combat = {**self.common, 'counts': {'state-accepted': len(self.states), 'damage-accepted': len(self.cases)},
                  'champion-entity-start': 100, 'roster': [{'slot': i, 'champion': n, 'team': i}
                                                         for i, n in enumerate(('Sion', 'KSante'))]}
        self.save_summary('combat', combat)
        audit = {**self.identity, 'counts': {'champion-to-champion-events': len(self.cases)},
                 'source-files': {n: digest(self.folders['combat'] / n)
                                  for n in ('summary.json', 'state.jsonl.gz', 'damage.jsonl.gz')},
                 'evidence-files': self.receipts('audit')}
        self.save_summary('audit', audit)
        for label in ('actions', 'buffs'):
            self.save_summary(label, {**self.common, 'archives': self.receipts(label),
                                      'counts': {'accepted': len(self.rows['action' if label == 'actions' else 'buff'])}})
        parents = {label: digest(self.folders[label] / 'summary.json') for label in ('combat', 'audit', 'actions')}
        self.save_summary('outcomes', {**self.common, 'inputs': parents, 'archives': self.receipts('outcomes')})
        self.save_summary('attack-review', {**self.identity, 'inputs': parents,
                                           'counts': {'ordinary-candidates': len(self.contexts)},
                                           'evidence-files': self.receipts('attack-review')})

    def receipts(self, label):
        return {name: digest(self.folders[label] / name) for name in evidence.STREAMS[label].values()}

    def save_summary(self, label, report):
        (self.folders[label] / 'summary.json').write_text(json.dumps(report))

    def build(self, name='store', interval=3):
        path = self.root / name
        evidence.build(self.folders, path, interval)
        store = evidence.EvidenceStore(path)
        self.addCleanup(store.close)
        return store

    def test_checkpoint_and_uninterrupted_reconstruction_agree_at_every_position(self):
        store = self.build()
        reference = evidence.Reconstruction()
        mutations = sorted([('state', {**r, 'observations': evidence.normalize(r, {100, 101})}) for r in self.states]
                           + [('buff', r) for r in self.buffs], key=lambda x: evidence.checked_key(x[1]['event-id']))
        for offset in range(1, 18):
            while mutations and evidence.checked_key(mutations[0][1]['event-id']) < (3, offset):
                kind, row = mutations.pop(0); reference.apply(kind, row)
            state, cost = store.before(f'gameChunk:3:{offset}')
            self.assertEqual(evidence.encoded(state.checkpoint()), evidence.encoded(reference.checkpoint()))
            self.assertLess(cost['mutation-events-applied'], 3)

    def test_wire_order_wins_over_equal_timestamps_and_expiry_does_not_remove_buff(self):
        store = self.build()
        first = store.package('gameChunk:3:5')
        target = first['observed-before-hit']['101']
        self.assertEqual(target['last-observed']['armor']['value'], 44.)
        buff = target['buffs']['observed-active'][0]
        self.assertEqual(buff['counter-update']['counter'], 2)
        self.assertFalse(target['buffs']['complete-buff-state'])
        later = store.package('gameChunk:3:12')['observed-before-hit']['101']
        self.assertEqual(later['last-observed']['armor']['value'], 70.)
        self.assertEqual(later['buffs']['observed-active'], [])
        self.assertTrue(later['buffs']['lifecycle-issues'])

    def test_unknown_extended_field_invalidates_old_value_and_preserves_receipt(self):
        store = self.build()
        middle = store.package('gameChunk:3:12')['observed-before-hit']['100']
        self.assertNotIn('primary-resource', middle['last-observed'])
        self.assertTrue(middle['observation-issues'])
        last = store.package('gameChunk:3:16')['observed-before-hit']['100']
        self.assertEqual(last['last-observed']['primary-resource']['value'], 0.)
        self.assertTrue(last['observation-issues'])

    def test_continuity_detects_mid_attack_update_and_health_bracket_is_not_review(self):
        store = self.build()
        first = store.package('gameChunk:3:5')
        self.assertTrue(first['recomputed-continuity']['observed-stable'])
        self.assertFalse(store.package('gameChunk:3:12')['recomputed-continuity']['observed-stable'])
        bracket = first['target-health-interval']
        self.assertEqual(bracket['before']['value'], 775.)
        self.assertEqual(bracket['after']['value'], 720.)
        self.assertEqual(len(bracket['damage-packets-between']), 1)
        self.assertFalse(bracket['closure-reviewed'])
        self.assertFalse(first['model-admissible'])
        self.assertEqual(set(first['remaining-semantic-blockers']), set(evidence.SEMANTIC_GAPS))

    def test_batch_needs_no_sources_and_can_query_earlier_actions(self):
        store = self.build()
        with patch.object(evidence, 'archive', side_effect=AssertionError('Archive reread')):
            for folder in self.folders.values():
                for path in folder.iterdir(): path.unlink()
            report = evidence.batch(store, ['gameChunk:3:16', 'gameChunk:3:5'], self.root / 'batch')
            self.assertEqual(report['cost']['source-archive-reads'], 0)
            self.assertEqual([r['event-id'] for r in report['records']], ['gameChunk:3:5', 'gameChunk:3:16'])
            self.assertEqual(len(store.history('action', 'gameChunk:3:16', entity=100)), 3)
            again = evidence.EvidenceStore(store.folder)
            self.addCleanup(again.close)
            self.assertEqual(store.package('gameChunk:3:5'), again.package('gameChunk:3:5'))

    def test_candidate_selection_excludes_amounts_predictions_and_unstable_context(self):
        store = self.build()
        candidates = store.candidates()
        self.assertEqual(len(candidates), 2)
        for candidate in candidates:
            self.assertNotIn('recorded-amount', candidate)
            self.assertNotIn('predicted', candidate)

    def test_changed_source_adapter_database_and_manifest_are_detected(self):
        store = self.build()
        source = self.folders['combat'] / 'state.jsonl.gz'
        source.write_bytes(source.read_bytes() + b'changed')
        with self.assertRaisesRegex(ValueError, 'source changed'):
            evidence.EvidenceStore(store.folder, verify_sources=True)
        with patch.object(evidence, 'adapters', return_value={}):
            with self.assertRaisesRegex(ValueError, 'stale'):
                evidence.EvidenceStore(store.folder)
        manifest = evidence.load(store.folder / 'manifest.json')
        changed = copy.deepcopy(manifest); changed['replay-sha256'] = 'd' * 64
        (store.folder / 'manifest.json').write_text(json.dumps(changed))
        with self.assertRaisesRegex(ValueError, 'fingerprint'):
            evidence.EvidenceStore(store.folder)
        (store.folder / 'manifest.json').write_text(json.dumps(manifest))
        with (store.folder / 'events.sqlite').open('ab') as handle: handle.write(b'corrupt')
        with self.assertRaisesRegex(ValueError, 'fingerprint'):
            evidence.EvidenceStore(store.folder)

    def test_incomplete_mixed_or_replaced_inputs_do_not_publish_store(self):
        report = evidence.load(self.folders['actions'] / 'summary.json')
        report['replay-sha256'] = 'd' * 64
        self.save_summary('actions', report)
        with self.assertRaisesRegex(ValueError, 'identity'):
            evidence.build(self.folders, self.root / 'bad')
        self.assertFalse((self.root / 'bad').exists())
        self.write_sources()
        self.rows['outcome'] = [self.cases[0], self.cases[1], {**self.cases[2], 'event-id': 'gameChunk:3:18'}]
        self.write_sources()
        with self.assertRaisesRegex(ValueError, 'identities'):
            evidence.build(self.folders, self.root / 'bad')
        self.assertFalse((self.root / 'bad').exists())

    def test_bad_batch_leaves_no_partial_result_and_does_not_overwrite(self):
        store = self.build()
        with self.assertRaises(ValueError):
            evidence.batch(store, ['gameChunk:3:5', 'gameChunk:3:999'], self.root / 'batch')
        self.assertFalse((self.root / 'batch').exists())
        evidence.batch(store, ['gameChunk:3:5'], self.root / 'batch')
        with self.assertRaises(ValueError):
            evidence.batch(store, ['gameChunk:3:5'], self.root / 'batch')

    def test_source_receipts_and_malformed_core_state_fail_closed(self):
        source = self.folders['combat'] / 'state.jsonl.gz'
        source.write_bytes(source.read_bytes() + b'changed')
        with self.assertRaisesRegex(ValueError, 'receipt mismatch'):
            evidence.build(self.folders, self.root / 'bad')
        self.states[0]['decoded-buffer-hex'] = '00'
        self.write_sources()
        with self.assertRaisesRegex(ValueError, 'Truncated'):
            evidence.build(self.folders, self.root / 'bad')
        self.assertFalse((self.root / 'bad').exists())

    def test_api_context_uses_pinned_sources_and_omits_account_identity_and_final_items(self):
        match = {'info': {'participants': [
            {'championName': name, 'teamId': i, 'participantId': i + 1, 'puuid': 'secret-account',
             'riotIdGameName': 'private-name', 'item0': 9999, 'summoner1Id': 4, 'summoner2Id': 12,
             'perks': {'styles': [{'selections': [{'perk': 8230}]}], 'statPerks': {'offense': 5008}}}
            for i, name in enumerate(('Sion', 'KSante'))]}}
        timeline = {'info': {'frames': [{'events': [
            {'timestamp': 100, 'type': 'ITEM_PURCHASED', 'participantId': 1, 'itemId': 1036,
             'secret-extra': 'must-not-escape'},
            {'timestamp': 1001, 'type': 'SKILL_LEVEL_UP', 'participantId': 1, 'skillSlot': 1},
            {'timestamp': 900, 'type': 'CHAMPION_KILL', 'killerId': 1, 'victimId': 2,
             'assistingParticipantIds': [2]}]}]}}
        match_path, timeline_path = self.root / 'match.json', self.root / 'timeline.json'
        match_path.write_text(json.dumps(match)); timeline_path.write_text(json.dumps(timeline))
        combat = evidence.load(self.folders['combat'] / 'summary.json')
        combat['validation'] = {'match-sha256': digest(match_path), 'timeline-sha256': digest(timeline_path)}
        self.save_summary('combat', combat)
        audit = evidence.load(self.folders['audit'] / 'summary.json')
        audit['source-files']['summary.json'] = digest(self.folders['combat'] / 'summary.json')
        self.save_summary('audit', audit)
        for label in ('outcomes', 'attack-review'):
            report = evidence.load(self.folders[label] / 'summary.json')
            for parent in ('combat', 'audit'):
                report['inputs'][parent] = digest(self.folders[parent] / 'summary.json')
            self.save_summary(label, report)
        path = self.root / 'api-store'
        evidence.build(self.folders, path, match=match_path, timeline=timeline_path)
        store = evidence.EvidenceStore(path); self.addCleanup(store.close)
        api = store.package('gameChunk:3:5')['api-context']
        self.assertEqual(len(api['events-through-api-time']), 2)
        self.assertEqual(api['events-through-api-time'][0]['actors']['participantId'], 100)
        self.assertEqual(api['events-through-api-time'][1]['assisting-entities'], [101])
        self.assertFalse(api['exact-replay-alignment'])
        for secret in ('secret-account', 'private-name', '9999', 'must-not-escape'):
            self.assertNotIn(secret, json.dumps(api))
        match_path.write_text('{}')
        with self.assertRaisesRegex(ValueError, 'API source'):
            evidence.build(self.folders, self.root / 'bad-api', match=match_path, timeline=timeline_path)


@unittest.skipUnless(os.environ.get('PS_REPLAY_EVIDENCE_STORE'), 'Optional retained replay evidence store')
class RetainedStoreTests(unittest.TestCase):
    def test_all_candidate_checkpoints_match_one_uninterrupted_archive_pass(self):
        store = evidence.EvidenceStore(os.environ['PS_REPLAY_EVIDENCE_STORE'], verify_sources=True)
        self.addCleanup(store.close)
        source = store.manifest['sources']
        states = ((evidence.checked_key(r['event-id']), 'state', r)
                  for r in evidence.archive(Path(source['combat/state.jsonl.gz']['path'])))
        buffs = ((evidence.checked_key(r['event-id']), 'buff', r)
                 for r in evidence.archive(Path(source['buffs/buffs.jsonl.gz']['path'])))
        rows = iter(heapq.merge(states, buffs))
        pending = next(rows, None)
        reference, ledger = ObservedState(), evidence.BuffLedger()
        candidates = store.candidates()
        self.assertGreater(len(candidates), 0)
        for case in candidates:
            event_key = evidence.checked_key(case['event-id'])
            while pending is not None and pending[0] < event_key:
                _, kind, row = pending
                if kind == 'state':
                    reference.apply(row['champions'], row['timestamp'], row['order'], row['event-id'])
                else:
                    ledger.apply(row)
                pending = next(rows, None)
            actual, cost = store.before(case['event-id'])
            snapshot = actual.snapshot(store.manifest['roster'], case['timestamp'])
            original_case = store.event('case', case['event-id'])
            with self.subTest(event=case['event-id']):
                self.assertLess(cost['mutation-events-applied'], store.manifest['checkpoint-every'])
                for player in store.manifest['roster']:
                    entity = player['entity']
                    expected = reference.before(entity, case['timestamp'], original_case['order'])
                    observed = snapshot[str(entity)]['last-observed']
                    for name, sample in expected.items():
                        self.assertEqual(observed[name]['value'], sample['value'])
                        if 'event-id' in sample:
                            self.assertEqual(observed[name]['event-id'], sample['event-id'])
                    self.assertEqual(snapshot[str(entity)]['buffs'], ledger.snapshot(entity))


if __name__ == '__main__':
    unittest.main()
