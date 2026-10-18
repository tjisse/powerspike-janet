"""Gap recovery cannot manufacture context, fit damage or discard unknowns."""
import copy
import gzip
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from replay_gaps import audit, classify, effect_kind, elf32, ordered_rows, candidate_witness, append_derived_history
from replay_native import BUILD, PROTOCOL
from replay_state import ObservedState, AD_INPUTS, AP_INPUTS, derived_stats, replication_records


def samples(values):
    return {k: {'value': v, 'timestamp': 1., 'order': 1, 'event-id': 'observed'}
            for k, v in values.items()}


class OffensiveStats(unittest.TestCase):
    def test_unrelated_updates_do_not_refresh_derived_stat_evidence(self):
        from collections import defaultdict
        history = defaultdict(list)
        inputs = samples(dict(zip(AD_INPUTS, [70, 10, 0, 0, 0])))
        append_derived_history(history, 7, derived_stats(inputs))
        inputs['health'] = {'value': 500, 'timestamp': 20., 'order': 20, 'event-id': 'unrelated'}
        append_derived_history(history, 7, derived_stats(inputs))
        self.assertEqual(history[7, 'attack-damage'], [(1., 1, 80)])
        inputs['flat-attack-damage'] = {'value': 15, 'timestamp': 21., 'order': 21, 'event-id': 'ad-change'}
        append_derived_history(history, 7, derived_stats(inputs))
        self.assertEqual(history[7, 'attack-damage'][-1], (21., 21, 85))

    def test_components_compose_with_bonus_modifier_and_retain_provenance(self):
        inputs = samples(dict(zip(AD_INPUTS, [70, 50, .1, .08, .2])))
        result = derived_stats(inputs)['attack-damage']
        self.assertAlmostEqual(result['value'], 151.8)
        self.assertEqual(result['inputs'], inputs)
        del inputs['flat-attack-damage']
        self.assertEqual(derived_stats(inputs), {})
        self.assertIn('flat-attack-damage', result['inputs'])

    def test_explicit_zero_is_required_for_ability_power(self):
        inputs = samples(dict(zip(AP_INPUTS, [0, 100, .3])))
        self.assertEqual(derived_stats(inputs)['ability-power']['value'], 130)
        del inputs['base-ability-power']
        self.assertEqual(derived_stats(inputs), {})

    def test_group8_unknown_suffix_is_preserved_and_nonhero_layout_is_untouched(self):
        # Field19 = bonus AD modifier; field31 is an unresolved integer.
        data = struct.pack('<BIIB', 8, 7, (1 << 19) | (1 << 31), 6)
        data += struct.pack('<f', .08) + b'\xff\x02'
        rec = replication_records(data, {7})[0]
        self.assertAlmostEqual(rec['fields']['percent-bonus-attack-damage'], .08)
        self.assertEqual(rec['components'][0]['uninterpreted-data-hex'], 'ff02')
        self.assertEqual(replication_records(data, {8})[0]['fields'], {})

    def test_derived_hit_inputs_cannot_include_same_time_later_update(self):
        state = ObservedState()
        state.apply([{'entity': 7, 'fields': dict(zip(AD_INPUTS, [70, 10, 0, 0, 0]))}], 1., 1, 'old')
        snapshot = state.before(7, 2., 2)
        self.assertEqual(snapshot['attack-damage']['value'], 80)
        state.apply([{'entity': 7, 'fields': {'flat-attack-damage': 100}}], 2., 3, 'new')
        self.assertEqual(snapshot['attack-damage']['inputs']['flat-attack-damage']['event-id'], 'old')
        self.assertNotIn('attack-damage', state.before(7, 2., 2))
        state.invalidate()
        self.assertEqual(state.before(7, 3., 4), {})


