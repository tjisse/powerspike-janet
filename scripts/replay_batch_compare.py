"""Freeze, admit, execute and record the reviewed indexed comparison batch.

Uses the same production runner and predeclared float32 policy as the first hit.
Blocked cases never enter the runner. Observations/tolerances are not sent to it.
"""
import argparse
import copy
from datetime import datetime, timezone
from pathlib import Path
import time

from replay_batch_review import CASES, GAME, SCOPE, ROOT
from replay_conditional_compare import (POLICY, RUNNER, ledger_row, outcome,
                                        run_model, save_new, tolerance)
from replay_coverage import (DEFAULT_LEDGER, Ledger, append, digest, event,
                             identity, load, model_identity, require)
from replay_gaps import SEMANTIC_GAPS
from replay_state import derived_stats

REVIEW = ROOT / 'observations/replays/batch-conditional-review-2026-10-18.json'


def checked_review(path):
    report = load(path)
    require(report.get('format') == 'powerspike-indexed-batch-conditional-review'
            and report['version'] == 1 and report['replay-sha256'] == GAME
            and report['scope'] == SCOPE and report['patch'] == '16.20.1', 'Wrong batch review scope')
    require(len(report['cases']) == len(CASES) and {r['event-id'] for r in report['cases']} == set(CASES),
            'Batch review differs from frozen case selection')
    for name, expected in report['adapters'].items():
        require(Path(name).name == name and digest(ROOT / 'scripts' / name) == expected,
                'Batch review adapter revision mismatch')
    for row in report['cases']:
        if row['ready-for-conditional-comparison'] is True:
            require(row['remaining-semantic-blockers'] == [] and set(row['resolved-semantic-blockers']) == set(SEMANTIC_GAPS)
                    and row['health-measurement']['isolated'] is True and row['health-measurement']['closes'] is True
                    and row['health-measurement']['nonlethal'] is True and row.get('mechanic-review')
                    and row['sampling-observations']['observed-stable'] is True,
                    'Unreviewed or blocked case cannot be compared')
    return report


def make_plan(state, row, review, review_sha, model):
    case_id = row['case']; case = state.cases[case_id]
    annotation = state.annotations.get(case_id, {})
    require(case['blockers'] == [] and case['numeric-ready'] is True
            and case['effect-kind'] == 'basic-attack-candidate'
            and case['recorded'] == row['health-measurement']['wire-damage']
            and annotation.get('source') == review_sha
            and annotation.get('ledger-record') == case['classification-revision'], 'Review is not bound to current ledger case')
    require(state.registry['client-build'] == review['client-build']
            and state.registry['patch'] == review['patch'], 'Registry patch/build mismatch')
    scalar = {(r['role'], r['field']): r['before-action']['value'] for r in row['sampling-observations']['fields']}
    require(len(scalar) == 11 and all(type(v) in (int, float) for v in scalar.values()), 'Missing or mistyped observed scalar')
    require(all(scalar['source', k] == 0 for k in ('crit-chance', 'flat-armor-penetration', 'physical-lethality'))
            and all(scalar['source', k] == 1 for k in ('armor-remaining-fraction', 'bonus-armor-remaining-fraction'))
            and 0 < scalar['target', 'armor'] <= 1e6, 'Outside ordinary positive-armor scope')
    ad = derived_stats({k: {'value': v} for (role, k), v in scalar.items() if role == 'source'})['attack-damage']['value']
    inputs = {'source': {'ad': ad, 'crit-chance': 0, 'crit-damage': 2, 'armor-pen-flat': 0, 'armor-pen-percent': 0},
              'target': {'armor': scalar['target', 'armor'], 'armor-reduction-flat': 0, 'armor-reduction-percent': 0}}
    context = {'format': 'powerspike-conditional-observed-inputs', 'version': 1, 'case': case_id,
               'case-state': identity(case), 'client-build': review['client-build'], 'patch': review['patch'],
               'layer': 'conditional-damage', 'inputs': inputs, 'review-sha256': review_sha,
               'package-file-sha256': row['package-file-sha256'], 'evidence-sha256': row['evidence-sha256']}
    evidence = {k: f'Case-specific six-gate review sha256:{review_sha}, event {row["event-id"]}' for k in
                ('packet-semantics', 'pre-hit-state', 'actions', 'patch-data', 'independent-oracle')}
    return {'case': case_id, 'model': model, 'registry': state.registry_hash,
            'evidence-role': state.games[GAME]['role'], 'context': context, 'snapshot': identity(context),
            'snapshot-kind': 'reviewed-observed-scalars', 'observed': case['recorded'],
            'tolerance': tolerance(ad), 'tolerance-policy': digest(POLICY),
            'adapter-sha256': digest(__file__), 'runner-sha256': digest(RUNNER),
            'obligations': ['ordinary-physical', 'positive-armor'], 'evidence': evidence,
            'resolved-blockers': sorted(SEMANTIC_GAPS), 'encounter': 'indexed-review:' + row['event-id'],
            'conditions': {**case['features'], 'attack-style': 'ranged' if row['source'] == 'Tristana' else 'melee'},
            'scope': SCOPE, 'uses-runtime-build-data': False}


