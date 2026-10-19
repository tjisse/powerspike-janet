"""Recover exact-build action announcements without admitting damage evidence.

Packet identities/field labels remain research candidates. Native full-payload
decoding is distinct from proving server-side timing, cancellation or effects.
The decoder never receives damage amounts, model predictions or Riot timelines.
"""
import argparse
from collections import Counter
import gzip
import json
import math
from pathlib import Path
import struct
import time

from replay_buffs import wire_key
from replay_framing import iter_blocks
from replay_native import NativeDecoder, accepted_call, BUILD, PROTOCOL
from replay_recovery import digest, load

ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / 'observations/replays/16.20.824.8524-native-profile.json'
ACTION_TYPES = {906: (80, 0x10154b9b0), 1215: (352, 0x10154f810)}


class ActionDecoder(NativeDecoder):
    """Use only the guarded image; emulate allocation, never native execution."""
    def __init__(self, image, profile):
        super().__init__(image, profile)
        from unicorn import UC_HOOK_CODE, UC_HOOK_MEM_WRITE
        # Runtime-only services: thread-safe static initialization, process-exit
        # registration and a string allocator. No wire-reader/game logic is stubbed.
        for address, kind in (
                (0x10223271a, 'guard-acquire'), (0x102232720, 'guard-release'),
                (0x1022326fc, 'atexit'), (0x1016fc320, 'allocator-init'),
                (0x1016f0510, 'allocate-with-owner'), (0x1016fc0f0, 'free')):
            self.uc.hook_add(UC_HOOK_CODE, self._runtime, kind, begin=address, end=address)
        # NativeDecoder's capture covers the first 128 bytes. Cast objects are
        # larger; retain four-byte writes in the rest without double-capturing.
        self.uc.hook_add(UC_HOOK_MEM_WRITE, self._capture,
                         begin=self.OUT + 128, end=self.OUT + 351)

    def _float_capture(self, uc, address, size, user):
        ptr = uc.reg_read(self.reg.UC_X86_REG_RBX)
        if self.OUT <= ptr <= self.OUT + 348:
            self.float_words[ptr - self.OUT].append(
                uc.reg_read(self.reg.UC_X86_REG_EAX) & 0xffffffff)

    def _runtime(self, uc, address, size, kind):
        r = self.reg
        result = 0
        if kind == 'guard-acquire':
            ptr = uc.reg_read(r.UC_X86_REG_RDI)
            result = int(not (uc.mem_read(ptr, 1)[0] & 1))
        elif kind == 'guard-release':
            uc.mem_write(uc.reg_read(r.UC_X86_REG_RDI), b'\x01')
        elif kind == 'allocate-with-owner':
            n = uc.reg_read(r.UC_X86_REG_RSI)
            if n > self.MAX_BYTES or self.heap_cursor + n + 16 > self.HEAP + self.HEAP_SIZE:
                raise ValueError('Action string allocation budget exceeded')
            result = self.heap_cursor
            self.heap_cursor = (result + n + 15) & ~15
            uc.mem_write(result, bytes(n))
        sp = uc.reg_read(r.UC_X86_REG_RSP)
        ret = struct.unpack('<Q', uc.mem_read(sp, 8))[0]
        uc.reg_write(r.UC_X86_REG_RAX, result)
        uc.reg_write(r.UC_X86_REG_RSP, sp + 8)
        uc.reg_write(r.UC_X86_REG_RIP, ret)

    def _action(self, opcode, payload):
        if opcode not in ACTION_TYPES or not 0 < len(payload) <= self.MAX_BYTES:
            raise ValueError('Unsupported action opcode or payload budget')
        size, function = ACTION_TYPES[opcode]
        uc, r = self.uc, self.reg
        self.heap_cursor = self.HEAP
        uc.mem_write(self.IO, bytes(8))
        uc.reg_write(r.UC_X86_REG_RDI, self.IO)
        uc.reg_write(r.UC_X86_REG_RSI, opcode)
        self._call(0x101237830)
        ptr = struct.unpack('<Q', uc.mem_read(self.IO, 8))[0]
        if not self.HEAP <= ptr <= self.heap_cursor - size:
            raise ValueError('Action constructor outside private heap')
        obj = bytes(uc.mem_read(ptr, size))
        vtable = struct.unpack_from('<Q', obj)[0]
        if struct.unpack('<Q', uc.mem_read(vtable + 8, 8))[0] != function:
            raise ValueError('Action factory/deserializer identity mismatch')
        uc.mem_write(self.OUT, obj)
        uc.mem_write(self.PAYLOAD, payload)
        uc.mem_write(self.CURSOR, struct.pack('<Q', self.PAYLOAD))
        self.writes.clear()
        self.float_words.clear()
        uc.reg_write(r.UC_X86_REG_RDI, self.OUT)
        uc.reg_write(r.UC_X86_REG_RSI, self.CURSOR)
        uc.reg_write(r.UC_X86_REG_RDX, self.PAYLOAD + len(payload))
        self._call(function)
        consumed = struct.unpack('<Q', uc.mem_read(self.CURSOR, 8))[0] - self.PAYLOAD
        accepted_call(uc.reg_read(r.UC_X86_REG_RIP), self.STOP,
                      uc.reg_read(r.UC_X86_REG_RAX), consumed, len(payload))

    def _word(self, offset):
        values = self.writes[offset]
        if len(values) < 2:
            raise ValueError('No independent plaintext action field')
        return values[-2]

    def decode(self, opcode, payload, source):
        self._action(opcode, payload)
        if opcode == 906:
            # The internal attack-slot byte and auxiliary cast records are left
            # uninterpreted. Neither an ordinary nor a noncritical hit is inferred.
            return {'kind': 'basic-attack-announcement-candidate', 'source': source,
                    'target': self._word(0x30), 'missile-id-candidate': self._word(0x2c),
                    'encoded-slot': self.uc.mem_read(self.OUT + 0x18, 1)[0],
                    'auxiliary-cast-count': struct.unpack('<I', self.uc.mem_read(self.OUT + 0x40, 4))[0]}
        caster = self._word(0x90)
        if caster != source:
            raise ValueError('Cast source and block subject disagree')
        start = struct.unpack('<f', struct.pack('<I', self._word(0x40)))[0]
        if not math.isfinite(start) or not 0 <= start <= 86400:
            raise ValueError('Implausible native cast start time')
        pointer = struct.unpack('<Q', self.uc.mem_read(self.OUT + 0x110, 8))[0]
        length = struct.unpack('<I', self.uc.mem_read(self.OUT + 0x118, 4))[0]
        if length > 128 or length and not self.HEAP <= pointer <= self.heap_cursor - length:
            raise ValueError('Cast source name outside private heap/budget')
        name = bytes(self.uc.mem_read(pointer, length)).decode('utf-8') if length else ''
        return {'kind': 'spell-cast-announcement-candidate', 'source': caster,
                'effect-hash': self._word(0x30), 'start-time-candidate': start,
                'secondary-hash-candidate': self._word(0x108),
                'source-name': name}