class GapClassification(unittest.TestCase):
    def test_unique_hash_label_is_candidate_and_collisions_abstain(self):
        h = elf32('SionBasicAttack')
        self.assertEqual(effect_kind(h, 'Sion', {h: {'sionbasicattack'}})[0], 'basic-attack-candidate')
        self.assertEqual(effect_kind(h, 'Sion', {h: {'sionbasicattack', 'other'}})[0], 'ambiguous-effect')
        self.assertEqual(effect_kind(h, 'Tristana', {h: {'sionbasicattack'}})[0], 'other-effect')

    def test_unknown_fields_are_not_absence_and_amount_does_not_select_cases(self):
        event = {'effect-hash': elf32('sionbasicattack'), 'damage-type': 'physical', 'amount': 1}
        labels = {event['effect-hash']: {'sionbasicattack'}}
        before = copy.deepcopy(event)
        a = classify(event, {}, {}, 'Sion', labels)
        event['amount'] = 99999
        b = classify(event, {}, {}, 'Sion', labels)
        self.assertEqual(a, b)
        self.assertIn('missing-source:crit-chance', a['data-gaps'])
        self.assertIn('missing-target:shield-all-candidate', a['data-gaps'])
        self.assertFalse(a['model-admissible'])
        self.assertEqual(before['amount'], 1)

    def test_complete_numeric_inputs_still_do_not_approve_a_case(self):
        source = samples({'attack-damage': 78, 'crit-chance': 0, 'flat-armor-penetration': 0,
                          'armor-remaining-fraction': 1, 'physical-lethality': 0,
                          'bonus-armor-remaining-fraction': 1})
        target = samples({'armor': 44, 'shield-all-candidate': 0, 'shield-physical-candidate': 0})
        h = elf32('sionbasicattack')
        result = classify({'effect-hash': h, 'damage-type': 'physical'}, source, target,
                          'Sion', {h: {'sionbasicattack'}})
        self.assertEqual(result['data-gaps'], [])
        self.assertTrue(result['semantic-gaps'])
        self.assertFalse(result['model-admissible'])


class ArchiveGuards(unittest.TestCase):
    def test_duplicate_orders_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'rows.gz'
            with gzip.open(path, 'wt') as f:
                f.write('{"order":1}\n{"order":1}\n')
            with self.assertRaises(ValueError):
                list(ordered_rows(path, 'state'))

    def test_empty_archive_preserves_zero_coverage(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'source'; source.mkdir()
            summary = {'client-build': BUILD, 'protocol-digest': PROTOCOL, 'failures': {},
                       'champion-entity-start': 7, 'roster': [{'slot': 0, 'champion': 'Sion'}],
                       'replay-sha256': 'synthetic', 'counts': {'state-accepted': 0, 'damage-accepted': 0}}
            (source / 'summary.json').write_text(json.dumps(summary))
            for name in ('damage', 'state'):
                with gzip.open(source / (name + '.jsonl.gz'), 'wt') as f:
                    pass
            result = audit(source, root / 'out')
            self.assertEqual(result['admissible-cases'], 0)
            self.assertEqual(result['first-candidates'], [])
            with self.assertRaises(ValueError):
                audit(source, root / 'out')

    def test_witness_future_health_is_diagnostic_and_other_damage_remains_visible(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with gzip.open(root / 'state.jsonl.gz', 'wt') as f:
                for order, health in [(1, 500), (5, 440)]:
                    f.write(json.dumps({'order': order, 'timestamp': float(order), 'event-id': str(order),
                                        'champions': [{'entity': 7, 'fields': {'health': health}}]}) + '\n')
            with gzip.open(root / 'damage.jsonl.gz', 'wt') as f:
                for order, amount in [(2, 10), (3, 50)]:
                    f.write(json.dumps({'order': order, 'timestamp': float(order), 'event-id': str(order),
                                        'target': 7, 'amount': amount}) + '\n')
            result = candidate_witness({'target': 7, 'order': 3}, root)
            self.assertEqual(len(result['damage-between-health-samples']), 2)
            self.assertEqual(result['health-drop'], 60)
            self.assertFalse(result['model-admissible'])


if __name__ == '__main__':
    unittest.main()
