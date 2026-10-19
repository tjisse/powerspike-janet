"""Reproduce numeric-stat addition using the hash-guarded official client image.

Only bounded scalar methods run inside Unicorn. No game process, API value,
network access, tolerance or expected answer enters the native calculation.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from replay_combat import add_damage_total
from replay_native import NativeDecoder, IMAGE_SHA256, BUILD
from replay_recovery import digest, load

PROFILE = Path(__file__).resolve().parents[1] / 'observations/replays/16.20.824.8524-native-profile.json'


def native_check(image, amounts):
    if not 0 < len(amounts) <= 100000:
        raise ValueError('Native accumulation requires 1 to 100000 amounts')
    for amount in amounts:
        add_damage_total(0., amount)
    decoder = NativeDecoder(image, load(PROFILE))
    uc, reg = decoder.uc, decoder.reg
    left, right = decoder.IO + 0x4000, decoder.IO + 0x4040
    uc.mem_write(left, bytes(64))
    uc.mem_write(right, bytes(64))
    uc.mem_write(left + 0x18, struct.pack('<I', 1))  # native numeric-stat sum mode
    transcript, operands = hashlib.sha256(), hashlib.sha256()
    total = 0.
    for amount in amounts:
        uc.mem_write(left + 0x20, struct.pack('<f', total))
        uc.mem_write(right + 0x20, struct.pack('<f', amount))
        uc.reg_write(reg.UC_X86_REG_RDI, left)
        uc.reg_write(reg.UC_X86_REG_RSI, right)
        decoder._call(0x100143fb0)
        observed = bytes(uc.mem_read(left + 0x20, 4))
        if observed != struct.pack('<f', add_damage_total(total, amount)):
            raise ValueError('Python accumulation differs from guarded native ADDSS')
        next_total = struct.unpack('<f', observed)[0]
        transcript.update(struct.pack('<fff', total, amount, next_total))
        operands.update(struct.pack('<f', amount))
        total = next_total
    if total >= 2 ** 31:
        raise ValueError('Native signed-integer formatter domain exceeded')
    # Stop immediately after CVTTSS2SI; do not call the string formatter.
    uc.reg_write(reg.UC_X86_REG_RDI, left)
    decoder._call(0x100143f97, 0x100143f9c)
    return {'additions': len(amounts), 'native-total': total,
            'native-integer': uc.reg_read(reg.UC_X86_REG_EDX),
            'python-binary64-sum': sum(amounts), 'all-python-additions-bit-exact': True,
            'binary32-operands-sha256': operands.hexdigest(),
            'step-transcript-sha256': transcript.hexdigest()}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', type=Path, required=True)
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.inputs.stat().st_size > 1024 * 1024:
        parser.error('Input JSON must fit within 1 MiB')
    inputs = load(args.inputs)
    result = {'format': 'powerspike-native-stat-accumulation-proof', 'version': 1,
              'client-build': BUILD, 'image-sha256': IMAGE_SHA256,
              'inputs-sha256': digest(args.inputs), 'adapter-sha256': digest(__file__),
              'accumulation-adapter-sha256': digest(Path(__file__).with_name('replay_combat.py')),
              'result': native_check(args.image, inputs['amounts'])}
    with args.output.open('x') as handle:
        handle.write(json.dumps(result, indent=2, allow_nan=False) + '\n')
    print(json.dumps(result))
