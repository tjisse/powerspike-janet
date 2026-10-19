"""Final review is bounded to an invariant conditional-input case."""
import copy
import json
from pathlib import Path
import struct
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from replay_final_review import inventory, scope_check, SOURCE, TARGET, RENGAR
from replay_review_fields import fields, word


class ReviewFieldTests(unittest.TestCase):
    def test_retained_native_prefixes(self):
        fixture = json.loads((ROOT / 'observations/replays/16.20.824.8524-review-fields.json').read_text())
        for row in fixture['cases']:
            self.assertEqual(fields(row['component']), row['expected'])

    def test_resource_zero_max_four_and_fail_closed_mixed_field(self):
        component = {'group': 32, 'mask': (1 << 10) | (1 << 15) | (1 << 16),
                     'data-hex': (b'\x00\xff' + struct.pack('<f', 4.)).hex()}
        self.assertEqual(fields(component), {'primary-resource': 0., 'primary-resource-max': 4.})
        for changed in ('01' + component['data-hex'][2:], component['data-hex'][:-2], component['data-hex'] + '00'):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                fields({**component, 'data-hex': changed})

    def test_control_words_reject_truncation_and_overflow(self):
        for raw in (b'', b'\x80', b'\x80' * 5, b'\x80' * 4 + b'\x10'):
            with self.subTest(raw=raw), self.assertRaises(ValueError): word(raw, 0)


class FinalReviewTests(unittest.TestCase):
    def setUp(self):
        self.report = json.loads((ROOT / 'observations/replays/first-hit-final-review-2026-10-18.json').read_text())
        self.players = copy.deepcopy(self.report['source-team'])
        self.histories = {(r['entity'], r['field']): copy.deepcopy(r['observations']) for r in self.report['supporting-histories']}
        self.actions = json.loads((ROOT / 'observations/replays/first-hit-effect-review-2026-10-18.json').read_text())['observed-pre-hit-actions']
        self.stats = copy.deepcopy(self.report['sampling-review']['observations'])

    def check_context(self, deaths=None):
        return scope_check(self.players, self.histories, self.actions, self.stats, deaths or [])

    def test_six_gates_are_conditional_readiness_not_full_protocol_or_admission(self):
        self.check_context()
        self.assertEqual(len(set(self.report['cumulative-resolved-semantic-blockers'])), 6)
        self.assertEqual(self.report['remaining-semantic-blockers'], [])
        self.assertEqual(self.report['admitted-model-comparisons'], 0)
        self.assertFalse(self.report['sampling-review']['server-sampling-instant-known'])
        self.assertFalse(self.report['buff-metadata-retained']['target']['complete-buff-state'])
        self.assertTrue(self.report['buff-metadata-retained']['target']['lifecycle-issues'])
        self.assertEqual(len(self.report['resource-oracle-checks']), 20)

    def test_resource_gain_or_missing_resource_prevents_empowered_cast_exclusion(self):
        for value in (1., 4., None):
            self.setUp()
            if value is None: self.histories[RENGAR, 'primary-resource'] = []
            else: self.histories[RENGAR, 'primary-resource'][0]['value'] = value
            with self.subTest(value=value), self.assertRaises(ValueError): self.check_context()

    def test_extra_action_or_changed_cast_cannot_inherit_no_cc_review(self):
        self.actions.append({**self.actions[-1], 'source': RENGAR})
        with self.assertRaises(ValueError): self.check_context()
        self.setUp()
        self.actions[0]['effect-hash'] = 145275620  # Exhaust, not a ward.
        with self.assertRaises(ValueError): self.check_context()

    def test_new_ability_rune_or_item_requires_new_modifier_review(self):
        for field, value in [('skills', [{'timestamp': 2., 'slot': 3}]),
                             ('runes', [8351]), ('items', [3087])]:
            self.setUp(); self.players[1][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError): self.check_context()

    def test_transient_stat_or_control_change_and_death_invalidate_scope(self):
        self.stats['observed-stable'] = False
        with self.assertRaises(ValueError): self.check_context()
        self.setUp()
        self.stats['fields'][0]['before-action']['value'] += 10
        with self.assertRaises(ValueError): self.check_context()
        self.setUp()
        self.histories[TARGET, 'action-state-code'].append(
            {'event-id': 'gameChunk:4:43000', 'timestamp': 38., 'value': 99})
        with self.assertRaises(ValueError): self.check_context()
        self.setUp()
        self.histories[SOURCE, 'physical-damage-percentage-modifier'][0]['value'] = .15
        with self.assertRaises(ValueError): self.check_context()
        self.setUp()
        with self.assertRaises(ValueError): self.check_context([{'type': 'CHAMPION_KILL'}])

    def test_only_bounded_purchase_undo_is_supported(self):
        events = [{'type': 'ITEM_PURCHASED', 'itemId': 1086},
                  {'type': 'ITEM_UNDO', 'beforeId': 1086, 'afterId': 0, 'goldGain': 400},
                  {'type': 'ITEM_PURCHASED', 'itemId': 1082}]
        self.assertEqual(inventory(events), [1082])
        for change in ({'goldGain': 300}, {'afterId': 1036}, {'beforeId': 9999}):
            mutated = copy.deepcopy(events); mutated[1].update(change)
            with self.subTest(change=change), self.assertRaises(ValueError): inventory(mutated)


if __name__ == '__main__': unittest.main()
