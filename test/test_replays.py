"""Synthetic replay evidence tests. These do not establish game accuracy."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import replays


def evidence():
    event = {'event-id': 'gameChunk:1:12', 'replay-sha256': 'a' * 64,
             'client-build': '16.14.794.5912', 'fields': {'damageAmount': 50, 'damageType': 'physical'}}
    definition = {'patch': '16.14.1', 'snapshot': 'b' * 64, 'model': 'c' * 64, 'samples': 1}
    case = {'event-id': event['event-id'], 'replay-sha256': event['replay-sha256'],
            'client-build': event['client-build'], 'reviewed': True, 'mechanic': 'ordinary-attack',
            'required-source': 'attack', 'tolerance': .01,
            'evidence': {key: 'synthetic test evidence' for key in
                         ('packet-semantics', 'pre-hit-state', 'actions', 'patch-data')},
            'scenario-document': {'scenario': definition}}
    outcome = {'scenario': definition.copy(), 'unsupported': [], 'samples': 1,
               'trace': [{'kind': 'damage', 'source': 'attack', 'damage': 50,
                          'type': 'physical', 'absorbed': 0, 'health': 100}]}
    return event, case, outcome


class ReplayTests(unittest.TestCase):
    def test_random_selection_is_reproducible_and_order_independent(self):
        source = replays.source_by_id('rofllens-v0.1.0')
        selected, names = replays.select_sample(source, 1829709103)
        self.assertEqual(selected['filename'], 'KR_8305643709.rofl')
        self.assertEqual(len(names), 5)
        source['samples'].reverse()
        self.assertEqual((selected, names), replays.select_sample(source, 1829709103))

    def test_reject_path_traversal_and_duplicate_sources(self):
        for samples in [[{'filename': '../bad.rofl'}], [{'filename': 'a'}, {'filename': 'a'}]]:
            with self.assertRaises(ValueError):
                replays.select_sample({'samples': samples}, 1)

    def test_corrupt_download_never_becomes_an_observation(self):
        from io import BytesIO
        source = {'samples': [{'filename': 'a.rofl', 'url': 'https://example.invalid/a',
                              'bytes': 3, 'sha256': hashlib.sha256(b'abc').hexdigest()}]}
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'download'
            with patch.object(replays.urllib.request, 'urlopen', return_value=BytesIO(b'bad')):
                with self.assertRaisesRegex(ValueError, 'SHA-256'):
                    replays.fetch(source, 1, output, 10)
            self.assertEqual(list(output.iterdir()), [])

    def test_contribution_preserves_bytes_and_is_not_a_random_sample(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'original.rofl').write_bytes(b'synthetic replay')
            (root / 'client.exe').write_bytes(b'synthetic client')
            header = {'clientVersion': '16.14.794.5912', 'protocolDigest': 'test-protocol'}
            with patch.object(replays, 'replay_header', return_value=header):
                result = replays.import_local(root / 'original.rofl', 'test contribution',
                                             root / 'client.exe', root / 'copy', 1024)
            self.assertEqual((root / 'copy/contributed.rofl').read_bytes(), b'synthetic replay')
            self.assertEqual(result['sample']['sha256'], replays.sha256(root / 'original.rofl'))
            self.assertIsNone(result['seed'])
            self.assertEqual(result['client-build'], header['clientVersion'])

    def test_oversized_sample_is_not_reselected_to_bias_the_corpus(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(replays.urllib.request, 'urlopen') as download:
                with self.assertRaisesRegex(ValueError, 'budget'):
                    replays.fetch({'samples': [{'filename': 'a', 'bytes': 100}]},
                                  1, Path(directory) / 'sample', 10)
                download.assert_not_called()

    def test_unreviewed_and_missing_state_cannot_count_as_checks(self):
        event, case, _ = evidence()
        self.assertIsNone(replays.prepare_case(event, case))
        case['reviewed'] = False
        self.assertEqual(replays.prepare_case(event, case), 'unreviewed')
        case['reviewed'] = True
        case['evidence']['pre-hit-state'] = None
        self.assertEqual(replays.prepare_case(event, case), 'missing-review-evidence')

    def test_replay_build_patch_and_trial_must_match(self):
        event, case, _ = evidence()
        case['client-build'] = '16.14.other'
        self.assertEqual(replays.prepare_case(event, case), 'evidence-identity-mismatch')
        case['client-build'] = event['client-build']
        case['scenario-document']['scenario']['patch'] = '16.19.1'
        self.assertEqual(replays.prepare_case(event, case), 'patch-mismatch')
        case['scenario-document']['scenario']['patch'] = '16.14.1'
        case['scenario-document']['scenario']['samples'] = 8
        self.assertEqual(replays.prepare_case(event, case), 'single-observed-hit-requires-one-trial')

    def test_missing_or_nonfinite_measurements_are_never_zero(self):
        for value in [None, True, float('nan'), float('inf'), -1]:
            event, case, _ = evidence()
            event['fields']['damageAmount'] = value
            self.assertEqual(replays.prepare_case(event, case), 'invalid-measurement-or-tolerance')

    def test_consistency_and_mismatch_use_recorded_amount(self):
        event, case, outcome = evidence()
        self.assertEqual(replays.compare_outcome(event, case, outcome)['status'], 'consistent')
        outcome['trace'][0]['damage'] = 49
        result = replays.compare_outcome(event, case, outcome)
        self.assertEqual(result['status'], 'mismatch')
        self.assertEqual(result['observed'], 50)
        self.assertEqual(result['error'], -1)

    def test_ambiguous_effects_trials_and_model_changes_are_not_coverage(self):
        event, case, outcome = evidence()
        variants = []
        changed = copy.deepcopy(outcome)
        changed['scenario']['model'] = 'new-model'
        variants.append(changed)
        changed = copy.deepcopy(outcome)
        changed['unsupported'] = ['unimplemented effect']
        variants.append(changed)
        changed = copy.deepcopy(outcome)
        changed['trace'] *= 2
        variants.append(changed)
        for field, value in [('source', 'different-spell'), ('absorbed', 10), ('health', 0), ('type', 'magic')]:
            changed = copy.deepcopy(outcome)
            changed['trace'][0][field] = value
            variants.append(changed)
        for changed in variants:
            self.assertFalse(replays.compare_outcome(event, case, changed)['checked'])

    def test_empty_reviews_report_zero_coverage_without_launching_model(self):
        event, _, _ = evidence()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            replays.save(root / 'events.json', {'format': 'powerspike-replay-events', 'version': 1, 'events': [event]})
            replays.save(root / 'reviews.json', {'format': 'powerspike-replay-reviews', 'version': 1, 'cases': []})
            with patch.object(replays.subprocess, 'run') as run:
                report = replays.compare(root / 'events.json', root / 'reviews.json', 'absent', root / 'report.json')
                run.assert_not_called()
            self.assertEqual(report['coverage']['verified-comparisons'], 0)
            self.assertEqual(report['coverage']['unsubmitted-events'], 1)

    def test_duplicate_reviews_cannot_inflate_coverage(self):
        event, case, _ = evidence()
        case['reviewed'] = False
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            replays.save(root / 'events.json', {'format': 'powerspike-replay-events', 'version': 1, 'events': [event]})
            replays.save(root / 'reviews.json', {'format': 'powerspike-replay-reviews', 'version': 1, 'cases': [case, case]})
            with self.assertRaisesRegex(ValueError, 'Duplicate review'):
                replays.compare(root / 'events.json', root / 'reviews.json', 'absent', root / 'report.json')


if __name__ == '__main__':
    unittest.main()
