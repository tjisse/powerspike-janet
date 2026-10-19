"""Action decoding and contextual matches cannot manufacture admitted hits."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from replay_actions import ActionDecoder, PROFILE, candidates
from replay_attack_review import continuity, DEPENDENCIES

IMAGE = ROOT / 'observations/local/riot-thebausffs-access/damage-research/LeagueofLegends-16.20-x64.macho'


class ActionContextTests(unittest.TestCase):
    def setUp(self):
        self.case = {'event-id': 'gameChunk:4:100', 'timestamp': 10., 'source': 1, 'target': 2,
                     'recorded-amount': 54.}
        self.action = {'event-id': 'gameChunk:4:90', 'timestamp': 9.7, 'source': 1, 'target': 2,
                       'kind': 'basic-attack-announcement-candidate'}

    def test_matches_require_causal_wire_order_actor_target_and_window(self):
        for change in ({'source': 3}, {'target': 4}, {'timestamp': 11.}, {'timestamp': 7.},
                       {'event-id': 'gameChunk:4:101'}, {'kind': 'spell-cast-announcement-candidate'}):
            with self.subTest(change=change):
                self.assertEqual(candidates(self.case, [{**self.action, **change}]), [])
        self.assertEqual(candidates(self.case, [self.action]), [self.action])
        for window in (0, -1, float('nan'), float('inf'), 11):
            with self.assertRaises(ValueError): candidates(self.case, [], window)

    def test_ambiguity_is_retained_and_damage_magnitude_does_not_select(self):
        actions = [self.action, {**self.action, 'event-id': 'gameChunk:4:91', 'timestamp': 9.9}]
        self.assertEqual(len(candidates(self.case, actions)), 2)
        self.assertEqual(candidates(self.case, actions), candidates({**self.case, 'recorded-amount': 99999}, actions))

    def history(self):
        return {(self.case[role], field): [{'wire-key': (3, 1), 'event-id': 'gameChunk:3:1',
                 'timestamp': 0., 'value': 1.}] for role, fields in DEPENDENCIES.items() for field in fields}

    def test_old_but_unchanged_client_observations_do_not_prove_server_sampling(self):
        report = continuity(self.case, self.action, self.history())
        self.assertTrue(report['complete-observed-inputs'])
        self.assertTrue(report['observed-stable'])
        self.assertFalse(report['server-sampling-resolved'])

    def test_changes_and_reversions_inside_interval_are_not_stable(self):
        h = self.history()
        h[2, 'armor'] += [{'wire-key': (4, 92), 'event-id': 'gameChunk:4:92', 'timestamp': 9.8, 'value': 2.},
                          {'wire-key': (4, 93), 'event-id': 'gameChunk:4:93', 'timestamp': 9.9, 'value': 1.},
                          {'wire-key': (4, 101), 'event-id': 'gameChunk:4:101', 'timestamp': 10., 'value': 99.}]
        report = continuity(self.case, self.action, h)
        armor = next(row for row in report['fields'] if row['role'] == 'target')
        self.assertFalse(report['observed-stable'])
        self.assertEqual([r['value'] for r in armor['value-changes']], [2., 1.])

    def test_missing_initial_value_or_noncausal_action_cannot_pass(self):
        h = self.history(); h.pop((2, 'armor'))
        report = continuity(self.case, self.action, h)
        self.assertFalse(report['complete-observed-inputs'])
        self.assertFalse(report['observed-stable'])
        with self.assertRaises(ValueError):
            continuity(self.case, {**self.action, 'event-id': self.case['event-id']}, h)


@unittest.skipUnless(IMAGE.exists() and importlib.util.find_spec('unicorn'),
                     'Optional exact-build image and Unicorn unavailable')
class NativeActionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.decoder = ActionDecoder(IMAGE, json.loads(PROFILE.read_text()))
        cls.cases = json.loads((ROOT / 'observations/replays/16.20.824.8524-action-cases.json').read_text())['cases']

    def test_frozen_packets_repeat_after_heap_reuse(self):
        for case in self.cases * 2:
            with self.subTest(event=case['event-id']):
                self.assertEqual(self.decoder.decode(case['opcode'], bytes.fromhex(case['payload-hex']),
                                                     case['source']), case['expected'])
        self.assertTrue(any(case['expected'].get('effect-hash') != case['expected'].get('secondary-hash-candidate')
                            for case in self.cases if case['opcode'] == 1215))

    def test_wrong_cast_subject_truncated_and_trailing_payloads_fail(self):
        from unicorn import UcError
        for case in self.cases:
            payload = bytes.fromhex(case['payload-hex'])
            for changed in (payload[:-1], payload + b'\x00'):
                with self.assertRaises((ValueError, UcError)):
                    self.decoder.decode(case['opcode'], changed, case['source'])
            if case['opcode'] == 1215:
                with self.assertRaisesRegex(ValueError, 'subject'):
                    self.decoder.decode(case['opcode'], payload, case['source'] + 1)

    def test_opcode_and_allocation_budgets_fail_closed(self):
        for opcode, payload in ((150, b'x'), (906, b''), (1215, b'x' * (self.decoder.MAX_BYTES + 1))):
            with self.assertRaises(ValueError): self.decoder.decode(opcode, payload, 1)


if __name__ == '__main__':
    unittest.main()
