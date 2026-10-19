"""Only an isolated independently measured health bracket resolves this metric."""
import copy
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from replay_amount_review import bracket, GAME, EVENT


class AmountReviewTests(unittest.TestCase):
    def setUp(self):
        self.case = {'replay-sha256': GAME, 'event-id': EVENT, 'timestamp': 38.32643605041511,
                     'damage-type': 'physical', 'source': 1, 'target': 2,
                     'recorded-amount': 54.166664123535156, 'effect-hash': 264459371}
        self.health = [
            {'event-id': 'gameChunk:3:71962', 'timestamp': 5.025256216049195,
             'health': 775., 'health-max': 775.},
            {'event-id': 'gameChunk:4:44032', 'timestamp': 38.392436050415114,
             'health': 720.8333129882812, 'health-max': 775.}]
        self.damage = [{'event-id': EVENT, 'source': 1, 'target': 2, 'damage-type': 'physical',
                        'effect-hash': 264459371, 'amount': 54.166664123535156}]
        self.capacities = [{k: v for k, v in self.health[0].items() if k != 'health'}]

    def check_bracket(self):
        return bracket(self.case, self.health, self.damage, self.capacities)

    def test_metric_is_independent_health_loss_not_a_model_tolerance(self):
        result = self.check_bracket()
        self.assertEqual(result['status'], 'corroborated-health-damage-amount-for-this-case')
        self.assertLess(abs(result['closure']['difference']), result['closure']['measurement-bound'])
        self.assertIn('not fitted', result['closure']['bound-policy'])
        self.assertIn('not', result['scope'].lower())

    def test_another_target_does_not_confuse_the_target_health_bracket(self):
        self.damage.append({**self.damage[0], 'event-id': 'gameChunk:4:43919', 'target': 3})
        self.assertEqual(len(self.check_bracket()['damage-between-health-samples']), 1)

    def test_extra_hit_or_wrong_actor_or_effect_cannot_close_one_hit(self):
        for updates in ({'event-id': 'gameChunk:4:43919'}, {'source': 3}, {'effect-hash': 4}):
            self.setUp()
            if 'event-id' in updates:
                self.damage.append({**self.damage[0], **updates})
            else:
                self.damage[0].update(updates)
            with self.subTest(updates=updates), self.assertRaises(ValueError): self.check_bracket()

    def test_missing_duplicate_or_reordered_health_samples_fail(self):
        original = copy.deepcopy(self.health)
        for changed in ([], original[:1], original[1:], original[::-1], original + [original[-1]]):
            self.health = changed
            with self.subTest(changed=changed), self.assertRaises(ValueError): self.check_bracket()

    def test_lethal_nonfull_or_healing_overlapping_brackets_cannot_pass(self):
        for index, updates in ((1, {'health': 0}), (0, {'health': 774.}),
                               (1, {'health': 775.}), (1, {'health': 720.9}),
                               (1, {'health': float('nan')}), (1, {'health-max': 800.})):
            self.setUp()
            self.health[index].update(updates)
            with self.subTest(updates=updates), self.assertRaises(ValueError): self.check_bracket()

    def test_capacity_changes_and_reversions_cannot_hide_between_samples(self):
        self.capacities += [
            {'event-id': 'gameChunk:4:43000', 'timestamp': 38., 'health-max': 800.},
            {'event-id': 'gameChunk:4:43800', 'timestamp': 38.3, 'health-max': 775.}]
        with self.assertRaises(ValueError): self.check_bracket()
        self.capacities = []
        with self.assertRaises(ValueError): self.check_bracket()

    def test_other_games_events_and_damage_types_require_separate_semantics(self):
        for updates in ({'replay-sha256': 'a' * 64}, {'event-id': 'gameChunk:4:43919'},
                        {'damage-type': 'true'}):
            self.setUp(); self.case.update(updates)
            with self.subTest(updates=updates), self.assertRaises(ValueError): self.check_bracket()


if __name__ == '__main__':
    unittest.main()
