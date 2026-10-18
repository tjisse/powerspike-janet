"""Bounded offline emulation of exact-build macOS packet deserializers.

The official Intel Mach-O slice is data for Unicorn, never a native process.
No network, API key, game installation or Windows unpacking is involved.
Addresses below apply ONLY to the SHA-256 guarded image. Imports are lazy so
the ordinary project tests do not need the optional replay dependencies.
"""
from collections import defaultdict
import hashlib
import math
from pathlib import Path
import struct


IMAGE_SHA256 = '6e22b0f07beb51a0f5df84435123a34d97b68345319cacff65740f79e0da35a3'
BUILD = '16.20.824.8524'
PROTOCOL = '142cabd45e45d83f'


def verify_inputs(image, profile):
    if (profile.get('format') != 'powerspike-native-replay-profile'
            or profile.get('version') != 1 or profile.get('client-build') != BUILD
            or profile.get('protocol-digest') != PROTOCOL
            or profile.get('image-sha256') != IMAGE_SHA256):
        raise ValueError('Unsupported native decoder profile')
    with Path(image).open('rb') as f:
        if hashlib.file_digest(f, 'sha256').hexdigest() != IMAGE_SHA256:
            raise ValueError('Native image SHA-256 mismatch; refusing address reuse')
    table = profile.get('damage-object-float-byte-table')
    if (not isinstance(table, list) or len(table) != 256
            or any(type(x) is not int for x in table) or set(table) != set(range(256))):
        raise ValueError('Float substitution must be a complete byte bijection')


def accepted_call(pc, stop, result, consumed, length):
    # Unicorn can exhaust its instruction/time budget without raising an error.
    if pc != stop or result & 255 != 1 or consumed != length:
        raise ValueError('Deserializer did not return true and consume the full packet')


