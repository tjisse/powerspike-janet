"""A real production check must remain scoped, bound, and retry-safe."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from replay_conditional_compare import (CASE, GAME, EVENT, REVIEWS, build_plan, tolerance,
    save_new, admit, execute, record_report, validate_plan, outcome)
from replay_coverage import Ledger, append, event, digest, load, model_identity, coverage_report

JANET = ROOT / 'build/janet'


class ConditionalPolicyTests(unittest.TestCase):
    def test_policy_depends_on_ad_not_prediction_or_observed_error(self):
        bound = tolerance(78.)
        self.assertGreater(bound, 0)
        self.assertLess(bound, .0001)
        self.assertGreater(tolerance(156.), bound)
        plan = {'model': 'a' * 64, 'observed': 50., 'tolerance': bound}
        native = {'model': plan['model'], 'predicted': 50.001}
        self.assertEqual(outcome(plan, native)['status'], 'mismatch')
        self.assertEqual(outcome(plan, native)['tolerance'], bound)
        for bad in (0, -1, True, float('nan'), float('inf'), 1e20):
            with self.subTest(bad=bad), self.assertRaises(ValueError): tolerance(bad)


@unittest.skipUnless(JANET.exists(), 'Production Janet runner unavailable')
class ConditionalComparisonTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.model = model_identity()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.ledger, self.plan, self.report = [self.folder / n for n in ('ledger.jsonl', 'plan.json', 'report.json')]
        self.reviews = self.folder / 'reviews'; self.reviews.mkdir()
        for name in ('final', 'amount', 'effect', ''):
            filename = 'first-hit-' + (name + '-' if name else '') + 'review-2026-10-18.json'
            (self.reviews / filename).write_bytes((REVIEWS / filename).read_bytes())
        final = self.reviews / 'first-hit-final-review-2026-10-18.json'
        packet = load(self.reviews / 'first-hit-review-2026-10-18.json')['damage-outcome']
        registry = load(ROOT / 'observations/verification/registry.json')
        append(self.ledger, [event('registry', registry=registry),
            event('game', id=GAME, build=packet.get('client-build', registry['client-build']), role='development'),
            event('case', id=CASE, game=GAME, **{'event-id': EVENT},
                  population='champion-to-champion', timestamp=packet['timestamp'], recorded=packet['amount'],
                  actor='Sion', target='KSante', features={'damage-type': 'physical', 'armor-band': 'low', 'resistance-band': 'low'},
                  **{'numeric-ready': True, 'effect-kind': 'basic-attack-candidate'},
                  blockers=[], obligations=['ordinary-physical', 'positive-armor']),
            event('annotation', case=CASE, source=digest(final),
                  reason='Six gates reviewed; sha256:' + digest(final), changes={'blockers': []})])
        self.recipe = build_plan(Ledger.read(self.ledger), self.model, self.reviews)
        save_new(self.plan, self.recipe)

    def test_actual_production_execution_and_reimport_credit_one_case_two_conditions(self):
        self.assertEqual(admit(self.plan, self.ledger, self.reviews), 1)
        self.assertEqual(admit(self.plan, self.ledger, self.reviews), 0)
        result = execute(self.plan, self.report, self.ledger, JANET, self.reviews)
        self.assertEqual(result['result']['status'], 'consistent')
        self.assertLessEqual(result['result']['absolute-error'], self.recipe['tolerance'])
        self.assertFalse(result['uses-runtime-build-data'])
        self.assertEqual(result['snapshot-kind'], 'reviewed-observed-scalars')
        before = Ledger.read(self.ledger).length
        self.assertEqual(record_report(self.plan, self.report, self.ledger, JANET, self.reviews), 0)
        state = Ledger.read(self.ledger)
        self.assertEqual(state.length, before)
        report = coverage_report(state, self.model)
        self.assertEqual(report['pipeline']['admitted'], 1)
        self.assertEqual(report['pipeline']['evaluated'], 1)
        self.assertEqual(report['coverage']['combat-checked'], 2)
        self.assertEqual(report['audit']['fresh-evaluated-games'], 0)
        self.assertFalse(state.results[0]['fresh-game'])
        self.assertEqual(report['history']['comparisons'], 1)

    def test_admission_is_required_before_prediction(self):
        with self.assertRaisesRegex(ValueError, 'Admit'):
            execute(self.plan, self.report, self.ledger, JANET, self.reviews)
        self.assertFalse(self.report.exists())

    def test_modified_input_tolerance_or_model_is_rejected(self):
        for change in ('tolerance', 'model', 'bool-input'):
            altered = copy.deepcopy(self.recipe)
            if change == 'tolerance': altered['tolerance'] = 100
            elif change == 'model': altered['model'] = 'a' * 64
            else: altered['context']['inputs']['source']['armor-pen-flat'] = False
            self.plan.write_text(json.dumps(altered))
            with self.subTest(change=change), self.assertRaises(ValueError): admit(self.plan, self.ledger, self.reviews)
        self.assertEqual(len(Ledger.read(self.ledger).admissions), 0)

    def test_new_case_revision_or_model_stales_the_recipe(self):
        with patch('replay_conditional_compare.model_identity', return_value='e' * 64), self.assertRaises(ValueError):
            validate_plan(self.plan, self.ledger, self.reviews)
        append(self.ledger, [event('annotation', case=CASE, source='f' * 64,
                                   reason='New CC evidence', changes={'blockers': ['cc']})])
        with self.assertRaises(ValueError): admit(self.plan, self.ledger, self.reviews)

    def test_unbound_or_changed_review_cannot_be_admitted(self):
        final = self.reviews / 'first-hit-final-review-2026-10-18.json'
        data = load(final); data['scope'] += ' changed'
        final.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'annotation'):
            build_plan(Ledger.read(self.ledger), self.model, self.reviews)

    def test_report_tampering_is_detected_by_production_reexecution(self):
        admit(self.plan, self.ledger, self.reviews)
        result = execute(self.plan, self.report, self.ledger, JANET, self.reviews)
        original = self.report.read_bytes()
        for changed in ('prediction', 'snapshot', 'scope'):
            data = copy.deepcopy(result)
            if changed == 'prediction':
                data['production-output']['predicted'] += 10
                data['result'] = outcome(self.recipe, data['production-output'])
            elif changed == 'snapshot': data['snapshot'] = 'f' * 64
            else: data['scope'] = 'All champion and build stats validated'
            self.report.write_text(json.dumps(data))
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                record_report(self.plan, self.report, self.ledger, JANET, self.reviews)
        self.report.write_bytes(original)
        self.assertEqual(len(Ledger.read(self.ledger).results), 1)

    def test_mismatch_is_retained_and_not_hidden_by_a_wider_tolerance(self):
        admit(self.plan, self.ledger, self.reviews)
        with patch('replay_conditional_compare.run_model', return_value={
                'model': self.model, 'raw': 78., 'effective-resistance': 44., 'predicted': 48.}):
            result = execute(self.plan, self.report, self.ledger, JANET, self.reviews)
        self.assertEqual(result['result']['status'], 'mismatch')
        report = coverage_report(Ledger.read(self.ledger), self.model)
        self.assertEqual(report['pipeline']['evaluated'], 1)
        self.assertEqual(report['coverage']['combat-checked'], 2)
        self.assertEqual(report['agreement']['mismatches'], 1)
        self.assertEqual(result['result']['tolerance'], self.recipe['tolerance'])


if __name__ == '__main__': unittest.main()
