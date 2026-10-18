"""ROFL2 block framing with signed relative entity IDs.

RoflLens 0.1.0 remains the container/decompression dependency. Its block iterator
adds relative params as unsigned bytes, which invents IDs offset by 256. This
adapter implements the signed delta documented by ROFL-X at commit
88954be66da506f188fbd134944fdfd8334ad846, src/rofl/block.rs. No payload semantics
or old patch packet IDs are inherited here.
"""
from dataclasses import dataclass
import math
import struct


@dataclass(frozen=True)
class Block:
    stream: str
    stream_id: int
    chunk_id: int
    block_offset: int
    timestamp: float
    packet_id: int
    param: int
    payload_length: int
    payload: bytes | None


def chunk_blocks(body, chunk, *, opcodes=None, include_payload=False):
    cursor = 0
    timestamp = 0.0
    packet_id = param = 0

    def read(fmt):
        nonlocal cursor
        size = struct.calcsize(fmt)
        if cursor + size > len(body):
            raise ValueError(f'Truncated block in chunk {chunk.chunk_id} at {offset}')
        value = struct.unpack_from(fmt, body, cursor)[0]
        cursor += size
        return value

    while cursor < len(body):
        offset = cursor
        marker = read('<B')
        timestamp = timestamp + read('<B') * .001 if marker & 0x80 else read('<f')
        if not math.isfinite(timestamp) or timestamp < 0:
            raise ValueError(f'Invalid timestamp in chunk {chunk.chunk_id} at {offset}')
        length = read('<B') if marker & 0x10 else read('<I')
        if not marker & 0x40:
            packet_id = read('<H')
        param = (param + read('<b')) & 0xffffffff if marker & 0x20 else read('<I')
        if cursor + length > len(body):
            raise ValueError(f'Truncated payload in chunk {chunk.chunk_id} at {offset}')
        payload = body[cursor:cursor + length] if include_payload else None
        cursor += length
        # Filter after updating framing state, including unselected packet IDs.
        if opcodes is None or packet_id in opcodes:
            yield Block(chunk.stream_name, chunk.stream, chunk.chunk_id, offset,
                        timestamp, packet_id, param, length, payload)


def iter_blocks(replay, *, streams=None, opcodes=None, include_payload=False):
    for chunk in replay.chunks(verify=False):
        if streams is not None and chunk.stream_name not in streams and chunk.stream not in streams:
            continue
        yield from chunk_blocks(replay.read_chunk_body(chunk, verify=True), chunk,
                                opcodes=opcodes, include_payload=include_payload)