class NativeDecoder:
    IO = 0x50000000
    OUT = IO + 0x1000
    CURSOR = IO + 0x8000
    PAYLOAD = IO + 0x10000
    STACK = 0x70000000
    STOP = STACK + 0x100
    HEAP = 0x60000000
    HEAP_SIZE = 0x600000
    MAX_BYTES = 512 * 1024

    def __init__(self, image, profile):
        verify_inputs(image, profile)
        import unicorn
        from unicorn import x86_const
        self.reg = x86_const
        self.uc = uc = unicorn.Uc(unicorn.UC_ARCH_X86, unicorn.UC_MODE_64)
        self.table = profile['damage-object-float-byte-table']
        self.types = profile['damage-types']
        data = Path(image).read_bytes()
        if struct.unpack_from('<II', data) != (0xfeedfacf, 0x01000007):
            raise ValueError('Expected a thin x86_64 Mach-O image')
        cursor = 32
        for _ in range(struct.unpack_from('<I', data, 16)[0]):
            cmd, size = struct.unpack_from('<II', data, cursor)
            if cmd == 0x19:
                va, vsize, offset, n = struct.unpack_from('<QQQQ', data, cursor + 24)
                if n:
                    uc.mem_map(va, (vsize + 4095) & ~4095)
                    uc.mem_write(va, data[offset:offset + n])
            cursor += size
        for address, size in ((self.IO, 0x100000), (self.STACK, 0x100000),
                              (self.HEAP, self.HEAP_SIZE)):
            uc.mem_map(address, size)
        # The ROFL block already carried the common entity header.
        uc.mem_write(0x101865e80, bytes.fromhex('b8 01 00 00 00 c3'))
        self.heap_cursor = self.HEAP
        self.writes = defaultdict(list)
        uc.hook_add(unicorn.UC_HOOK_MEM_WRITE, self._capture,
                    begin=self.OUT, end=self.OUT + 0x80)
        hooks = {0x1016fc1a0: 'allocate', 0x1016fc0c0: 'allocate',
                 0x1022326f0: 'zero', 0x102232750: 'copy',
                 0x102232756: 'copy', 0x10223275c: 'fill',
                 0x102232b4c: 'copy', 0x102232b52: 'copy', 0x102232b58: 'fill'}
        for address, kind in hooks.items():
            uc.hook_add(unicorn.UC_HOOK_CODE, self._memory, kind,
                        begin=address, end=address)
        # Capture float reader output AFTER its big-endian conversion, before
        # per-object substitution. Unchanged fields remain unknown.
        self.float_words = defaultdict(list)
        uc.hook_add(unicorn.UC_HOOK_CODE, self._float_capture,
                    begin=0x101670178, end=0x101670178)
        self.templates = {}
        for opcode, start, end, tail in (
                (150, 0x1012409fc, 0x101240a4d, None),
                (287, 0x1012396f3, 0x10123971e, (0x101243ff5, 0x101243ffc))):
            uc.mem_write(self.OUT, bytes(128))
            uc.reg_write(self.reg.UC_X86_REG_RAX, self.OUT)
            self._call(start, end)
            if tail:
                self._call(*tail)
            self.templates[opcode] = bytes(uc.mem_read(self.OUT, 128))

        # These three packet constructors contain no external allocations.
        # Construct from the guarded image rather than copying research dumps.
        for opcode, expected, size in ((435, 0x10152fb40, 112),
                                       (262, 0x101533d30, 32),
                                       (430, 0x101536de0, 32)):
            self.heap_cursor = self.HEAP
            uc.mem_write(self.IO, bytes(8))
            uc.reg_write(self.reg.UC_X86_REG_RDI, self.IO)
            uc.reg_write(self.reg.UC_X86_REG_RSI, opcode)
            self._call(0x101237830)
            ptr = struct.unpack('<Q', uc.mem_read(self.IO, 8))[0]
            if not self.HEAP <= ptr <= self.heap_cursor - size:
                raise ValueError('Buff constructor allocation outside private heap')
            template = bytes(uc.mem_read(ptr, size))
            vtable = struct.unpack_from('<Q', template)[0]
            if struct.unpack('<Q', uc.mem_read(vtable + 8, 8))[0] != expected:
                raise ValueError('Buff factory/deserializer identity mismatch')
            self.templates[opcode] = template + bytes(128 - size)
        # Counter constants (0/1/2/-1) bypass the plaintext write path. Probe
        # the guarded native SIMD byte codec exhaustively, without replay/API
        # values. All four lanes must agree and form a byte bijection.
        self.counter_table = [None] * 256
        for value in range(256):
            uc.reg_write(self.reg.UC_X86_REG_RBX, self.OUT)
            uc.reg_write(self.reg.UC_X86_REG_EDX, value * 0x01010101)
            self._call(0x101537075, 0x1015370c0)
            encoded = bytes(uc.mem_read(self.OUT + 0x10, 4))
            if len(set(encoded)) != 1 or self.counter_table[encoded[0]] is not None:
                raise ValueError('Counter native byte codec is not lane-independent/bijective')
            self.counter_table[encoded[0]] = value

    def _float_capture(self, uc, address, size, user):
        ptr = uc.reg_read(self.reg.UC_X86_REG_RBX)
        if self.OUT <= ptr <= self.OUT + 0x7c:
            self.float_words[ptr - self.OUT].append(
                uc.reg_read(self.reg.UC_X86_REG_EAX) & 0xffffffff)

    def _capture(self, uc, access, address, size, value, user):
        if size == 4:
            self.writes[address - self.OUT].append(value & 0xffffffff)

    def _memory(self, uc, address, size, kind):
        r = self.reg
        dst = uc.reg_read(r.UC_X86_REG_RDI)
        src = uc.reg_read(r.UC_X86_REG_RSI)
        n = uc.reg_read(r.UC_X86_REG_RDX)
        if kind == 'allocate':
            n = dst
            if n > self.MAX_BYTES or self.heap_cursor + n + 16 > self.HEAP + self.HEAP_SIZE:
                raise ValueError('Emulated allocation budget exceeded')
            result = self.heap_cursor
            self.heap_cursor = (self.heap_cursor + n + 15) & ~15
        else:
            if kind == 'zero':
                n = src
            # Check bounds before constructing bytes or reading emulated memory.
            if n > self.MAX_BYTES or not self.HEAP <= dst <= self.HEAP + self.HEAP_SIZE - n:
                raise ValueError('Emulated memory-copy budget/bounds exceeded')
            if n:
                data = (bytes(n) if kind == 'zero' else bytes([src & 255]) * n
                        if kind == 'fill' else bytes(uc.mem_read(src, n)))
                uc.mem_write(dst, data)
            result = dst
        sp = uc.reg_read(r.UC_X86_REG_RSP)
        ret = struct.unpack('<Q', uc.mem_read(sp, 8))[0]
        uc.reg_write(r.UC_X86_REG_RAX, result)
        uc.reg_write(r.UC_X86_REG_RSP, sp + 8)
        uc.reg_write(r.UC_X86_REG_RIP, ret)

    def _call(self, address, stop=None):
        stop = self.STOP if stop is None else stop
        sp = self.STACK + 0x80000 - 8
        self.uc.reg_write(self.reg.UC_X86_REG_RSP, sp)
        self.uc.mem_write(sp, struct.pack('<Q', self.STOP))
        self.uc.emu_start(address, stop, timeout=1000000, count=1000000)
        if self.uc.reg_read(self.reg.UC_X86_REG_RIP) != stop:
            raise ValueError('Emulator instruction/time budget exhausted')

    def _deserialize(self, opcode, payload):
        if not 0 < len(payload) <= self.MAX_BYTES or opcode == 150 and len(payload) > 4096:
            raise ValueError('Packet payload exceeds decoder budget')
        uc, r = self.uc, self.reg
        self.heap_cursor = self.HEAP
        uc.mem_write(self.OUT, self.templates[opcode])
        uc.mem_write(self.PAYLOAD, payload)
        uc.mem_write(self.CURSOR, struct.pack('<Q', self.PAYLOAD))
        self.writes.clear()
        self.float_words.clear()
        uc.reg_write(r.UC_X86_REG_RDI, self.OUT)
        uc.reg_write(r.UC_X86_REG_RSI, self.CURSOR)
        uc.reg_write(r.UC_X86_REG_RDX, self.PAYLOAD + len(payload))
        self._call({150: 0x101261ff0, 287: 0x10129d410,
                    435: 0x10152fb40, 262: 0x101533d30,
                    430: 0x101536de0}[opcode])
        consumed = struct.unpack('<Q', uc.mem_read(self.CURSOR, 8))[0] - self.PAYLOAD
        accepted_call(uc.reg_read(r.UC_X86_REG_RIP), self.STOP,
                      uc.reg_read(r.UC_X86_REG_RAX), consumed, len(payload))

    def damage(self, payload, target):
        self._deserialize(150, payload)
        obj = bytes(self.uc.mem_read(self.OUT, 0x30))
        def word(offset):
            values = self.writes[offset]
            if len(values) >= 2:
                return values[-2]  # plaintext write, then object obfuscation
            if obj[offset:offset + 4] == self.templates[150][offset:offset + 4]:
                return 0  # unchanged native zero-initialized field
            raise ValueError('No independently decoded scalar field')
        amount = struct.unpack('<f', bytes(self.table[b] for b in obj[0x10:0x14]))[0]
        if not math.isfinite(amount) or amount < 0 or word(0x14) != target:
            raise ValueError('Nonfinite/negative damage or target/block mismatch')
        return {'amount': amount, 'target': target, 'source': word(0x1c),
                'effect-hash': word(0x2c), 'damage-type': self.types.get(str(obj[0x18])),
                'type-encoded': obj[0x18], 'source-kind-encoded': obj[0x20]}

    def state_buffer(self, payload):
        self._deserialize(287, payload)
        ptr, n, cap = struct.unpack('<QII', self.uc.mem_read(self.OUT + 32, 16))
        if (n > self.MAX_BYTES or cap < n or cap > self.MAX_BYTES
                or n and not self.HEAP <= ptr <= self.heap_cursor - n):
            raise ValueError('Decoded vector budget/bounds exceeded')
        return bytes(self.uc.mem_read(ptr, n)) if n else b''

    def buff(self, opcode, payload):
        """Partial lifecycle fields. Encoded slot is an opaque equality token.

        Counter zero is NOT removal. Missing scalar capture is unknown, never
        inferred from ctor bytes. Buff absence/behavior is outside this method.
        """
        if opcode not in (435, 262, 430):
            raise ValueError('Unsupported buff opcode')
        self._deserialize(opcode, payload)
        obj = bytes(self.uc.mem_read(self.OUT, 128))
        def word(offset):
            values = self.writes[offset]
            return values[-2] if len(values) >= 2 else None
        name_at, slot_at, kind = {435: (0x64, 0x60, 'add'),
                                  262: (0x14, 0x10, 'remove'),
                                  430: (0x18, 0x1c, 'counter')}[opcode]
        name = word(name_at)
        if name is None or not 0 < name <= 0x0fffffff:
            raise ValueError('Buff hash has no independent plaintext capture')
        result = {'kind': kind, 'name-hash': name, 'slot-token': obj[slot_at]}
        if kind == 'add':
            result['caster'] = word(0x1c)
            bits = self.float_words[0x3c]
            duration = struct.unpack('<f', struct.pack('<I', bits[-1]))[0] if bits else None
            if duration is not None and (not math.isfinite(duration) or duration < 0):
                raise ValueError('Nonfinite/negative buff duration')
            result['duration-seconds'] = duration
        if kind == 'counter':
            counter = struct.unpack('<I', bytes(self.counter_table[b] for b in obj[0x10:0x14]))[0]
            if word(0x10) is not None and word(0x10) != counter:
                raise ValueError('Counter codec/plaintext capture disagree')
            result['counter'] = counter
        return result
