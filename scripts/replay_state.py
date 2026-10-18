"""Partial replication fields and causal last-observed state, never exact state.

All group bodies are retained. Groups 4 and the float prefix of group 8 include
offensive stat components. Group 32 is decoded only through field 5: later
integer encodings are unresolved on this build. Shield names follow the native
mHP/mMaxHP/mAllShield descriptor order but lack independent API shield labels.
"""
import math
import struct


HEALTH_FIELDS = ('health', 'health-max', 'health-max-penalty',
                 'shield-all-candidate', 'shield-physical-candidate', 'shield-magic-candidate')
COMBAT_FIELDS = {
    3: 'base-attack-damage', 4: 'base-ability-power', 6: 'crit-chance',
    7: 'armor', 8: 'magic-resist', 12: 'flat-attack-damage',
    13: 'percent-attack-damage', 14: 'flat-ability-power',
    15: 'percent-ability-power', 23: 'flat-armor-penetration',
    24: 'armor-remaining-fraction', 25: 'flat-magic-penetration',
    26: 'magic-resist-remaining-fraction',
}
# Current Intel descriptor function 0x10006b4c0, first 26 float fields.
# The remaining group-8 fields have different types and stay uninterpreted.
EXTENDED_FIELDS = {
    0: 'bonus-armor-remaining-fraction',
    1: 'crit-bonus-armor-remaining-fraction',
    2: 'crit-total-armor-remaining-fraction',
    3: 'bonus-magic-resist-remaining-fraction',
    4: 'physical-lethality', 5: 'magic-lethality',
    13: 'flat-base-attack-damage', 14: 'percent-base-attack-damage',
    15: 'base-attack-damage-sans-percent-scale',
    17: 'bonus-armor', 18: 'bonus-magic-resist',
    19: 'percent-bonus-attack-damage',
    20: 'percent-base-attack-damage-as-bonus', 23: 'crit-damage-multiplier',
}
AD_INPUTS = ('base-attack-damage', 'flat-attack-damage', 'percent-attack-damage',
             'percent-bonus-attack-damage', 'percent-base-attack-damage-as-bonus')
AP_INPUTS = ('base-ability-power', 'flat-ability-power', 'percent-ability-power')
NAMED_FIELDS = (*HEALTH_FIELDS, *COMBAT_FIELDS.values(), *EXTENDED_FIELDS.values())


def float_field(data, cursor):
    if cursor >= len(data):
        raise ValueError('Truncated replication float')
    if data[cursor] == 255:
        return 0., cursor + 1
    if data[cursor] == 254:
        cursor += 1
    if cursor + 4 > len(data):
        raise ValueError('Truncated replication float')
    value = struct.unpack_from('<f', data, cursor)[0]
    if not math.isfinite(value):
        raise ValueError('Nonfinite replication float')
    return value, cursor + 4


def combat_fields(mask, data):
    cursor, values = 0, {}
    for bit in range(32):
        if not mask & (1 << bit):
            continue
        if bit > 2:
            value, cursor = float_field(data, cursor)
            values[bit] = value
        else:
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
    if cursor != len(data):
        raise ValueError('Trailing combat field bytes')
    return {name: values[bit] for bit, name in COMBAT_FIELDS.items() if bit in values}


def extended_fields(mask, data):
    cursor, named = 0, {}
    for bit in range(26):
        if mask & (1 << bit):
            value, cursor = float_field(data, cursor)
            if bit in EXTENDED_FIELDS:
                named[EXTENDED_FIELDS[bit]] = value
    if not mask >> 26 and cursor != len(data):
        raise ValueError('Trailing extended combat prefix bytes')
    return named, cursor


def derived_stats(samples):
    """Derive totals from observed components, retaining every input's provenance.

    These compose replicated stats; they are not model-derived build statistics.
    No missing component defaults to zero. No damage observation enters here.
    """
    result = {}
    for name, inputs in (('attack-damage', AD_INPUTS), ('ability-power', AP_INPUTS)):
        if not all(key in samples for key in inputs):
            continue
        values = {key: samples[key]['value'] for key in inputs}
        if name == 'attack-damage':
            base = values['base-attack-damage']
            value = (base + values['flat-attack-damage'] * (1 + values['percent-bonus-attack-damage'])
                     + base * values['percent-base-attack-damage-as-bonus']) * (1 + values['percent-attack-damage'])
        else:
            value = (values['base-ability-power'] + values['flat-ability-power']) * (1 + values['percent-ability-power'])
        if not math.isfinite(value):
            raise ValueError('Nonfinite derived offensive stat')
        result[name] = {'value': value, 'inputs': {key: dict(samples[key]) for key in inputs},
                        'kind': 'composed-replay-observation'}
    return result


def replication_records(data, named_entities=None):
    cursor, records = 0, []
    while cursor < len(data):
        if cursor + 5 > len(data):
            raise ValueError('Truncated replication record')
        groups, entity = struct.unpack_from('<BI', data, cursor)
        cursor += 5
        if groups & 128:
            raise ValueError('Unsupported replication record wrapper')
        components, named = [], {}
        for group in (1, 2, 4, 8, 16, 32, 64):
            if not groups & group:
                continue
            if cursor + 5 > len(data):
                raise ValueError('Truncated replication group header')
            mask, n = struct.unpack_from('<IB', data, cursor)
            cursor += 5
            if cursor + n > len(data):
                raise ValueError('Truncated replication group body')
            body = data[cursor:cursor + n]
            cursor += n
            component = {'group': group, 'mask': mask, 'data-hex': body.hex()}
            # Parse every named component before returning any state. A malformed
            # record cannot leave a partially applied health/armor update behind.
            interpret = named_entities is None or entity in named_entities
            if group == 4 and interpret:
                named.update(combat_fields(mask, body))
            elif group == 8 and interpret:
                extra, pos = extended_fields(mask, body)
                named.update(extra)
                component['uninterpreted-mask'] = mask & ~((1 << 26) - 1)
                component['uninterpreted-data-hex'] = body[pos:].hex()
            elif group == 32 and interpret:
                pos = 0
                for bit, name in enumerate(HEALTH_FIELDS):
                    if mask & (1 << bit):
                        named[name], pos = float_field(body, pos)
                if not mask >> 6 and pos != len(body):
                    raise ValueError('Trailing health-prefix bytes')
                component['uninterpreted-mask'] = mask & ~63
                component['uninterpreted-data-hex'] = body[pos:].hex()
            components.append(component)
        records.append({'entity': entity, 'components': components, 'fields': named})
    return records


class ObservedState:
    def __init__(self):
        self.entities = {}
        self.last_key = None

    def apply(self, records, timestamp, order, event_id):
        key = (timestamp, order)
        if self.last_key is not None and key <= self.last_key:
            raise ValueError('Replication updates must preserve timestamp and wire order')
        self.last_key = key
        for record in records:
            fields = self.entities.setdefault(record['entity'], {})
            for name, value in record['fields'].items():
                fields[name] = {'value': value, 'timestamp': timestamp,
                                'order': order, 'event-id': event_id}

    def invalidate(self):
        # After a dropped update, retain no implied continuity of older values.
        self.entities.clear()

    def before(self, entity, timestamp, order):
        result = {}
        for name, sample in self.entities.get(entity, {}).items():
            if (sample['timestamp'], sample['order']) >= (timestamp, order):
                continue
            result[name] = {**sample, 'age-seconds': timestamp - sample['timestamp'],
                            'same-timestamp': timestamp == sample['timestamp']}
        result.update(derived_stats(result))
        return result
