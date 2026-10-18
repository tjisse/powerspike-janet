"""Regression cases for framing errors that misattribute replay observations."""
from pathlib import Path
import struct
import sys
from types import SimpleNamespace
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from replay_framing import chunk_blocks, iter_blocks

CHUNK = SimpleNamespace(chunk_id=1, stream=1, stream_name='gameChunk')


def absolute(param, packet=421, payload=b''):
    return struct.pack('<BfIHI', 0, 1.0, len(payload), packet, param) + payload


class FramingTests(unittest.TestCase):
    def test_negative_delta_does_not_create_an_entity_256_away(self):
        data = absolute(0x400000b3) + bytes([0xf0, 1, 0, 255])
        a, b = list(chunk_blocks(data, CHUNK))
        self.assertEqual(a.param, 0x400000b3)
        self.assertEqual(b.param, 0x400000b2)
        self.assertAlmostEqual(b.timestamp, 1.001)

    def test_delta_limits_and_uint32_wrap(self):
        for start, delta, wanted in [(0, -1, 0xffffffff), (0xffffffff, 1, 0),
                                     (128, -128, 0), (0, 127, 127)]:
            data = absolute(start) + bytes([0xf0, 0, 0, delta & 255])
            self.assertEqual(list(chunk_blocks(data, CHUNK))[-1].param, wanted)

    def test_filtered_packet_still_updates_the_next_param(self):
        data = absolute(10, 7) + bytes([0xb0, 0, 1]) + struct.pack('<H', 8) + bytes([255, 42])
        data += bytes([0xb0, 0, 0]) + struct.pack('<H', 421) + bytes([255])
        blocks = list(chunk_blocks(data, CHUNK, opcodes={421}, include_payload=True))
        self.assertEqual(len(blocks), 1)
        self.assertEqual(blocks[0].param, 8)
        self.assertEqual(blocks[0].payload, b'')

    def test_each_chunk_resets_relative_state(self):
        class Replay:
            def chunks(self, **kwargs):
                return [CHUNK, SimpleNamespace(chunk_id=2, stream=1, stream_name='gameChunk')]
            def read_chunk_body(self, chunk, **kwargs):
                return absolute(99) if chunk.chunk_id == 1 else bytes([0xf0, 0, 0, 1])
        self.assertEqual([b.param for b in iter_blocks(Replay())], [99, 1])

    def test_bad_length_or_timestamp_fails_instead_of_partial_success(self):
        for data in (b'\0', absolute(1, payload=b'ab')[:-1],
                     absolute(1)[:1] + struct.pack('<f', float('nan')) + absolute(1)[5:]):
            with self.assertRaises(ValueError):
                list(chunk_blocks(data, CHUNK))


if __name__ == '__main__':
    unittest.main()
