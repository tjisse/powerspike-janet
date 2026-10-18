"""Evidence must preserve uncertainty, causal order and decoder boundaries."""
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from replay_native import accepted_call, verify_inputs
from replay_state import ObservedState, replication_records, float_field
from replay_combat import snapshots_check, totals_check


def record(entity, group, mask, data):
    return struct.pack('<BII B', group, entity, mask, len(data)) + data


class NativeGuards(unittest.TestCase):
    def test_wrong_binary_is_refused_before_optional_emulator_import(self):
        profile = json.loads((Path(__file__).resolve().parents[1] /
                             'observations/replays/16.20.824.8524-native-profile.json').read_text())
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / 'wrong-image'
            image.write_bytes(b'wrong build')
            with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
                verify_inputs(image, profile)
            profile['client-build'] = '16.19'
            with self.assertRaisesRegex(ValueError, 'Unsupported'):
                verify_inputs(image, profile)

    def test_timeout_return_false_and_partial_reads_cannot_pass(self):
        accepted_call(100, 100, 1, 17, 17)
        for args in [(99, 100, 1, 17, 17), (100, 100, 0, 17, 17),
                     (100, 100, 1, 16, 17), (100, 100, 1, 18, 17)]:
            with self.assertRaises(ValueError):
                accepted_call(*args)


class ReplicationTests(unittest.TestCase):
    def test_default_escape_and_truncated_floats(self):
        self.assertEqual(float_field(b'\xff', 0), (0., 1))
        self.assertEqual(float_field(b'\xfe' + struct.pack('<f', 42), 0), (42., 5))
        for data in (b'', b'\xfe', b'\x00\x00\x00', struct.pack('<f', float('nan'))):
            with self.assertRaises(ValueError):
                float_field(data, 0)

    def test_unknown_later_integer_is_preserved_without_guessing_zero(self):
        # The build has an unresolved field 10; old-patch FF-as-zero loses a byte.
        data = record(7, 32, (1 << 0) | (1 << 10), struct.pack('<f', 123) + b'\xff\x02')
        decoded = replication_records(data)[0]
        self.assertEqual(decoded['fields'], {'health': 123.})
        self.assertEqual(decoded['components'][0]['uninterpreted-data-hex'], 'ff02')
        self.assertEqual(decoded['components'][0]['uninterpreted-mask'], 1 << 10)

    def test_nonchampion_layout_is_retained_without_champion_stat_interpretation(self):
        data = record(9, 4, 1 << 7, b'\x01')
        self.assertEqual(replication_records(data, {7})[0]['fields'], {})
        with self.assertRaises(ValueError):
            replication_records(data, {9})

    def test_empty_absent_field_is_unknown_not_zero(self):
        self.assertEqual(replication_records(record(7, 32, 0, b''))[0]['fields'], {})
        self.assertEqual(replication_records(record(7, 32, 1, b'\xff'))[0]['fields'], {'health': 0.})

    def test_record_lengths_and_unhandled_wrappers_fail_closed(self):
        good = record(7, 32, 1, struct.pack('<f', 500))
        for cut in range(1, len(good)):
            with self.assertRaises(ValueError):
                replication_records(good[:cut])
        for bad in (b'\x80\x00\x00\x00\x00', good + b'\x01',
                    record(7, 32, 1, struct.pack('<f', 500) + b'\x00')):
            with self.assertRaises(ValueError):
                replication_records(bad)


class CausalStateTests(unittest.TestCase):
    def test_same_timestamp_preserves_wire_order_and_never_uses_future(self):
        state = ObservedState()
        state.apply([{'entity': 7, 'fields': {'health': 500}}], 10., 1, 'before')
        snapshot = state.before(7, 10., 2)
        self.assertTrue(snapshot['health']['same-timestamp'])
        self.assertEqual(snapshot['health']['event-id'], 'before')
        state.apply([{'entity': 7, 'fields': {'health': 450}}], 10., 3, 'after')
        self.assertEqual(snapshot['health']['value'], 500)
        self.assertEqual(state.before(7, 10., 2), {})
        self.assertEqual(state.before(7, 11., 4)['health']['age-seconds'], 1.)

    def test_dropped_update_breaks_continuity_until_each_field_returns(self):
        state = ObservedState()
        state.apply([{'entity': 7, 'fields': {'health': 500, 'armor': 30}}], 1., 1, 'old')
        state.invalidate()
        self.assertEqual(state.before(7, 2., 2), {})
        state.apply([{'entity': 7, 'fields': {'health': 400}}], 3., 3, 'new')
        self.assertNotIn('armor', state.before(7, 4., 4))
        with self.assertRaises(ValueError):
            state.apply([], 2., 5, 'backwards')

    def test_api_disagreement_and_missing_state_remain_visible(self):
        history = {(7, 'health'): [(10., 1, 100.), (12., 2, 200.)]}
        timeline = {'info': {'frames': [{'timestamp': 11000, 'participantFrames': {
            '1': {'championStats': {'health': 95, 'healthMax': 500, 'armor': 30, 'magicResist': 30}}}}]}}
        check = snapshots_check(history, {0: 1}, 7, timeline)
        self.assertEqual(check['fields']['health']['different'], 1)
        self.assertEqual(check['rows'][0]['decoded'], 100)
        self.assertEqual(check['rows'][0]['difference'], 5)
        self.assertEqual(check['fields']['armor']['missing'], 1)

    def test_aggregate_tolerance_does_not_hide_one_point_or_missing_metric(self):
        from collections import Counter
        match = {'info': {'participants': [{'participantId': 1, 'totalDamageTaken': 10,
                 'totalDamageDealtToChampions': 8, 'physicalDamageTaken': 10,
                 'magicDamageTaken': 0, 'trueDamageTaken': 0}]}}
        totals = {7: Counter({'incoming': 10.9, 'outgoing-champions': 9, 'physical': 10})}
        result = totals_check(totals, [{'slot': 0}], 7, {0: 1}, match)
        self.assertEqual((result['checks'], result['within-one']), (5, 4))


if __name__ == '__main__':
    unittest.main()