def bundle(state, review_path):
    review, review_sha = checked_review(review_path), digest(review_path)
    model = model_identity()
    return {'format': 'powerspike-indexed-comparison-plans', 'version': 1,
            'review-sha256': review_sha, 'adapter-sha256': digest(__file__),
            'plans': [make_plan(state, r, review, review_sha, model) for r in review['cases'] if r['ready-for-conditional-comparison']],
            'blocked': [{'case': r['case'], 'event-id': r['event-id'], 'reason': r['reason'],
                         'remaining-semantic-blockers': r['remaining-semantic-blockers']}
                        for r in review['cases'] if not r['ready-for-conditional-comparison']]}


def prepare(review_path, output, ledger):
    require(not Path(output).exists(), 'Choose a fresh plan bundle path')
    review, state = checked_review(review_path), Ledger.read(ledger)
    review_sha = digest(review_path)
    rows = []
    for r in review['cases']:
        require(r['case'] in state.cases, 'Import selected replay cases first')
        old = state.annotations.get(r['case'], {})
        if old.get('source') == review_sha and state.cases[r['case']]['blockers'] == r['remaining-semantic-blockers']:
            continue
        rows.append(event('annotation', case=r['case'], source=review_sha,
                          reason=r['reason'] + ' Review sha256:' + review_sha,
                          changes={'blockers': r['remaining-semantic-blockers']}))
    # The ledger validates the complete transaction before appending it.
    preview = copy.deepcopy(state)
    for row in rows:
        preview.apply(row, identity(row))
    proposed = bundle(preview, review_path)
    require(proposed['plans'], 'No reviewed comparisons in this batch')
    for p in proposed['plans']:
        preview.check_comparison(ledger_row('admission', p, '0' * 64))
    append(ledger, rows)
    result = bundle(Ledger.read(ledger), review_path)
    require(result['plans'], 'No reviewed comparisons in this batch')
    save_new(output, result)
    return result


def validate(plan_path, review_path, ledger):
    state = Ledger.read(ledger)
    actual = load(plan_path)
    require(identity(actual) == identity(bundle(state, review_path)),
            'Plan bundle differs from model, review, tolerance policy or current case revision')
    return state, actual


def admit(plan_path, review_path, ledger):
    state, plans = validate(plan_path, review_path, ledger)
    rows = []
    for p in plans['plans']:
        row = ledger_row('admission', p, digest(plan_path))
        state.check_comparison(row)
        existing = [r for r in state.active_admissions() if state.result_key(r) == state.result_key(row)]
        if existing:
            require(existing[0]['source'] == digest(plan_path), 'Different admitted recipe already exists')
        else:
            rows.append(row)
    return append(ledger, rows)


def admission_check(state, plan_path, p):
    require(any(state.result_key(r) == (p['case'], p['model'], p['snapshot'], p['registry'])
                and r['source'] == digest(plan_path) for r in state.active_admissions()),
            'Admit this exact batch before model execution')


