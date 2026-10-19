"""Extra exact-build observation fields, separate from the frozen state adapters.

Control words remain numeric observations, not historical CC bit enums. Resource
floats follow native registration order; the intervening mixed field is accepted
only in the zero-byte representation actually reviewed for this prefix.
"""
from replay_state import float_field


def word(data, pos):
    if pos >= len(data):
        raise ValueError('Truncated control word')
    if data[pos] == 255:
        return 0, pos + 1
    value = 0
    for index in range(5):
        if pos >= len(data):
            raise ValueError('Truncated control word')
        byte = data[pos]; pos += 1
        if index == 4 and byte > 15:
            raise ValueError('Control word exceeds uint32')
        value |= (byte & 127) << (7 * index)
        if byte < 128:
            return value, pos
    raise ValueError('Overlong control word')


def fields(component):
    group, mask = component['group'], component['mask']
    data, pos, result = bytes.fromhex(component['data-hex']), 0, {}
    if group == 4:
        names = {0: 'action-state-code', 1: 'action-state2-code', 2: 'status-flags-code',
                 30: 'physical-damage-percentage-modifier', 31: 'magical-damage-percentage-modifier'}
        for bit in range(32):
            if mask & (1 << bit):
                value, pos = (word if bit < 3 else float_field)(data, pos)
                if bit in names: result[names[bit]] = value
        if pos != len(data):
            raise ValueError('Trailing combat bytes')
    elif group == 32:
        # Native health registration: ten floats, one mixed field. Hero
        # registration adds Exp/Lifetime/MaxLifetime/LifetimeTicks, then PAR.
        for bit in range(17):
            if not mask & (1 << bit): continue
            if bit == 10:
                if pos >= len(data) or data[pos] != 0:
                    raise ValueError('Unreviewed mixed health field representation')
                pos += 1
            else:
                value, pos = float_field(data, pos)
                if bit in (15, 16):
                    result['primary-resource' if bit == 15 else 'primary-resource-max'] = value
        if not mask >> 17 and pos != len(data):
            raise ValueError('Trailing resource prefix bytes')
    return result
