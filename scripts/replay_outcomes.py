"""Decode action slots and damage result codes from guarded native byte codecs.

These are observations, not model comparisons. Historical enum labels are not
copied onto current codes. Unknown outcome codes and opaque flags stay explicit.
"""
import argparse
from collections import Counter, defaultdict
import gzip
import json
from pathlib import Path
import struct
import time

from replay_actions import ActionDecoder, PROFILE
from replay_attack_review import archive
from replay_native import BUILD, PROTOCOL
from replay_recovery import digest, load

ROOT = Path(__file__).resolve().parents[1]


class OutcomeDecoder(ActionDecoder):
    def __init__(self, image, profile):
        super().__init__(image, profile)
        self.slots, self.action_words, self.results, self.contexts = {}, {}, {}, {}
        # Exhaustive native probes, independent of replay/API/model values.
        # Slot: decode the stored object byte using the reader's native codec.
        # Other fields: invert the native object-encoding block, including its
        # constant branches, rather than assuming a plaintext write was observed.
        uc, r = self.uc, self.reg
        for value in range(256):
            uc.reg_write(r.UC_X86_REG_RCX, value)
            self._call(0x10154b756, 0x10154b773)
            self.slots[value] = uc.reg_read(r.UC_X86_REG_RCX) & 255
            for register in (r.UC_X86_REG_RDX, r.UC_X86_REG_RDI, r.UC_X86_REG_RSI, r.UC_X86_REG_RCX):
                uc.reg_write(register, value)
            uc.reg_write(r.UC_X86_REG_RBX, self.OUT + 0x10)
            self._call(0x10154b086, 0x10154b0e2)
            encoded = bytes(uc.mem_read(self.OUT + 0x18, 4))
            if len(set(encoded)) != 1 or encoded[0] in self.action_words:
                raise ValueError('Action word codec is not lane-independent/bijective')
            self.action_words[encoded[0]] = value
            uc.reg_write(r.UC_X86_REG_RCX, value)
            self._call(0x10125b0b9, 0x10125b0d4)
            self.results[uc.reg_read(r.UC_X86_REG_RCX) & 255] = value
            uc.reg_write(r.UC_X86_REG_RAX, value)
            self._call(0x1012623db, 0x1012623e2)
            self.contexts[uc.reg_read(r.UC_X86_REG_RAX) & 255] = value
        if any(len(table) != 256 or len(set(table.values())) != 256
               for table in (self.slots, self.action_words, self.results, self.contexts)):
            raise ValueError('Native outcome codec is not a complete byte bijection')

    def action(self, opcode, payload, source):
        row = super().decode(opcode, payload, source)
        if opcode == 906:
            obj = bytes(self.uc.mem_read(self.OUT, 80))
            # The older opaque `encoded-slot` key referred to a byte of a
            # different four-byte field. Keep its location explicit; it is not
            # the AttackSlot byte at parent offset 0x1d.
            row['opaque-field-08-first-byte'] = row.pop('encoded-slot')
            row['attack-slot'] = self.slots[obj[0x1d]]
            row['sequence-candidate'] = struct.unpack('<I', bytes(self.action_words[b] for b in obj[0x18:0x1c]))[0]
        return row

    def damage_outcome(self, payload, target):
        row = super().damage(payload, target)
        obj = bytes(self.uc.mem_read(self.OUT, 48))
        row['result-code'] = self.results[obj[0x20]]
        row['opaque-context-code'] = self.contexts[obj[0x1a]]
        if obj[0x19] not in (0x7d, 0xbf):
            raise ValueError('Unexpected native boolean representation')
        row['opaque-flag-19'] = obj[0x19] == 0x7d
        row['result-code-encoded'] = row.pop('source-kind-encoded')
        return row


