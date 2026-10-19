"""Reviewed batch execution must preserve blockers, fixed recipes and mismatches."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import replay_batch_compare as batch
from replay_batch_review import health_measurement
from replay_coverage import Ledger, append, event, load

JANET = ROOT / 'build/janet'


class MeasurementTests(unittest.TestCase):
    def test_isolated_nonlethal_measurement_closure_is_independent_of_model(self):
        p = {'event-id': 'gameChunk:3:9', 'damage-outcome': {'amount': 54.166664123535156},
             'target-health-interval': {'before': {'value': 775.}, 'after': {'value': 720.8333129882812},
                                      'damage-packets-between': [{'event-id': 'gameChunk:3:9'}]}}
        self.assertTrue(health_measurement(p)['closes'])
        p['target-health-interval']['damage-packets-between'].append({'event-id': 'gameChunk:3:8'})
        self.assertFalse(health_measurement(p)['closes'])
        p['target-health-interval']['after']['value'] += 1
        self.assertFalse(health_measurement(p)['closes'])


@unittest.skipUnless(JANET.exists(), 'Optional local production Janet runtime')
class BatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.ledger = self.root / 'ledger.jsonl'
        self.review = self.root / 'review.json'
        self.plan = self.root / 'plan.json'
        self.report = self.root / 'report.json'
        self.review.write_bytes(batch.REVIEW.read_bytes())
        self.review_data = load(self.review)
        registry = load(ROOT / 'observations/verification/registry.json')
        rows = [event('registry', registry=registry), event('game', id=batch.GAME,
                build=self.review_data['client-build'], role='development')]
        for r in self.review_data['cases']:
            armor = next(f['before-action']['value'] for f in r['sampling-observations']['fields']
                         if (f['role'], f['field']) == ('target', 'armor'))
            band = 'low' if armor < 50 else 'medium' if armor < 100 else 'high'
            rows.append(event('case', id=r['case'], game=batch.GAME, **{'event-id': r['event-id']},
                timestamp=r['health-measurement']['before']['timestamp'],
                population='champion-to-champion', recorded=r['health-measurement']['wire-damage'],
                actor=r['source'], target=r['target'], **{'numeric-ready': True, 'effect-kind': 'basic-attack-candidate'},
                obligations=['ordinary-physical', 'positive-armor'], blockers=list(batch.SEMANTIC_GAPS),
                features={'damage-type': 'physical', 'armor-band': band, 'resistance-band': band}))
        append(self.ledger, rows)
        self.bundle = batch.prepare(self.review, self.plan, self.ledger)

    def fake_output(self, p, janet):
        return {'model': p['model'], 'raw': p['context']['inputs']['source']['ad'],
                'effective-resistance': p['context']['inputs']['target']['armor'], 'predicted': p['observed'] + 1}

    def test_only_three_reviewed_cases_get_plans_and_tolerances_are_fixed(self):
        self.assertEqual(len(self.bundle['plans']), 3)
        self.assertEqual(len(self.bundle['blocked']), 1)
        self.assertTrue(self.bundle['blocked'][0]['remaining-semantic-blockers'])
        for p in self.bundle['plans']:
            self.assertLess(p['tolerance'], .0001)
            self.assertEqual(p['tolerance'], batch.tolerance(p['context']['inputs']['source']['ad']))

    def test_model_is_never_called_before_admission(self):
        with patch.object(batch, 'run_model') as run:
            with self.assertRaisesRegex(ValueError, 'Admit'):
                batch.execute(self.plan, self.report, self.review, self.ledger, JANET)
            run.assert_not_called()
        self.assertFalse(self.report.exists())

    def test_blocked_case_cannot_be_promoted_by_flipping_review_flag(self):
        changed = copy.deepcopy(self.review_data)
        changed['cases'][-1]['ready-for-conditional-comparison'] = True
        changed['cases'][-1]['remaining-semantic-blockers'] = []
        changed['cases'][-1]['resolved-semantic-blockers'] = list(batch.SEMANTIC_GAPS)
        self.review.write_text(json.dumps(changed))
        with self.assertRaisesRegex(ValueError, 'blocked case'):
            batch.checked_review(self.review)

    def test_failed_prepare_does_not_clear_or_revise_case_blockers(self):
        state = Ledger.read(self.ledger)
        selected = self.bundle['plans'][0]['case']
        append(self.ledger, [event('annotation', case=selected, source='f' * 64,
                                   reason='Numeric inputs invalidated', changes={'numeric-ready': False, 'blockers': ['missing']})])
        before = self.ledger.read_bytes()
        with self.assertRaises(ValueError):
            batch.prepare(self.review, self.root / 'invalid-plan.json', self.ledger)
        self.assertEqual(before, self.ledger.read_bytes())

    def test_edited_plan_model_policy_and_bool_inputs_are_rejected(self):
        for name in ('tolerance', 'model', 'bool-input'):
            changed = copy.deepcopy(self.bundle)
            if name == 'tolerance': changed['plans'][0]['tolerance'] = 100
            elif name == 'model': changed['plans'][0]['model'] = 'a' * 64
            else: changed['plans'][0]['context']['inputs']['source']['armor-pen-flat'] = False
            self.plan.write_text(json.dumps(changed))
            with self.subTest(name=name), self.assertRaises(ValueError):
                batch.admit(self.plan, self.review, self.ledger)
        self.assertEqual(Ledger.read(self.ledger).admissions, [])

    def test_mismatches_are_recorded_and_reimport_is_idempotent(self):
        self.assertEqual(batch.admit(self.plan, self.review, self.ledger), 3)
        self.assertEqual(batch.admit(self.plan, self.review, self.ledger), 0)
        with patch.object(batch, 'run_model', side_effect=self.fake_output) as run:
            r = batch.execute(self.plan, self.report, self.review, self.ledger, JANET)
            self.assertEqual(run.call_count, 3)
            self.assertEqual([x['result']['status'] for x in r['results']], ['mismatch'] * 3)
            self.assertEqual(batch.record(self.plan, self.report, self.review, self.ledger, JANET), 0)
        self.assertEqual(len(Ledger.read(self.ledger).active_results()), 3)

    def test_changed_report_or_current_case_revision_is_rejected(self):
        batch.admit(self.plan, self.review, self.ledger)
        with patch.object(batch, 'run_model', side_effect=self.fake_output):
            batch.execute(self.plan, self.report, self.review, self.ledger, JANET)
            changed = load(self.report); changed['uses-runtime-build-data'] = True
            self.report.write_text(json.dumps(changed))
            with self.assertRaises(ValueError):
                batch.record(self.plan, self.report, self.review, self.ledger, JANET)
        selected = self.bundle['plans'][0]['case']
        append(self.ledger, [event('annotation', case=selected, source='f' * 64,
                                   reason='New shield evidence', changes={'blockers': ['shield']})])
        with self.assertRaises(ValueError): batch.validate(self.plan, self.review, self.ledger)

    @unittest.skipUnless(JANET.exists(), 'Optional local production Janet runtime')
    def test_real_production_batch_and_deterministic_reimport(self):
        batch.admit(self.plan, self.review, self.ledger)
        report = batch.execute(self.plan, self.report, self.review, self.ledger, JANET)
        self.assertEqual(len(report['results']), 3)
        self.assertEqual(len(report['blocked']), 1)
        self.assertEqual(report['cost']['raw-replay-reads'], 0)
        self.assertEqual(len(Ledger.read(self.ledger).active_results()), 3)
        self.assertEqual(batch.record(self.plan, self.report, self.review, self.ledger, JANET), 0)


if __name__ == '__main__':
    unittest.main()
