"""Native fields and a narrow semantic review must not imply admission."""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from replay_first_hit_review import (GAME, EVENT, RESOLVED, attack_identity,
                                    causal_skills, health_closure, inventory_context)
from replay_gaps import SEMANTIC_GAPS, elf32
from replay_outcomes import OutcomeDecoder, PROFILE

IMAGE = ROOT / 'observations/local/riot-thebausffs-access/damage-research/LeagueofLegends-16.20-x64.macho'


class FirstHitReviewTests(unittest.TestCase):
    def setUp(self):
        self.case = {'event-id': EVENT, 'replay-sha256': GAME, 'timestamp': 38.32643605041511,
            'source': 1, 'target': 2, 'damage-type': 'physical', 'recorded-amount': 54.166664123535156,
            'effect-hash': elf32('SionBasicAttack'), 'source-observed': {'crit-chance': {'value': 0}}}
        self.action = {'event-id': 'gameChunk:4:42928', 'timestamp': 37.99243605041511,
            'source': 1, 'target': 2, 'attack-slot': 64, 'auxiliary-cast-count': 0,
            'kind': 'basic-attack-announcement-candidate'}
        self.result = {'result-code': 5, 'source': 1, 'target': 2,
            'amount': self.case['recorded-amount'], 'effect-hash': self.case['effect-hash']}

    def test_review_scope_is_case_specific_and_leaves_four_blockers(self):
        result = attack_identity(self.case, self.action, self.result, {'mScriptName': 'SionBasicAttack'})
        self.assertEqual(result['status'], 'corroborated-for-this-case')
        self.assertEqual(len(set(SEMANTIC_GAPS) - set(RESOLVED)), 4)
        changed = {**self.case, 'event-id': 'gameChunk:4:99999'}
        with self.assertRaises(ValueError):
            attack_identity(changed, self.action, self.result, {'mScriptName': 'SionBasicAttack'})

    def test_empowered_crit_wrong_subject_or_noncausal_evidence_cannot_pass(self):
        for target, updates in (('action', {'attack-slot': 51}), ('action', {'auxiliary-cast-count': 1}),
                ('action', {'timestamp': 39}), ('action', {'target': 3}),
                ('result', {'result-code': 3}), ('result', {'result-code': 4}),
                ('result', {'amount': 0}), ('result', {'effect-hash': 99}),
                ('result', {'source': 3}), ('case', {'source-observed': {'crit-chance': {'value': .1}}})):
            values = {'case': copy.deepcopy(self.case), 'action': self.action.copy(), 'result': self.result.copy()}
            values[target].update(updates)
            with self.subTest(target=target, updates=updates), self.assertRaises(ValueError):
                attack_identity(**values, spell={'mScriptName': 'SionBasicAttack'})

    def witness(self):
        return {'case': self.case, 'health-before': {'health': 775.0},
                'health-after': {'health': 720.8333129882812},
                'damage-between-health-samples': [{'event-id': EVENT}]}

    def test_health_closure_uses_measurement_precision_without_model_prediction(self):
        report = health_closure(self.witness())
        self.assertLess(abs(report['difference']), report['measurement-bound'])
        self.assertLess(report['measurement-bound'], .0001)
        self.assertIn('not fitted', report['bound-policy'])

    def test_other_damage_or_missing_health_loss_invalidates_closure(self):
        for updates in ({'health-after': {'health': 775.0}}, {'health-after': {'health': 720.8}},
                        {'health-after': {'health': float('nan')}},
                        {'damage-between-health-samples': []},
                        {'damage-between-health-samples': [{'event-id': EVENT}, {'event-id': 'other'}]},
                        {'damage-between-health-samples': [{'event-id': 'other'}]}):
            with self.subTest(updates=updates), self.assertRaises(ValueError):
                health_closure({**self.witness(), **updates})

    def test_unknown_inventory_and_undo_are_not_assumed_away(self):
        items = {'data': {'1036': {'name': 'Long Sword', 'stats': {'FlatPhysicalDamageMod': 10}}}}
        events = [{'type': 'ITEM_PURCHASED', 'itemId': 1036}]
        self.assertEqual(inventory_context(events, items)[0]['name'], 'Long Sword')
        for changed in ([{'type': 'ITEM_PURCHASED', 'itemId': 9999}],
                        events + [{'type': 'ITEM_UNDO', 'beforeId': 1036, 'afterId': 0}],
                        events + [{'type': 'CHAMPION_KILL'}]):
            with self.assertRaises(ValueError): inventory_context(changed, items)

    def test_future_and_other_players_skills_are_not_forward_filled(self):
        timeline = {'info': {'frames': [{'events': [
            {'type': 'SKILL_LEVEL_UP', 'participantId': 1, 'timestamp': 36000, 'skillSlot': 1},
            {'type': 'SKILL_LEVEL_UP', 'participantId': 1, 'timestamp': 40000, 'skillSlot': 3},
            {'type': 'SKILL_LEVEL_UP', 'participantId': 2, 'timestamp': 1000, 'skillSlot': 2}]}]}}
        self.assertEqual(causal_skills(timeline, 1, 38), [{'timestamp': 36., 'slot': 1}])


@unittest.skipUnless(IMAGE.exists() and importlib.util.find_spec('unicorn'),
                     'Optional exact-build image and Unicorn unavailable')
class NativeOutcomeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.decoder = OutcomeDecoder(IMAGE, json.loads(PROFILE.read_text()))
        cls.cases = json.loads((ROOT / 'observations/replays/16.20.824.8524-outcome-cases.json').read_text())

    def test_slot_field_and_damage_codes_survive_heap_reuse(self):
        for _ in range(2):
            for row in self.cases['actions']:
                actual = self.decoder.action(row['opcode'], bytes.fromhex(row['payload-hex']), row['source'])
                self.assertEqual(actual, row['expected'])
                self.assertNotIn('encoded-slot', actual)
            for row in self.cases['damage']:
                actual = self.decoder.damage_outcome(bytes.fromhex(row['payload-hex']), row['target'])
                self.assertEqual(actual, row['expected'])
                self.assertNotIn('source-kind-encoded', actual)
        self.assertEqual({row['expected']['result-code'] for row in self.cases['damage']}, {3, 5, 6})

    def test_all_native_byte_codecs_are_complete_bijections(self):
        for table in (self.decoder.slots, self.decoder.action_words, self.decoder.results, self.decoder.contexts):
            self.assertEqual(set(table), set(range(256)))
            self.assertEqual(set(table.values()), set(range(256)))


if __name__ == '__main__':
    unittest.main()
