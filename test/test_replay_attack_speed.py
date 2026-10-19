"""Raw timing evidence must retain component boundaries and source identities."""
import gzip
import hashlib
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from replay_attack_speed import decode_records, extract
from replay_native import BUILD, PROTOCOL, IMAGE_SHA256


def record(entity, group, mask, data):
    return struct.pack('<BIIB', group, entity, mask, len(data)) + data


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class SpeedFields(unittest.TestCase):
    def test_separate_raw_components_and_absent_values(self):
        fields = decode_records(record(7, 4, 1 << 18, struct.pack('<f', 1.85)), {7})[0]['fields']
        self.assertAlmostEqual(fields['attack-speed-modifier'], 1.85, places=6)
        self.assertNotIn('percent-attack-speed-modifier', fields)
        data = record(7, 8, (1 << 21) | (1 << 22), struct.pack('<ff', .5, 1))
        self.assertEqual(decode_records(data, {7})[0]['fields'],
                         {'percent-attack-speed-modifier': .5,
                          'multiplicative-attack-speed-modifier': 1.})
        self.assertEqual(decode_records(record(7, 8, 0, b''), {7})[0]['fields'], {})
        self.assertEqual(decode_records(data, {8})[0]['fields'], {})

    def test_integer_prefix_escape_zero_and_unresolved_suffix(self):
        data = record(7, 4, 1 | (1 << 18), b'\x80\x01\xff')
        self.assertEqual(decode_records(data, {7})[0]['fields']['attack-speed-modifier'], 0.)
        data = record(7, 8, (1 << 21) | (1 << 31), b'\xfe' + struct.pack('<f', .5) + b'\xff\x02')
        parsed = decode_records(data, {7})[0]
        self.assertEqual(parsed['fields']['percent-attack-speed-modifier'], .5)
        self.assertEqual(parsed['components'][0]['uninterpreted-data-hex'], 'ff02')

    def test_malformed_or_nonfinite_components_are_not_partial_observations(self):
        for raw in [b'', b'\xfe', struct.pack('<f', float('nan'))]:
            with self.assertRaises(ValueError):
                decode_records(record(7, 8, 1 << 21, raw), {7})

    def test_retained_native_decoded_examples(self):
        fixture = json.loads((Path(__file__).resolve().parents[1] /
                              'observations/replays/16.20.824.8524-attack-speed-cases.json').read_text())
        for case in fixture['cases']:
            # These are native-decoded record components from a retained game,
            # not expected combat values calculated by the simulator.
            from replay_attack_speed import speed_fields
            self.assertEqual(speed_fields(case['components']), case['expected-fields'])


class ArchiveExtraction(unittest.TestCase):
    def setup_archive(self, root):
        combat = root / 'combat'
        combat.mkdir()
        summary = {'client-build': BUILD, 'protocol-digest': PROTOCOL,
                   'image-sha256': IMAGE_SHA256, 'replay-sha256': 'a' * 64,
                   'failures': {}, 'champion-entity-start': 7,
                   'validation': {'damage-totals': {'checks': 50, 'within-one': 49,
                                                    'max-absolute-error': 1.01}}}
        (combat / 'summary.json').write_text(json.dumps(summary))
        source = combat / 'state.jsonl.gz'
        with gzip.open(source, 'wt') as handle:
            handle.write(json.dumps({'event-id': 'gameChunk:3:4', 'timestamp': 1.,
                                      'decoded-buffer-hex': record(7, 8, 1 << 21, struct.pack('<f', .5)).hex()}) + '\n')
        return combat, source, summary

    def test_receipts_preserve_discrepancy_and_do_not_admit_model_results(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            combat, source, _ = self.setup_archive(root)
            result = extract(combat, root / 'output', digest(source))
            self.assertEqual(result['source-state-sha256'], digest(source))
            self.assertEqual(result['source-damage-totals']['within-one'], 49)
            self.assertEqual(result['model-admissible-cases'], 0)
            with gzip.open(root / 'output/attack-speed.jsonl.gz', 'rt') as handle:
                row = json.loads(handle.readline())
            self.assertEqual(row['event-id'], 'gameChunk:3:4')
            self.assertEqual(row['timestamp'], 1.)
            self.assertEqual(row['fields'], {'percent-attack-speed-modifier': .5})
            with self.assertRaises(FileExistsError):
                extract(combat, root / 'output', digest(source))

    def test_changed_archive_wrong_build_and_failed_decoder_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            combat, source, summary = self.setup_archive(root)
            with self.assertRaisesRegex(ValueError, 'receipt mismatch'):
                extract(combat, root / 'output', '0' * 64)
            for changes in [{'client-build': '16.19'}, {'failures': {'bad packet': 1}},
                            {'image-sha256': '0' * 64}]:
                (combat / 'summary.json').write_text(json.dumps({**summary, **changes}))
                with self.assertRaisesRegex(ValueError, 'incompatible'):
                    extract(combat, root / 'output', digest(source))
            self.assertFalse((root / 'output').exists())

    def test_duplicate_wire_identity_is_not_double_counted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            combat, source, _ = self.setup_archive(root)
            with gzip.open(source, 'rt') as handle:
                line = handle.read()
            with gzip.open(source, 'wt') as handle:
                handle.write(line + line)
            with self.assertRaisesRegex(ValueError, 'unique gameplay wire order'):
                extract(combat, root / 'output', digest(source))

    def test_invalid_or_backwards_timestamps_are_rejected(self):
        for timestamp in [False, float('nan'), float('inf'), -1., .5]:
            with self.subTest(timestamp=timestamp), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                combat, source, _ = self.setup_archive(root)
                with gzip.open(source, 'rt') as handle:
                    first = json.loads(handle.readline())
                with gzip.open(source, 'wt') as handle:
                    handle.write(json.dumps(first) + '\n')
                    handle.write(json.dumps({**first, 'event-id': 'gameChunk:3:5', 'timestamp': timestamp}) + '\n')
                with self.assertRaisesRegex(ValueError, 'finite and nondecreasing'):
                    extract(combat, root / 'output', digest(source))


if __name__ == '__main__':
    unittest.main()