def record(plan_path, report_path, review_path, ledger, janet, reexecute=True):
    state, plans = validate(plan_path, review_path, ledger)
    report = load(report_path)
    require(report.get('format') == 'powerspike-indexed-model-comparisons' and report['version'] == 1
            and report['plan-sha256'] == digest(plan_path) and report['review-sha256'] == digest(review_path)
            and report['adapter-sha256'] == digest(__file__) and report['runner-sha256'] == digest(RUNNER)
            and report['janet-sha256'] == digest(janet) and report['blocked'] == plans['blocked']
            and report['client-build'] == state.registry['client-build'] and report['patch'] == state.registry['patch']
            and report['layer'] == 'conditional-damage' and report['snapshot-kind'] == 'reviewed-observed-scalars'
            and report['uses-runtime-build-data'] is False and report['scope'] == SCOPE
            and len(report['results']) == len(plans['plans']), 'Comparison bundle metadata/receipts mismatch')
    rows = []
    for p, saved in zip(plans['plans'], report['results']):
        admission_check(state, plan_path, p)
        native = run_model(p, janet) if reexecute else saved['production-output']
        require(saved['case'] == p['case'] and saved['snapshot'] == p['snapshot']
                and saved['model'] == p['model'] and saved['conditions'] == p['conditions']
                and saved['obligations'] == p['obligations'] and saved['evidence-role'] == p['evidence-role']
                and saved['scope'] == p['scope'] and saved['production-output'] == native
                and saved['result'] == outcome(p, native), 'Comparison differs from admitted production calculation')
        row = ledger_row('comparison', p, digest(report_path), predicted=native['predicted'], status=saved['result']['status'])
        state.check_comparison(row)
        existing = [r for r in state.active_results() if state.result_key(r) == state.result_key(row)]
        if existing:
            require(all(existing[0][k] == row[k] for k in ('predicted', 'observed', 'tolerance', 'status', 'obligations')),
                    'Changed result requires explicit invalidation')
        else:
            rows.append(row)
    return append(ledger, rows)


def execute(plan_path, output, review_path, ledger, janet):
    require(not Path(output).exists(), 'Choose a fresh comparison report path')
    state, plans = validate(plan_path, review_path, ledger)
    for p in plans['plans']: admission_check(state, plan_path, p)
    started = time.monotonic()
    results = []
    for p in plans['plans']:
        native = run_model(p, janet)
        results.append({k: p[k] for k in ('case', 'model', 'snapshot', 'conditions', 'obligations', 'evidence-role', 'scope')} |
                       {'production-output': native, 'result': outcome(p, native)})
    report = {'format': 'powerspike-indexed-model-comparisons', 'version': 1,
              'client-build': state.registry['client-build'], 'patch': state.registry['patch'],
              'layer': 'conditional-damage', 'snapshot-kind': 'reviewed-observed-scalars',
              'plan-sha256': digest(plan_path), 'review-sha256': digest(review_path),
              'adapter-sha256': digest(__file__), 'runner-sha256': digest(RUNNER), 'janet-sha256': digest(janet),
              'results': results, 'blocked': plans['blocked'], 'scope': SCOPE,
              'uses-runtime-build-data': False, 'recorded-at': datetime.now(timezone.utc).isoformat(),
              'cost': {'wall-seconds': time.monotonic() - started, 'raw-replay-reads': 0,
                       'source-archive-reads': 0, 'native-decode-calls': 0, 'new-requests': 0}}
    save_new(output, report)
    added = record(plan_path, output, review_path, ledger, janet, reexecute=False)
    if added:
        append(ledger, [event('cost', category='compute', label='Indexed production conditional batch comparison',
                              seconds=report['cost']['wall-seconds'], lane='discovery')])
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ledger', type=Path, default=DEFAULT_LEDGER)
    parser.add_argument('--review', type=Path, default=REVIEW)
    sub = parser.add_subparsers(dest='command', required=True)
    cmd = sub.add_parser('prepare'); cmd.add_argument('--output', required=True, type=Path)
    for name in ('admit', 'run', 'import'):
        cmd = sub.add_parser(name); cmd.add_argument('--plan', type=Path, required=True)
        if name != 'admit':
            cmd.add_argument('--output' if name == 'run' else '--report', type=Path, required=True)
            cmd.add_argument('--janet', type=Path, default=ROOT / 'build/janet')
    args = parser.parse_args()
    if args.command == 'prepare':
        r = prepare(args.review, args.output, args.ledger)
        print({'planned': len(r['plans']), 'blocked': len(r['blocked'])})
    elif args.command == 'admit': print({'appended-records': admit(args.plan, args.review, args.ledger)})
    elif args.command == 'run':
        r = execute(args.plan, args.output, args.review, args.ledger, args.janet)
        print({'results': [x['result'] for x in r['results']], 'blocked': len(r['blocked'])})
    else: print({'appended-records': record(args.plan, args.report, args.review, args.ledger, args.janet)})
