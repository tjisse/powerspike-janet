"""Packet context must retain ambiguity and refuse mixed or changed evidence."""
import gzip
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from replay_timing import context, review, removals_context
from replay_recovery import digest
from replay_native import BUILD, PROTOCOL, IMAGE_SHA256


class TimingTests(unittest.TestCase):
    def setUp(self):
        self.hit = {'event-id': 'gameChunk:4:100', 'timestamp': 10., 'source': 10,
                    'target': 20, 'effect-hash': 42, 'opcode': 150, 'amount': 123.}
        self.action = {'event-id': 'gameChunk:4:80', 'timestamp': 9.5, 'source': 10,
                       'target': 20, 'kind': 'basic-attack-announcement-candidate', 'opcode': 906}
        self.buff = {'event-id': 'gameChunk:4:90', 'timestamp': 10., 'entity': 10,
                     'name-hash': 43, 'kind': 'remove', 'opcode': 262, 'slot-token': 1}

    def test_ambiguity_and_all_buff_orderings_survive(self):
        second = {**self.action, 'event-id': 'gameChunk:4:81', 'timestamp': 9.8}
        after = {**self.buff, 'event-id': 'gameChunk:4:110'}
        row = context(self.hit, [self.action, second], [self.buff, after])
        self.assertEqual(row['status'], 'ambiguous')
        self.assertEqual(len(row['action-candidates']), 2)
        self.assertEqual([r['wire-position'] for r in row['buff-updates']], ['before', 'after'])
        self.assertEqual([r['offset-from-damage-seconds'] for r in row['buff-updates']], [0., 0.])
        self.assertFalse(row['server-timing-resolved'])
        self.assertFalse(row['model-admissible'])

    def test_amount_cannot_select_or_change_output(self):
        row = context(self.hit, [self.action], [self.buff])
        self.assertEqual(row, context({**self.hit, 'amount': 999999}, [self.action], [self.buff]))
        self.assertNotIn('amount', row['damage'])
        self.assertEqual(context(self.hit, [], [])['status'], 'no-candidate')
        self.assertEqual(context(self.hit, [{**self.action, 'target': 99}], [])['status'], 'no-candidate')
        for window in (0, -1, float('nan'), float('inf'), 11):
            with self.assertRaises(ValueError): context(self.hit, [], [], window)

    def test_removals_without_damage_are_never_dropped_or_labelled_expiry(self):
        added = {**self.buff, 'kind': 'add', 'event-id': 'gameChunk:4:60', 'timestamp': 8.}
        later = {**self.buff, 'event-id': 'gameChunk:5:5', 'timestamp': 20.}
        rows = removals_context([added, self.buff, later], [self.hit], [self.action], {42})
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]['observed-lifetime-seconds'], 2.)
        self.assertEqual(len(rows[0]['same-timestamp-damage-candidates']), 1)
        self.assertIsNone(rows[1]['matching-observed-add'])
        self.assertEqual(rows[1]['same-timestamp-damage-candidates'], [])
        self.assertTrue(all(not r['consumption-or-expiry-resolved'] for r in rows))

    def make_fixture(self, root):
        folders = {name: root / name for name in ('actions', 'buffs', 'combat')}
        for p in folders.values(): p.mkdir()
        files = {'actions': ('actions.jsonl.gz', [self.action]),
                 'buffs': ('buffs.jsonl.gz', [self.buff]), 'combat': ('damage.jsonl.gz', [self.hit])}
        for name, (filename, rows) in files.items():
            with gzip.open(folders[name] / filename, 'wt') as f:
                for row in rows: f.write(json.dumps(row) + '\n')
        formats = {'actions': 'powerspike-replay-actions', 'buffs': 'powerspike-replay-buffs',
                   'combat': 'powerspike-replay-combat'}
        for name, folder in folders.items():
            report = {'format': formats[name], 'version': 1, 'client-build': BUILD,
                      'protocol-digest': PROTOCOL, 'image-sha256': IMAGE_SHA256,
                      'profile-sha256': 'p', 'replay-sha256': 'r', 'failures': {},
                      'champion-entity-start': 10, 'roster': [{'slot': 0}], 'lifecycle': {},
                      'adapters': {p.name: digest(p) for p in (ROOT / 'scripts').glob('replay_*.py')},
                      'archives': {files[name][0]: digest(folder / files[name][0])},
                      'counts': {'906': 1} if name == 'actions' else {'262': 1} if name == 'buffs' else {'damage-accepted': 1}}
            (folder / 'summary.json').write_text(json.dumps(report))
        return folders

    def test_bound_report_rejects_tampering_mixed_inputs_and_failures(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); folders = self.make_fixture(root)
            def run(output='out', **extra):
                return review(folders['actions'], folders['buffs'], folders['combat'], 10, {42}, 43,
                              root / output, extra.get('damage', digest(folders['combat'] / 'damage.jsonl.gz')))
            report = run()
            self.assertEqual(report['counts-by-effect-hash']['42']['unique-candidate'], 1)
            self.assertEqual(report['model-admissible-cases'], 0)
            with self.assertRaises(ValueError): run()  # immutable output
            with self.assertRaises(ValueError): run('wrong-damage', damage='bad')
            path = folders['buffs'] / 'summary.json'
            original = json.loads(path.read_text())
            for changed in ({'replay-sha256': 'other'}, {'profile-sha256': 'other'}, {'failures': {'262': 1}},
                            {'adapters': {}}, {'archives': {}}, {'counts': {'262': 2}}):
                path.write_text(json.dumps({**original, **changed}))
                with self.subTest(changed=changed), self.assertRaises(ValueError): run('rejected')
            path.write_text(json.dumps(original))
            with (folders['actions'] / 'actions.jsonl.gz').open('ab') as f: f.write(b'changed')
            with self.assertRaisesRegex(ValueError, 'receipt'): run('tampered')


if __name__ == '__main__': unittest.main()
