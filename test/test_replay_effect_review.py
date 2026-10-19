"""A shield-free capability review cannot generalize to changed circumstances."""
import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from replay_effect_review import eligible_shield_context, SHIELD_GATE
from replay_gaps import elf32


class ShieldEligibilityTests(unittest.TestCase):
    def setUp(self):
        self.report = json.loads((ROOT / 'observations/replays/first-hit-effect-review-2026-10-18.json').read_text())
        self.players = copy.deepcopy(self.report['target-team'])
        self.actions = copy.deepcopy(self.report['observed-pre-hit-actions'])
        self.snapshot = copy.deepcopy(self.report['target-buff-snapshot'])
        self.shields = {name: {'value': 0.} for name in
            ('shield-all-candidate', 'shield-physical-candidate', 'shield-magic-candidate')}

    def check_context(self):
        return eligible_shield_context(self.players, 38.32643605041511, self.actions, self.snapshot, self.shields)

    def test_reviewed_case_excludes_shield_eligibility_but_does_not_admit_damage(self):
        self.assertEqual(self.check_context(), self.report['shield-context-review'])
        self.assertEqual(self.report['resolved-semantic-blockers'], [SHIELD_GATE])
        self.assertEqual(len(self.report['remaining-semantic-blockers']), 3)
        self.assertFalse(self.report['model-admissible'])
        self.assertFalse(self.report['complete-buff-state'])
        self.assertTrue(self.snapshot['lifecycle-issues'])
        self.assertIn('Glacial Augment', self.report['effect-review-still-open'][0])

    def test_new_shield_ability_item_rune_or_summoner_requires_review(self):
        for field, replacement in (
                ('skill-upgrades-before-hit', [{'timestamp': 36.422, 'slot': 3}]),
                ('items', [3190, 2003, 3340]),
                ('rune-ids', [8465, 8446, 8444, 8242, 8299, 9105]),
                ('summoner-spell-ids', [4, 21]), ('team', 200)):
            self.setUp()
            player = next(r for r in self.players if r['champion'] == 'KSante')
            player[field] = replacement
            with self.subTest(field=field), self.assertRaises(ValueError): self.check_context()

    def test_ally_ability_or_unknown_roster_cannot_inherit_case_review(self):
        next(r for r in self.players if r['champion'] == 'Blitzcrank')['skill-upgrades-before-hit'] = [
            {'timestamp': 2., 'slot': 1}]
        with self.assertRaises(ValueError): self.check_context()
        self.setUp()
        self.players[-1]['champion'] = 'Lulu'
        with self.assertRaises(ValueError): self.check_context()
        self.setUp()
        self.players.append(copy.deepcopy(self.players[0]))
        with self.assertRaises(ValueError): self.check_context()

    def test_new_teleport_cast_or_quest_completion_cannot_pass(self):
        self.actions.append({'kind': 'spell-cast-announcement-candidate', 'source': 1073741998,
                             'effect-hash': elf32('SummonerTeleport')})
        with self.assertRaises(ValueError): self.check_context()
        self.setUp()
        quest = next(r for r in self.snapshot['observed-active']
                     if r['name-hash'] == elf32('SR_2026_S1_RoleBound_Top_Quest'))
        quest['counter-update']['counter'] = 1200
        with self.assertRaises(ValueError): self.check_context()
        self.setUp()
        self.snapshot['observed-active'].append({'name-hash': elf32('SR_2026_S1_RoleBound_Top_QuestCompleted')})
        with self.assertRaises(ValueError): self.check_context()

    def test_missing_quest_or_contradictory_shield_observation_cannot_pass(self):
        self.snapshot['observed-active'] = []
        with self.assertRaises(ValueError): self.check_context()
        for field in self.shields:
            self.setUp()
            self.shields[field]['value'] = 20.
            with self.subTest(field=field), self.assertRaises(ValueError): self.check_context()

    def test_later_game_cannot_inherit_early_context(self):
        with self.assertRaises(ValueError):
            eligible_shield_context(self.players, 600., self.actions, self.snapshot, self.shields)


if __name__ == '__main__':
    unittest.main()
