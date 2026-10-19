"""Prepare, admit, execute and record one reviewed conditional damage check.

Uses the production Janet damage functions. Snapshot means a content-addressed
observed-input context here, explicitly not a runtime champion/build package.
"""
import argparse
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import time

from jdn import dumps
from replay_coverage import (DEFAULT_LEDGER, Ledger, append, event, identity, digest,
                             load, model_identity, require, sha)
from replay_first_hit_review import GAME, EVENT
from replay_gaps import SEMANTIC_GAPS
from replay_state import derived_stats

ROOT = Path(__file__).resolve().parents[1]
REVIEWS = ROOT / 'observations/replays'
POLICY = ROOT / 'observations/verification/conditional-physical-fp32-policy.json'
RUNNER = ROOT / 'scripts/replay_conditional_model.janet'
CASE = GAME + ':' + EVENT
OBLIGATIONS = ['ordinary-physical', 'positive-armor']


def save_new(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x') as handle:
        handle.write(json.dumps(value, indent=2, allow_nan=False) + '\n')


def tolerance(ad):
    require(type(ad) in (int, float) and math.isfinite(ad) and 1 <= ad <= 1e6,
            'AD outside bounded float32 tolerance domain')
    policy = load(POLICY)
    require(policy['id'] == 'positive-armor-fp32-v1' and policy['rounding-stages'] == 4
            and policy['unit-roundoff'] == 2 ** -24, 'Unreviewed tolerance policy')
    bits = struct.unpack('<I', struct.pack('<f', ad))[0]
    ulp = struct.unpack('<f', struct.pack('<I', bits + 1))[0] - struct.unpack('<f', struct.pack('<I', bits))[0]
    nu = policy['rounding-stages'] * policy['unit-roundoff']
    return (nu / (1 - nu)) * ad + ulp / 2


def reviewed_context(reviews=REVIEWS):
    names = ['first-hit-final-review-2026-10-18.json', 'first-hit-amount-review-2026-10-18.json',
             'first-hit-effect-review-2026-10-18.json', 'first-hit-review-2026-10-18.json']
    paths = [Path(reviews) / n for n in names]
    final, amount, effect, first = [load(p) for p in paths]
    for report in (final, amount, effect, first):
        require(report['replay-sha256'] == GAME and report['event-id'] == EVENT
                and report['client-build'] == first['client-build'], 'Review case/build mismatch')
        for name, expected in report.get('adapters', {}).items():
            require(Path(name).name == name and digest(ROOT / 'scripts' / name) == expected,
                    'Review adapter revision mismatch')
    require(final['inputs']['amount-review'] == digest(paths[1])
            and amount['inputs']['effect-review'] == digest(paths[2])
            and effect['inputs']['first-review'] == digest(paths[3]), 'Review chain fingerprint mismatch')
    require(first['reviewer-adapter-sha256'] == digest(ROOT / 'scripts/replay_first_hit_review.py')
            and effect['reviewer-adapter-sha256'] == digest(ROOT / 'scripts/replay_effect_review.py'),
            'Semantic review revision mismatch')
    require(final['layer'] == 'conditional-damage' and final['ready-for-conditional-comparison'] is True
            and final['remaining-semantic-blockers'] == []
            and set(final['cumulative-resolved-semantic-blockers']) == set(SEMANTIC_GAPS),
            'All six conditional observation gates must be reviewed')
    require(final['sampling-review']['observations']['observed-stable'] is True,
            'Conditional input interval changed')
    scalar = {(r['role'], r['field']): r['before-action']['value']
              for r in final['sampling-review']['observations']['fields']}
    require(len(scalar) == 11, 'Missing or duplicate scalar input')
    source = {field: {'value': value} for (role, field), value in scalar.items() if role == 'source'}
    ad = derived_stats(source)['attack-damage']['value']
    require(scalar['source', 'crit-chance'] == scalar['source', 'physical-lethality']
            == scalar['source', 'flat-armor-penetration'] == 0
            and scalar['source', 'armor-remaining-fraction']
            == scalar['source', 'bonus-armor-remaining-fraction'] == 1
            and 0 < scalar['target', 'armor'] <= 1e6, 'Outside ordinary zero-penetration positive-armor domain')
    packet = first['damage-outcome']
    require(packet['damage-type'] == 'physical' and packet['event-id'] == EVENT
            and packet['amount'] == amount['amount-review']['closure']['wire-damage'],
            'Observation metric differs from reviewed native packet')
    inputs = {'source': {'ad': ad, 'crit-chance': 0, 'crit-damage': 2,
                         'armor-pen-flat': 0, 'armor-pen-percent': 0},
              'target': {'armor': scalar['target', 'armor'],
                         'armor-reduction-flat': 0, 'armor-reduction-percent': 0}}
    return final, packet, inputs, {p.name: digest(p) for p in paths}


def build_plan(state, model, reviews=REVIEWS):
    require(sha(model) and CASE in state.cases, 'Current model and imported case required')
    case = state.cases[CASE]
    final, packet, inputs, receipts = reviewed_context(reviews)
    annotation = state.annotations.get(CASE, {})
    require('sha256:' + receipts['first-hit-final-review-2026-10-18.json'] in annotation.get('reason', '')
            and annotation.get('ledger-record') == case.get('classification-revision'),
            'Final review receipt is not bound to the current ledger annotation')
    require(case['blockers'] == [] and case['numeric-ready'] is True
            and case['effect-kind'] == 'basic-attack-candidate'
            and case['recorded'] == packet['amount'] and case['event-id'] == EVENT
            and state.games[GAME]['build'] == final['client-build']
            and set(OBLIGATIONS) <= set(case['obligations']), 'Ledger case is not the reviewed ready observation')
    require(state.registry['client-build'] == final['client-build'] and state.registry['patch'] == '16.20.1',
            'Catalogue patch/build mismatch')
    context = {'format': 'powerspike-conditional-observed-inputs', 'version': 1,
               'case': CASE, 'case-state': identity(case), 'client-build': final['client-build'],
               'patch': state.registry['patch'], 'layer': 'conditional-damage',
               'inputs': inputs, 'review-receipts': receipts}
    evidence = {
        'packet-semantics': 'Amount and native outcome reviews: ' + receipts['first-hit-amount-review-2026-10-18.json'],
        'pre-hit-state': 'Six-gate conditional review: ' + receipts['first-hit-final-review-2026-10-18.json'],
        'actions': 'Causal ordinary noncritical attack review: ' + receipts['first-hit-review-2026-10-18.json'],
        'patch-data': 'Matching 16.20 sources pinned in semantic reviews; no runtime build data consumed.',
        'independent-oracle': 'Native packet plus independent health bracket and resource/API checks; amount review ' + receipts['first-hit-amount-review-2026-10-18.json']}
    return {'format': 'powerspike-conditional-comparison-plan', 'version': 1,
            'case': CASE, 'model': model, 'registry': state.registry_hash,
            'evidence-role': state.games[GAME]['role'],
            'snapshot': identity(context), 'snapshot-kind': 'reviewed-observed-scalars',
            'context': context, 'observed': packet['amount'],
            'tolerance': tolerance(inputs['source']['ad']), 'tolerance-policy': digest(POLICY),
            'adapter-sha256': digest(__file__), 'runner-sha256': digest(RUNNER),
            'obligations': OBLIGATIONS, 'evidence': evidence,
            'resolved-blockers': final['cumulative-resolved-semantic-blockers'],
            'encounter': 'opening-sion-ksante-exchange',
            'conditions': {**case['features'], 'attack-style': 'melee'},
            'scope': 'One conditional ordinary physical attack from reviewed observed scalars. Does not verify loadout/stat generation, critical outcomes, penetration, shields, sequences, or whole-model accuracy.',
            'uses-runtime-build-data': False}


def validate_plan(path, ledger, reviews=REVIEWS):
    state, plan = Ledger.read(ledger), load(path)
    require(identity(plan) == identity(build_plan(state, model_identity(), reviews)),
            'Plan differs from current model, policy, review receipts or case revision')
    return state, plan


def ledger_row(kind, plan, source, **extra):
    return event(kind, case=plan['case'], registry=plan['registry'], model=plan['model'],
                 snapshot=plan['snapshot'], observed=plan['observed'], tolerance=plan['tolerance'],
                 obligations=plan['obligations'], evidence=plan['evidence'],
                 **{'resolved-blockers': plan['resolved-blockers']},
                 encounter=plan['encounter'], conditions=plan['conditions'], source=source,
                 layer='conditional-damage', **{'snapshot-kind': plan['snapshot-kind']}, **extra)


def admit(path, ledger, reviews=REVIEWS):
    state, plan = validate_plan(path, ledger, reviews)
    row = ledger_row('admission', plan, digest(path))
    state.check_comparison(row)
    same = [r for r in state.active_admissions() if state.result_key(r) == state.result_key(row)]
    if same:
        require(same[0]['source'] == digest(path), 'A different recipe is already admitted')
        return 0
    return append(ledger, [row])


def run_model(plan, janet):
    # The runner receives no observed amount, tolerance, desired status or build.
    inputs = {'model': plan['model'], **plan['context']['inputs']}
    with tempfile.TemporaryDirectory(prefix='powerspike-conditional-') as folder:
        path = Path(folder) / 'inputs.jdn'; path.write_text(dumps(inputs))
        result = subprocess.run([str(Path(janet).resolve()), str(RUNNER), str(path)], cwd=ROOT,
            env={**os.environ, 'JANET_PATH': str(ROOT / 'build/web-modules')},
            text=True, capture_output=True, check=True, timeout=30)
    values = result.stdout.strip().split('\t')
    require(len(values) == 4 and values[0] == plan['model'], 'Production runner model/output mismatch')
    numbers = [float(v) for v in values[1:]]
    require(all(math.isfinite(v) and v >= 0 for v in numbers), 'Invalid production output')
    return {'model': values[0], 'raw': numbers[0], 'effective-resistance': numbers[1],
            'predicted': numbers[2]}


def outcome(plan, native):
    require(native['model'] == plan['model'], 'Wrong model prediction')
    predicted = native['predicted']
    require(type(predicted) in (int, float) and math.isfinite(predicted) and predicted >= 0,
            'Invalid model prediction')
    error = predicted - plan['observed']
    return {'predicted': predicted, 'observed': plan['observed'], 'error': error,
            'absolute-error': abs(error), 'tolerance': plan['tolerance'],
            'status': 'consistent' if abs(error) <= plan['tolerance'] else 'mismatch'}


def record_report(plan_path, report_path, ledger, janet, reviews=REVIEWS, reexecute=True):
    state, plan = validate_plan(plan_path, ledger, reviews)
    report = load(report_path)
    require(report.get('format') == 'powerspike-conditional-model-comparison' and report.get('version') == 1
            and report['plan-sha256'] == digest(plan_path)
            and report['adapter-sha256'] == digest(__file__)
            and report['runner-sha256'] == digest(RUNNER), 'Comparison report/recipe revision mismatch')
    require(all(report[key] == plan[key] for key in ('case', 'model', 'snapshot', 'snapshot-kind', 'evidence-role',
                                                    'obligations', 'conditions', 'scope'))
            and report['client-build'] == plan['context']['client-build']
            and report['patch'] == plan['context']['patch']
            and report['layer'] == 'conditional-damage' and report['uses-runtime-build-data'] is False
            and report['janet-sha256'] == digest(janet), 'Comparison metadata/runtime differs from the admitted recipe')
    admissions = [r for r in state.active_admissions() if state.result_key(r) ==
                  (plan['case'], plan['model'], plan['snapshot'], plan['registry'])]
    require(admissions and admissions[0]['source'] == digest(plan_path), 'Admit this exact recipe before execution')
    native = run_model(plan, janet) if reexecute else report['production-output']
    require(report['production-output'] == native and report['result'] == outcome(plan, native),
            'Report differs from production calculation or measurement policy')
    result = report['result']
    row = ledger_row('comparison', plan, digest(report_path), predicted=result['predicted'], status=result['status'])
    state.check_comparison(row)
    same = [r for r in state.active_results() if state.result_key(r) == state.result_key(row)]
    if same:
        require(all(same[0][k] == row[k] for k in ('predicted', 'observed', 'tolerance', 'status', 'obligations')),
                'Changed result requires explicit invalidation')
        return 0
    return append(ledger, [row])


def execute(plan_path, output, ledger, janet, reviews=REVIEWS):
    require(not Path(output).exists(), 'Choose a fresh comparison report path')
    state, plan = validate_plan(plan_path, ledger, reviews)
    require(any(r['source'] == digest(plan_path) and state.result_key(r) ==
                (plan['case'], plan['model'], plan['snapshot'], plan['registry'])
                for r in state.active_admissions()), 'Admit this exact recipe before execution')
    started = time.monotonic()
    native = run_model(plan, janet)
    report = {'format': 'powerspike-conditional-model-comparison', 'version': 1,
              'case': plan['case'], 'client-build': plan['context']['client-build'],
              'patch': plan['context']['patch'], 'layer': 'conditional-damage',
              'evidence-role': plan['evidence-role'],
              'model': plan['model'], 'snapshot': plan['snapshot'], 'snapshot-kind': plan['snapshot-kind'],
              'plan-sha256': digest(plan_path), 'adapter-sha256': digest(__file__),
              'runner-sha256': digest(RUNNER), 'janet-sha256': digest(janet),
              'production-output': native, 'result': outcome(plan, native),
              'obligations': plan['obligations'], 'conditions': plan['conditions'],
              'scope': plan['scope'], 'uses-runtime-build-data': False,
              'recorded-at': datetime.now(timezone.utc).isoformat(),
              'cost': {'wall-seconds': time.monotonic() - started, 'new-requests': 0, 'new-download-bytes': 0}}
    save_new(output, report)
    record_report(plan_path, output, ledger, janet, reviews, reexecute=False)
    append(ledger, [event('cost', category='compute', label='Production conditional damage execution',
                          seconds=report['cost']['wall-seconds'], lane='discovery')])
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ledger', type=Path, default=DEFAULT_LEDGER)
    parser.add_argument('--reviews', type=Path, default=REVIEWS)
    sub = parser.add_subparsers(dest='command', required=True)
    prepare = sub.add_parser('prepare'); prepare.add_argument('--output', type=Path, required=True)
    for name in ('admit', 'run', 'import'):
        command = sub.add_parser(name); command.add_argument('--plan', type=Path, required=True)
        if name != 'admit':
            command.add_argument('--output' if name == 'run' else '--report', type=Path, required=True)
            command.add_argument('--janet', type=Path, default=ROOT / 'build/janet')
    args = parser.parse_args()
    if args.command == 'prepare':
        plan = build_plan(Ledger.read(args.ledger), model_identity(), args.reviews)
        save_new(args.output, plan)
        print(json.dumps({'model': plan['model'], 'snapshot': plan['snapshot'], 'tolerance': plan['tolerance']}))
    elif args.command == 'admit': print(json.dumps({'appended-records': admit(args.plan, args.ledger, args.reviews)}))
    elif args.command == 'run': print(json.dumps(execute(args.plan, args.output, args.ledger, args.janet, args.reviews)['result']))
    else: print(json.dumps({'appended-records': record_report(args.plan, args.report, args.ledger, args.janet, args.reviews)}))


if __name__ == '__main__': main()
