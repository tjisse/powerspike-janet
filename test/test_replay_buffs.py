"""Lifecycle uncertainty must survive extraction and causal joins."""
import sys
import importlib.util
import json
import copy
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from replay_buffs import BuffLedger, wire_key, ward_counter_check
from replay_context import early_inventory, item_input, run_model
from replay_native import NativeDecoder

ROOT = Path(__file__).resolve().parents[1]
IMAGE = ROOT / 'observations/local/riot-thebausffs-access/damage-research/LeagueofLegends-16.20-x64.macho'


def event(offset, kind, name=100, token=7, counter=None):
    return {'event-id': f'gameChunk:4:{offset}', 'timestamp': 10.,
            'entity': 1, 'kind': kind, 'name-hash': name,
            'slot-token': token, 'counter': counter}


class LifecycleTests(unittest.TestCase):
    def test_wire_order_is_numeric_and_equal_timestamps_do_not_reorder(self):
        self.assertLess(wire_key('gameChunk:4:9'), wire_key('gameChunk:4:10'))
        ledger = BuffLedger()
        ledger.apply(event(9, 'add'))
        before = ledger.snapshot(1)
        ledger.apply(event(10, 'remove'))
        self.assertEqual(len(before['observed-active']), 1)
        self.assertEqual(ledger.snapshot(1)['observed-active'], [])
        with self.assertRaises(ValueError):
            ledger.apply(event(9, 'add'))

    def test_zero_and_unknown_counters_are_not_removal_or_absence(self):
        ledger = BuffLedger()
        ledger.apply(event(1, 'add'))
        for offset, counter in ((2, 0), (3, None)):
            ledger.apply(event(offset, 'counter', counter=counter))
            state = ledger.snapshot(1)
            self.assertEqual(len(state['observed-active']), 1)
            self.assertIs(state['observed-active'][0]['counter-update']['counter'], counter)
            self.assertFalse(state['complete-buff-state'])

    def test_hash_mismatch_cannot_remove_a_reused_slot(self):
        ledger = BuffLedger()
        ledger.apply(event(1, 'add', name=100))
        ledger.apply(event(2, 'remove', name=200))
        self.assertEqual(ledger.snapshot(1)['observed-active'][0]['name-hash'], 100)
        self.assertEqual(ledger.counts['remove-without-matching-add'], 1)
        ledger.apply(event(3, 'add', name=200))
        self.assertEqual(ledger.counts['replacement-without-removal'], 1)

    def test_unmatched_counter_does_not_create_an_active_buff(self):
        ledger = BuffLedger()
        ledger.apply(event(1, 'counter', counter=8))
        self.assertEqual(ledger.snapshot(1)['observed-active'], [])
        self.assertEqual(len(ledger.snapshot(1)['lifecycle-issues']), 1)


class ContextGuards(unittest.TestCase):
    def test_ward_hypothesis_keeps_herald_exception_separate(self):
        summary = {'champion-entity-start': 1, 'roster': [{'slot': 0, 'champion': 'Sion', 'team': 100}]}
        match = {'info': {'participants': [{'participantId': 1, 'championName': 'Sion', 'teamId': 100}]}}
        timeline = {'info': {'frames': [{'events': [
            {'type': 'WARD_PLACED', 'creatorId': 1, 'timestamp': 9000, 'wardType': 'YELLOW_TRINKET'},
            {'type': 'WARD_PLACED', 'creatorId': 1, 'timestamp': 9001, 'wardType': 'CONTROL_WARD'},
            {'type': 'ITEM_DESTROYED', 'participantId': 1, 'timestamp': 9500, 'itemId': 3513}]}]}}
        row = event(1, 'counter', name=205256130, counter=2)
        self.assertEqual(ward_counter_check([row], summary, match, timeline)['consistent'], 0)
        self.assertEqual(ward_counter_check([row], summary, match, timeline, True)['consistent'], 1)

    def test_inventory_prefix_refuses_undo_or_unobserved_removal(self):
        purchases = [{'type': 'ITEM_PURCHASED', 'itemId': 1036},
                     {'type': 'ITEM_PURCHASED', 'itemId': 2003}]
        self.assertEqual(early_inventory(purchases + [{'type': 'ITEM_DESTROYED', 'itemId': 2003}]), [1036])
        for event in ({'type': 'ITEM_UNDO'}, {'type': 'ITEM_SOLD', 'itemId': 9999}):
            with self.assertRaises(ValueError):
                early_inventory(purchases + [event])

    def test_new_items_or_stats_require_explicit_mapping(self):
        with self.assertRaises(ValueError):
            item_input({'data': {}}, 9999)
        with self.assertRaises(ValueError):
            item_input({'data': {'1036': {'stats': {'UnknownBonus': 10}}}}, 1036)


@unittest.skipUnless(IMAGE.exists() and importlib.util.find_spec('unicorn'),
                     'Optional exact-build image/emulator unavailable')
class NativeBuffRegressions(unittest.TestCase):
    def test_exact_build_fields_constants_and_truncation(self):
        profile = json.loads((ROOT / 'observations/replays/16.20.824.8524-native-profile.json').read_text())
        cases = json.loads((ROOT / 'observations/replays/16.20.824.8524-buff-cases.json').read_text())['cases']
        decoder = NativeDecoder(IMAGE, profile)
        for row in cases:
            payload = bytes.fromhex(row['payload-hex'])
            self.assertEqual(decoder.buff(row['opcode'], payload), row['expected'])
            with self.assertRaises(ValueError):
                decoder.buff(row['opcode'], payload[:-1])


@unittest.skipUnless((ROOT / 'build/janet').exists(), 'Janet runtime unavailable')
class ComponentHarnessTests(unittest.TestCase):
    def test_model_prediction_changes_with_inputs_without_observed_damage(self):
        report = json.loads((ROOT / 'observations/replays/context-study-2026-10-18.json').read_text())
        inputs = copy.deepcopy(report['stat-model-inputs'])
        # Only game-data inputs enter the process; there is no recorded damage
        # or observed-stat field in this data-only input schema.
        baseline = run_model(inputs, ROOT / 'build/janet')
        source = next(r for r in inputs['cases'] if r['id'] == 'source')
        sword = next(item for item in source['items'] if item['id'] == '1036')
        sword['stats']['ad'] += 1
        changed = run_model(inputs, ROOT / 'build/janet')
        self.assertEqual(changed['source', 'ad'] - baseline['source', 'ad'], 1)
        self.assertEqual(changed['target', 'armor'], baseline['target', 'armor'])
        self.assertGreater(changed['first-attack-conditional', 'damage'],
                           baseline['first-attack-conditional', 'damage'])


if __name__ == '__main__':
    unittest.main()