def extract(replay_path, image, profile_path, output, champion_start):
    from rofllens import ReplayReader
    output = Path(output)
    if output.exists():
        raise ValueError('Choose a fresh action archive directory')
    started = time.monotonic()
    decoder = ActionDecoder(image, load(profile_path))
    counts, failures = Counter(), Counter()
    rejected = []
    with ReplayReader.open(replay_path) as replay:
        if replay.header.client_version != BUILD or replay.header.protocol_digest != PROTOCOL:
            raise ValueError('Replay exact build/protocol mismatch')
        output.mkdir(parents=True)
        with gzip.open(output / 'actions.jsonl.gz', 'wt') as handle:
            for block in iter_blocks(replay, streams={'gameChunk'},
                                     opcodes=set(ACTION_TYPES), include_payload=True):
                if not champion_start <= block.param < champion_start + 10:
                    continue
                event_id = f'{block.stream}:{block.chunk_id}:{block.block_offset}'
                counts[str(block.packet_id)] += 1
                try:
                    row = decoder.decode(block.packet_id, block.payload, block.param)
                    row.update({'event-id': event_id, 'timestamp': block.timestamp,
                                'opcode': block.packet_id, 'raw-payload-hex': block.payload.hex()})
                    handle.write(json.dumps(row, allow_nan=False) + '\n')
                except (ValueError, UnicodeError, RuntimeError) as error:
                    failures[str(block.packet_id)] += 1
                    rejected.append({'event-id': event_id, 'opcode': block.packet_id,
                                     'timestamp': block.timestamp, 'reason': str(error)})
                except Exception as error:
                    # Optional Unicorn errors are recorded as failures, never an
                    # absent action. Unexpected Python failures must still stop.
                    from unicorn import UcError
                    if not isinstance(error, UcError):
                        raise
                    failures[str(block.packet_id)] += 1
                    rejected.append({'event-id': event_id, 'opcode': block.packet_id,
                                     'timestamp': block.timestamp, 'reason': str(error)})
    (output / 'rejected.json').write_text(json.dumps(rejected, indent=2) + '\n')
    report = {'format': 'powerspike-replay-actions', 'version': 1,
              'client-build': BUILD, 'protocol-digest': PROTOCOL,
              'replay-sha256': digest(replay_path), 'image-sha256': digest(image),
              'profile-sha256': digest(profile_path), 'champion-entity-start': champion_start,
              'adapters': {name: digest(ROOT / 'scripts' / name) for name in
                           ('replay_actions.py', 'replay_native.py', 'replay_framing.py')},
              'counts': dict(counts), 'failures': dict(failures),
              'archives': {name: digest(output / name) for name in ('actions.jsonl.gz', 'rejected.json')},
              'model-admissible-cases': 0,
              'scope': 'Native-decoded action candidates only. Cancellation, hit/crit outcome, server stat sampling and full protocol coverage remain unverified.',
              'cost': {'wall-seconds': time.monotonic() - started}}
    (output / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


def candidates(case, actions, window=2):
    """Find all possible announcements; no nearest-action or damage-error fitting."""
    if not math.isfinite(window) or not 0 < window <= 10:
        raise ValueError('Invalid candidate search window')
    return [row for row in actions
            if row['kind'] == 'basic-attack-announcement-candidate'
            and row['source'] == case['source'] and row['target'] == case['target']
            and 0 <= case['timestamp'] - row['timestamp'] <= window
            and wire_key(row['event-id']) < wire_key(case['event-id'])]


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--replay', type=Path, required=True)
    parser.add_argument('--image', type=Path, required=True)
    parser.add_argument('--profile', type=Path, default=PROFILE)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--champion-start', type=lambda value: int(value, 0), required=True)
    args = parser.parse_args()
    result = extract(args.replay, args.image, args.profile, args.output, args.champion_start)
    print(json.dumps({key: result[key] for key in ('counts', 'failures', 'model-admissible-cases', 'cost')}))