def extract(combat_dir, audit_dir, actions_dir, image, output):
    combat_dir, audit_dir, actions_dir, output = map(Path, (combat_dir, audit_dir, actions_dir, output))
    if output.exists():
        raise ValueError('Choose a fresh outcome archive directory')
    started = time.monotonic()
    combat, audit, actions = [load(folder / 'summary.json') for folder in (combat_dir, audit_dir, actions_dir)]
    if (len({r['replay-sha256'] for r in (combat, audit, actions)}) != 1
            or any(r['client-build'] != BUILD or r['protocol-digest'] != PROTOCOL for r in (combat, audit, actions))
            or combat.get('failures') or actions.get('failures')):
        raise ValueError('Source build/identity mismatch or incomplete source extraction')
    for folder, receipts in ((combat_dir, audit['source-files']), (audit_dir, audit['evidence-files']),
                             (actions_dir, actions['archives'])):
        for name, expected in receipts.items():
            if Path(name).name != name or digest(folder / name) != expected:
                raise ValueError('Outcome source receipt mismatch')
    decoder = OutcomeDecoder(image, load(PROFILE))
    if combat['image-sha256'] != digest(image) or actions['image-sha256'] != combat['image-sha256']:
        raise ValueError('Native image differs between source archives')
    cases = {row['event-id']: row for row in archive(audit_dir / 'cases.jsonl.gz')}
    if len(cases) != audit['counts']['champion-to-champion-events']:
        raise ValueError('Incomplete case archive')
    counts, cohorts = Counter(), defaultdict(Counter)
    output.mkdir(parents=True)
    seen = set()
    with gzip.open(output / 'damage-outcomes.jsonl.gz', 'wt') as handle:
        for row in archive(combat_dir / 'damage.jsonl.gz'):
            case = cases.get(row['event-id'])
            if case is None:
                continue
            result = decoder.damage_outcome(bytes.fromhex(row['raw-payload-hex']), row['target'])
            for key, field in (('source', 'source'), ('target', 'target'), ('effect-hash', 'effect-hash'),
                               ('damage-type', 'damage-type'), ('amount', 'recorded-amount')):
                if result[key] != case[field]:
                    raise ValueError('Native outcome extraction disagrees with retained damage observation')
            result.update({'event-id': row['event-id'], 'timestamp': row['timestamp'],
                           'effect-kind': case['effect-kind'], 'candidate-names': case['candidate-names']})
            cohorts[case['effect-kind']][str(result['result-code'])] += 1
            counts['damage-outcomes'] += 1
            seen.add(row['event-id'])
            handle.write(json.dumps(result, allow_nan=False) + '\n')
    if seen != set(cases):
        raise ValueError('Case/outcome archive is incomplete')
    with gzip.open(output / 'action-slots.jsonl.gz', 'wt') as handle:
        for row in archive(actions_dir / 'actions.jsonl.gz'):
            result = decoder.action(row['opcode'], bytes.fromhex(row['raw-payload-hex']), row['source'])
            for key in ('kind', 'source', 'target', 'missile-id-candidate', 'auxiliary-cast-count',
                        'effect-hash', 'start-time-candidate', 'secondary-hash-candidate', 'source-name'):
                if key in row and row[key] != result[key]:
                    raise ValueError('Native action disagrees with retained announcement')
            result.update({'event-id': row['event-id'], 'timestamp': row['timestamp'], 'opcode': row['opcode']})
            counts['action-announcements'] += 1
            if row['opcode'] == 906:
                counts['attack-slots'] += 1
            handle.write(json.dumps(result, allow_nan=False) + '\n')
    if counts['action-announcements'] != sum(actions['counts'].values()):
        raise ValueError('Action count differs from source extraction')
    report = {'format': 'powerspike-replay-outcomes', 'version': 1,
              'client-build': BUILD, 'protocol-digest': PROTOCOL, 'replay-sha256': combat['replay-sha256'],
              'image-sha256': digest(image), 'counts': dict(counts),
              'result-code-cohorts': {key: dict(value) for key, value in cohorts.items()},
              'inputs': {label: digest(folder / 'summary.json') for label, folder in
                         [('combat', combat_dir), ('audit', audit_dir), ('actions', actions_dir)]},
              'adapters': {name: digest(ROOT / 'scripts' / name) for name in
                           ('replay_outcomes.py', 'replay_actions.py', 'replay_native.py')},
              'archives': {p.name: digest(p) for p in output.iterdir()},
              'admitted-model-comparisons': 0,
              'scope': 'Native-decoded slots and result codes. Labels and causality require corroboration; no expected damage or tolerance fitting.',
              'cost': {'wall-seconds': time.monotonic() - started}}
    (output / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('combat', 'audit', 'actions', 'image', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    report = extract(args.combat, args.audit, args.actions, args.image, args.output)
    print(json.dumps({key: report[key] for key in ('counts', 'result-code-cohorts', 'admitted-model-comparisons', 'cost')}))
