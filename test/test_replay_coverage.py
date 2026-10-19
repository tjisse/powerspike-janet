"""Coverage credits evidence, preserves failures, and never manufactures trust."""
import copy
import gzip
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from replay_coverage import (Ledger, append, event, identity, load, digest, coverage_report,
                             export_review, import_reviews, import_comparison, import_context, import_attack_review,
                             context_case_state)

MODEL, SNAPSHOT, GAME = 'a' * 64, 'b' * 64, 'c' * 64


class CoverageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'ledger.jsonl'
        self.registry = load(ROOT / 'observations/verification/registry.json')
        append(self.path, [event('registry', registry=self.registry),
                           event('game', id=GAME, build=self.registry['client-build'], role='development')])
        self.case = event('case', id=GAME + ':gameChunk:4:10', game=GAME, **{'event-id': 'gameChunk:4:10'},
                          population='champion-to-champion', timestamp=10., recorded=10., actor='Sion', target='KSante',
                          features={'damage-type': 'physical', 'armor-band': 'low', 'resistance-band': 'low'},
                          **{'effect-kind': 'basic-attack-candidate', 'numeric-ready': True},
                          blockers=['identity', 'shields'], obligations=['ordinary-physical', 'positive-armor'])
        append(self.path, [self.case])

    def result(self, predicted=11, game=GAME, encounter='reviewed-exchange-1'):
        return event('comparison', case=game + ':gameChunk:4:10', registry=identity(self.registry),
                     model=MODEL, snapshot=SNAPSHOT, observed=10., predicted=predicted, tolerance=.01,
                     status='consistent' if abs(predicted - 10) <= .01 else 'mismatch',
                     obligations=['ordinary-physical', 'positive-armor'],
                     evidence={key: 'Independent observation source and locator' for key in
                               ['packet-semantics', 'pre-hit-state', 'actions', 'patch-data', 'independent-oracle']},
                     **{'resolved-blockers': ['identity', 'shields']}, encounter=encounter,
                     conditions={**self.case['features'], 'attack-style': 'melee'}, source='d' * 64)

    def report(self, model=MODEL):
        return coverage_report(Ledger.read(self.path), model)

    def test_retries_do_not_inflate_games_or_cases(self):
        self.assertEqual(append(self.path, [self.case]), 0)
        report = self.report()
        self.assertEqual(report['pipeline']['events'], 1)
        self.assertEqual(report['pipeline']['admitted'], 0)
        self.assertIsNone(report['agreement']['fraction'])
        self.assertEqual(report['coverage']['combat-total'], 27)
        self.assertIsNone(report['coverage']['overall-league-coverage'])

    def test_seven_provisional_fields_are_one_observed_snapshot_and_no_admission(self):
        path = ROOT / 'observations/replays/context-study-2026-10-18.json'
        self.assertEqual(import_context(path, self.path), 1)
        self.assertEqual(import_context(path, self.path), 0)
        report = self.report()
        self.assertEqual(report['diagnostics']['stat-checks'], 7)
        row = next(r for r in report['obligations'] if r['id'] == 'flat-loadout-stats')
        self.assertEqual(row['candidates'], 1)
        self.assertEqual(row['stage'], 'observed, provisional')
        self.assertEqual(report['coverage']['combat-checked'], 0)
        self.assertEqual(report['pipeline']['admitted'], 0)

    def test_action_context_progress_is_deduplicated_without_semantic_or_admission_credit(self):
        row = event('context-review', game=GAME, source='d' * 64,
                    build=self.registry['client-build'], admitted=False,
                    counts={'numeric-ready:unique-candidate': 1, 'numeric-ready:observed-stable': 1},
                    adapters={name: digest(ROOT / 'scripts' / name) for name in
                              ('replay_attack_review.py', 'replay_actions.py', 'replay_state.py')},
                    **{'decoded-actions': 10, 'decode-failures': 0, 'search-window-seconds': 2,
                       'case-state': context_case_state(Ledger.read(self.path), GAME)})
        self.assertEqual(append(self.path, [row]), 1)
        self.assertEqual(append(self.path, [row]), 0)
        report = self.report()
        self.assertEqual(report['diagnostics']['attack-context']['decoded-actions'], 10)
        self.assertEqual(report['pipeline']['admitted'], 0)
        self.assertEqual(report['coverage']['combat-checked'], 0)
        self.assertEqual(Ledger.read(self.path).cases[self.case['id']]['blockers'], ['identity', 'shields'])
        with self.assertRaises(ValueError):
            append(self.path, [event('context-review', **{**{k: v for k, v in row.items() if k not in ('kind', 'operation')}, 'admitted': True})])
        stale = {**row, 'source': 'e' * 64, 'adapters': {name: 'f' * 64 for name in row['adapters']}}
        append(self.path, [event('context-review', **{k: v for k, v in stale.items() if k not in ('kind', 'operation')})])
        self.assertEqual(self.report()['diagnostics']['attack-context']['decoded-actions'], 0)

    def test_context_import_checks_cases_receipts_counts_and_retry(self):
        folder = Path(self.temp.name) / 'context'; folder.mkdir()
        row = {'event-id': 'gameChunk:4:10', 'timestamp': 10., 'source': 1, 'target': 2,
               'action-candidates': [{'event-id': 'gameChunk:4:9', 'timestamp': 9.8,
                    'source': 1, 'target': 2, 'kind': 'basic-attack-announcement-candidate'}],
               'status': 'unique-candidate', 'model-admissible': False, 'resolved-semantic-blockers': [],
               'stat-continuity': {'observed-stable': True, 'server-sampling-resolved': False}}
        with gzip.open(folder / 'attack-context.jsonl.gz', 'wt') as handle:
            handle.write(json.dumps(row) + '\n')
        report = {'format': 'powerspike-replay-attack-review', 'version': 1,
                  'replay-sha256': GAME, 'client-build': self.registry['client-build'],
                  'model-admissible-cases': 0, 'resolved-semantic-blockers': [],
                  'candidate-search-window-seconds': 2, 'action-packets-decoded': 10, 'action-failures': 0,
                  'counts': {k: 1 for k in ('ordinary-candidates', 'unique-candidate', 'numeric-ready',
                             'numeric-ready:unique-candidate', 'observed-stable', 'numeric-ready:observed-stable')},
                  'adapters': {name: digest(ROOT / 'scripts' / name) for name in
                               ('replay_attack_review.py', 'replay_actions.py', 'replay_state.py')},
                  'evidence-files': {'attack-context.jsonl.gz': digest(folder / 'attack-context.jsonl.gz')}}
        path = folder / 'summary.json'; path.write_text(json.dumps(report))
        self.assertEqual(import_attack_review(folder, self.path), 1)
        self.assertEqual(import_attack_review(folder, self.path), 0)
        self.assertEqual(self.report()['pipeline']['admitted'], 0)
        append(self.path, [event('annotation', case=self.case['id'], source='f' * 64,
                    reason='New evidence corrects numerical readiness', changes={'numeric-ready': False})])
        self.assertEqual(self.report()['diagnostics']['attack-context']['decoded-actions'], 0)
        report['counts']['ordinary-candidates'] = 2; path.write_text(json.dumps(report))
        with self.assertRaisesRegex(ValueError, 'Incomplete'): import_attack_review(folder, self.path)
        with (folder / 'attack-context.jsonl.gz').open('ab') as handle: handle.write(b'bad bytes')
        with self.assertRaisesRegex(ValueError, 'receipt'): import_attack_review(folder, self.path)

    def test_mismatch_adds_coverage_but_not_agreement_and_survives_new_model(self):
        append(self.path, [self.result()])
        report = self.report()
        self.assertEqual(report['coverage']['combat-checked'], 2)
        self.assertEqual(report['pipeline']['evaluated'], 1)
        self.assertEqual(report['agreement']['fraction'], 0)
        self.assertEqual(report['agreement']['mismatches'], 1)
        new = self.report('e' * 64)
        self.assertEqual(new['coverage']['combat-checked'], 0)
        self.assertEqual(new['history']['all-revision-mismatches'], 1)
        self.assertEqual(new['history']['outside-current-view'], 1)

    def test_all_blockers_and_independent_evidence_are_required(self):
        for mutation in ('blocker', 'oracle', 'substitute', 'wrong-status', 'wrong-condition', 'wrong-obligation'):
            row = self.result()
            if mutation == 'blocker': row['resolved-blockers'] = ['identity']
            elif mutation == 'oracle': row['evidence'].pop('independent-oracle')
            elif mutation == 'substitute': row['observed'] = 11
            elif mutation == 'wrong-status': row['status'] = 'consistent'
            elif mutation == 'wrong-condition': row['conditions']['armor-band'] = 'high'
            else: row['obligations'] = ['attack-cadence']
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                append(self.path, [row])
        self.assertEqual(self.report()['pipeline']['admitted'], 0)

    def test_tampering_and_partial_transactions_are_detected(self):
        before = self.path.read_bytes()
        valid = event('cost', category='review', label='Actual review', seconds=30)
        invalid = self.result(); invalid['observed'] = 99
        with self.assertRaises(ValueError): append(self.path, [valid, invalid])
        self.assertEqual(self.path.read_bytes(), before)
        self.path.write_bytes(before.replace(b'Sion', b'Garen'))
        with self.assertRaisesRegex(ValueError, 'integrity'): Ledger.read(self.path)
        self.path.write_bytes(before[:-1])
        with self.assertRaisesRegex(ValueError, 'Truncated'): Ledger.read(self.path)

    def test_explicit_invalidation_retains_failed_history(self):
        append(self.path, [self.result()])
        original = Ledger.read(self.path).results[0]
        replacement = self.result(10)
        with self.assertRaises(ValueError): append(self.path, [replacement])
        append(self.path, [event('invalidate', record=original['ledger-record'], reason='Incorrect source context; retained for investigation')])
        append(self.path, [replacement])
        report = self.report()
        self.assertEqual(report['agreement']['mismatches'], 0)
        self.assertEqual(report['history']['all-revision-mismatches'], 1)
        self.assertEqual(report['history']['invalidated'], 1)

    def test_resource_only_costs_preserve_unknown_duration(self):
        append(self.path, [event('cost', category='maintenance', label='Public asset bytes', bytes=100, requests=2),
                           event('cost', category='review', label='Review receipt storage', bytes=20),
                           event('cost', category='compute', label='Measured execution', seconds=3)])
        resources = self.report()['resources']
        self.assertIsNone(resources['recorded-seconds']['maintenance'])
        self.assertIsNone(resources['recorded-seconds']['review'])
        self.assertEqual(resources['recorded-seconds']['compute'], 3)
        self.assertEqual(resources['recorded-bytes'], 120)
        self.assertEqual(resources['recorded-requests'], 2)
        self.assertIsNone(resources['audit-review-fraction'])

    def test_catalogue_change_requires_revision_and_stales_old_results(self):
        append(self.path, [self.result()])
        registry = copy.deepcopy(self.registry)
        registry['scope-note'] += ' Changed scope.'
        with self.assertRaisesRegex(ValueError, 'revision'):
            append(self.path, [event('registry', registry=registry)])
        registry['revision'] = 'plan-2'
        append(self.path, [event('registry', registry=registry)])
        self.assertEqual(self.report()['coverage']['combat-checked'], 0)
        self.assertEqual(self.report()['history']['all-revision-mismatches'], 1)

    def test_fresh_games_require_prior_freeze_and_cannot_relabel_development(self):
        audit_game = 'f' * 64
        freeze = event('freeze', id='frozen-model', model=MODEL, registry=identity(self.registry),
                       **{'selection-policy': 'Random whole-game selection, seed 123, pool receipt retained'})
        with self.assertRaises(ValueError):
            append(self.path, [event('game', id=audit_game, build=self.registry['client-build'], role='audit',
                                    freeze='missing', **{'selection-receipt': 'pool hash and sampled game'})])
        append(self.path, [freeze])
        with self.assertRaises(ValueError):
            append(self.path, [event('game', id=GAME, build=self.registry['client-build'], role='audit',
                                    freeze='frozen-model', **{'selection-receipt': 'Cannot relabel old game'})])
        append(self.path, [event('game', id=audit_game, build=self.registry['client-build'], role='audit',
                                freeze='frozen-model', **{'selection-receipt': 'pool and seed 123'})])
        case = {k: v for k, v in self.case.items() if k != 'operation'}
        case['game'], case['id'] = audit_game, audit_game + ':gameChunk:4:10'
        append(self.path, [event('case', **{k: v for k, v in case.items() if k != 'kind'})])
        append(self.path, [self.result(10, game=audit_game)])
        self.assertEqual(self.report()['audit']['fresh-evaluated-games'], 1)
        append(self.path, [event('development', game=audit_game, reason='Used result to tune the next model')])
        self.assertEqual(self.report()['audit']['reserved-games'], 0)
        # Its original frozen result remains historically valid for that model.
        self.assertEqual(self.report()['audit']['fresh-evaluated-games'], 1)

    def test_repeated_hits_cannot_satisfy_diversity_or_invent_interactions(self):
        append(self.path, [self.result(10)])
        row = next(r for r in self.report()['obligations'] if r['id'] == 'ordinary-physical')
        self.assertEqual(row['stage'], 'checked')
        self.assertEqual(row['games'], 1)
        self.assertEqual(self.report()['interactions'][0]['checked'], 1)
        self.assertEqual(self.report()['interactions'][1]['checked'], 0)

    def test_shared_blockers_are_one_bundle_with_no_fabricated_cost(self):
        queue = self.report()['next-unlocks']
        self.assertEqual(len(queue), 1)
        self.assertEqual(queue[0]['candidates'], 1)
        self.assertEqual(queue[0]['blockers'], ['identity', 'shields'])
        self.assertIsNone(queue[0]['estimated-review-hours'])
        append(self.path, [event('work-estimate', blockers=['identity', 'shields'], hours=2., rationale='Measured prototype review estimate')])
        self.assertEqual(self.report()['next-unlocks'][0]['estimated-obligations-per-hour'], 1.)
        self.assertIsNone(self.report()['resources']['recorded-seconds']['review'])

    def review_files(self):
        directory = Path(self.temp.name) / 'review'
        export_review(Ledger.read(self.path), self.case['id'], directory)
        reviews = load(directory / 'reviews.json')
        review = reviews['cases'][0]
        review.update({'reviewed': True, 'mechanic': 'ordinary-physical', 'required-source': 'SionBasicAttack',
                       'tolerance': .01, 'scenario-document': {'scenario': {
                           'patch': '16.20.1', 'model': MODEL, 'snapshot': SNAPSHOT, 'samples': 1}}})
        review['evidence'] = {key: 'Independent evidence with source and time' for key in review['evidence']}
        review['verification'].update({'independent-oracle': 'Isolated health loss with independent packet/context review',
                                       'resolved-blockers': self.case['blockers'], 'encounter': 'one-isolated-exchange'})
        (directory / 'reviews.json').write_text(json.dumps(reviews))
        return directory

    def test_review_admission_and_evaluation_are_separate_gates(self):
        directory = self.review_files()
        self.assertEqual(import_reviews(directory / 'events.json', directory / 'reviews.json', self.path), 1)
        self.assertEqual(import_reviews(directory / 'events.json', directory / 'reviews.json', self.path), 0)
        report = self.report()
        self.assertEqual(report['pipeline']['admitted'], 1)
        self.assertEqual(report['pipeline']['evaluated'], 0)
        self.assertEqual(report['pending-evaluations'], 1)
        self.assertEqual(report['next-unlocks'], [])
        self.assertEqual(report['coverage']['combat-checked'], 0)

    def test_context_corrections_are_append_only_and_invalidate_old_credit(self):
        append(self.path, [self.result(10)])
        change = event('annotation', case=self.case['id'], source='e' * 64,
                       reason='Independent stat sampling evidence corrects the provisional armor band',
                       changes={'features': {'damage-type': 'physical', 'armor-band': 'medium', 'resistance-band': 'medium'}})
        append(self.path, [change])
        report = self.report()
        self.assertEqual(report['coverage']['combat-checked'], 0)
        self.assertEqual(report['history']['comparisons'], 1)
        self.assertEqual(report['history']['invalidated'], 1)
        with self.assertRaises(ValueError):
            append(self.path, [event('annotation', case=self.case['id'], source='f' * 64,
                                    reason='Cannot replace observed damage', changes={'recorded': 99})])

    def test_import_commit_marker_prevents_partial_corpus_reporting(self):
        # Simulate an interrupted source import: a complete case line can exist
        # without the final source-count receipt. It must not become the denominator.
        case = {k: v for k, v in self.case.items() if k not in ('operation', 'kind')}
        case.update({'id': GAME + ':gameChunk:4:20', 'event-id': 'gameChunk:4:20', 'source': 'd' * 64})
        append(self.path, [event('case', **case)])
        with self.assertRaisesRegex(ValueError, 'Incomplete ledger import'): self.report()
        with self.assertRaises(ValueError):
            append(self.path, [event('case-import', game=GAME, source='d' * 64, cases=1)])
        append(self.path, [event('case-import', game=GAME, source='d' * 64, cases=2)])
        self.assertEqual(self.report()['pipeline']['events'], 2)

    def test_comparison_receipts_and_retries_bind_actual_measurement(self):
        directory = self.review_files()
        events, reviews = directory / 'events.json', directory / 'reviews.json'
        report_path = directory / 'comparison.json'
        row = {'event-id': self.case['event-id'], 'replay-sha256': GAME, 'client-build': self.registry['client-build'],
               'checked': True, 'model': MODEL, 'snapshot': SNAPSHOT, 'patch': '16.20.1',
               'observed': 10., 'predicted': 11., 'tolerance': .01, 'status': 'mismatch'}
        report = {'format': 'powerspike-replay-comparison', 'version': 1,
                  'adapter-sha256': digest(ROOT / 'scripts/replays.py'), 'events-sha256': digest(events),
                  'reviews-sha256': digest(reviews), 'rows': [row]}
        report_path.write_text(json.dumps(report))
        self.assertEqual(import_comparison(report_path, events, reviews, self.path), 1)
        self.assertEqual(import_comparison(report_path, events, reviews, self.path), 0)
        row['observed'] = 11
        report_path.write_text(json.dumps(report))
        with self.assertRaises(ValueError): import_comparison(report_path, events, reviews, self.path)
        reviews.write_text(reviews.read_text() + ' ')
        with self.assertRaisesRegex(ValueError, 'fingerprints'): import_comparison(report_path, events, reviews, self.path)


if __name__ == '__main__':
    unittest.main()
