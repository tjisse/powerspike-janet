"""Extract raw attack-speed components from an exact-build decoded state archive.

This separate extension preserves the frozen replay_state adapter used by past
reviews. Scalars are client observations, not attacks/second or timing proof.
No API values, model predictions or inferred zeroes enter the extraction.
"""
import argparse
import gzip
import json
import math
from pathlib import Path

from replay_buffs import wire_key
from replay_native import BUILD, PROTOCOL, IMAGE_SHA256
from replay_recovery import digest, load
from replay_state import float_field, replication_records


# Exact-image native descriptors: group4 0x10006b010; group8 0x10006b4c0.
# Keep the three raw components distinct; their full composition is unreviewed.
FIELDS = {4: {18: 'attack-speed-modifier'},
          8: {21: 'percent-attack-speed-modifier',
              22: 'multiplicative-attack-speed-modifier'}}


def speed_fields(components):
    result = {}
    for component in components:
        group = component['group']
        if group not in FIELDS:
            continue
        mask, data = component['mask'], bytes.fromhex(component['data-hex'])
        cursor = 0
        for bit in range(max(FIELDS[group]) + 1):
            if not mask & (1 << bit):
                continue
            if group == 4 and bit < 3:
                # Mixed integer prefix, exactly as in the frozen base adapter.
                if cursor >= len(data):
                    raise ValueError('Truncated combat integer')
                if data[cursor] == 255:
                    cursor += 1
                    continue
                for _ in range(5):
                    if cursor >= len(data):
                        raise ValueError('Truncated combat integer')
                    byte = data[cursor]
                    cursor += 1
                    if byte < 128:
                        break
                else:
                    raise ValueError('Overlong combat integer')
            else:
                value, cursor = float_field(data, cursor)
                if bit in FIELDS[group]:
                    result[FIELDS[group][bit]] = value
    return result


def decode_records(data, champions):
    records = replication_records(data, champions)
    for record in records:
        if record['entity'] in champions:
            record['fields'].update(speed_fields(record['components']))
    return records


def extract(combat, output, expected_state):
    combat, output = Path(combat), Path(output)
    report = load(combat / 'summary.json')
    if (report.get('client-build') != BUILD or report.get('protocol-digest') != PROTOCOL
            or report.get('image-sha256') != IMAGE_SHA256 or report.get('failures')):
        raise ValueError('Incomplete or incompatible native state extraction')
    source = combat / 'state.jsonl.gz'
    if digest(source) != expected_state:
        raise ValueError('State archive receipt mismatch')
    start = report['champion-entity-start']
    champions = set(range(start, start + 10))
    output.mkdir(parents=True, exist_ok=False)
    target = output / 'attack-speed.jsonl.gz'
    previous, previous_time, count = None, -1., 0
    with gzip.open(source, 'rt') as inputs, gzip.open(target, 'wt') as results:
        for line in inputs:
            row = json.loads(line)
            key = wire_key(row['event-id'])
            if previous is not None and key <= previous:
                raise ValueError('State archive must preserve unique gameplay wire order')
            timestamp = row['timestamp']
            if (type(timestamp) not in (int, float) or not math.isfinite(timestamp)
                    or timestamp < 0 or timestamp < previous_time):
                raise ValueError('State timestamps must be finite and nondecreasing')
            previous = key
            previous_time = timestamp
            records = decode_records(bytes.fromhex(row['decoded-buffer-hex']), champions)
            for record in records:
                fields = {name: value for name, value in record['fields'].items()
                          if any(name in names.values() for names in FIELDS.values())}
                if fields:
                    results.write(json.dumps({'event-id': row['event-id'], 'timestamp': row['timestamp'],
                                              'entity': record['entity'], 'fields': fields}, allow_nan=False) + '\n')
                    count += 1
    totals = report.get('validation', {}).get('damage-totals', {})
    result = {'format': 'powerspike-replay-attack-speed', 'version': 1,
              'client-build': BUILD, 'protocol-digest': PROTOCOL,
              'image-sha256': IMAGE_SHA256, 'replay-sha256': report['replay-sha256'],
              'source-summary-sha256': digest(combat / 'summary.json'),
              'source-state-sha256': digest(source),
              'adapters': {name: digest(Path(__file__).with_name(name)) for name in
                           ('replay_attack_speed.py', 'replay_state.py', 'replay_buffs.py',
                            'replay_native.py', 'replay_recovery.py')},
              'archive-sha256': digest(target), 'records': count,
              'source-damage-totals': {key: totals[key] for key in ('checks', 'within-one', 'max-absolute-error') if key in totals},
              'model-admissible-cases': 0,
              'scope': 'Raw named client scalars with original timestamps and wire IDs. No total-speed formula, server sampling instant, full buff state or combat timing is established.'}
    (output / 'summary.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--combat', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--state-sha256', required=True,
                        help='Expected state archive digest from the retained research receipt')
    args = parser.parse_args()
    result = extract(args.combat, args.output, args.state_sha256)
    print(json.dumps(result))
