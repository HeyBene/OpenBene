from openbene_receiver.pngviz import colorize_confidence, colorize_depth, decode_png, encode_png
import struct
import zlib


def _png(width: int, height: int, values: list[int], bit_depth: int) -> bytes:
    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    raw = bytearray()
    for row in range(height):
        raw.append(0)
        slice_ = values[row * width : (row + 1) * width]
        raw.extend(struct.pack(f"<{width}H", *slice_) if bit_depth == 16 else bytes(slice_))
    header = struct.pack(">IIBBBBB", width, height, bit_depth, 0, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(bytes(raw))) + chunk(b"IEND", b"")


def test_colorize_depth_produces_rgb_and_skips_invalid():
    # 16-bit millimetres, one zero pixel (no return).
    png = _png(3, 1, [0, 500, 3000], 16)
    out = colorize_depth(png)
    width, height, channels, depth = decode_png(out)[:4]
    assert (width, height, channels, depth) == (3, 1, 3, 8)
    # Zero pixels stay dark, real depth becomes a distinct colour.
    assert decode_png(out)[4][:3] == bytes((26, 31, 43))


def test_colorize_confidence_maps_levels_to_three_colours():
    png = _png(3, 1, [0, 1, 2], 8)
    out = colorize_confidence(png)
    pixels = decode_png(out)[4]
    colours = {pixels[0:3], pixels[3:6], pixels[6:9]}
    assert len(colours) == 3


def test_colorize_passes_through_unknown_data():
    assert colorize_depth(b"not-a-png") == b"not-a-png"
    assert colorize_confidence(b"not-a-png") == b"not-a-png"


def test_encode_roundtrip():
    data = bytes([255, 0, 0, 0, 255, 0])
    png = encode_png(2, 1, data)
    assert decode_png(png) == (2, 1, 3, 8, data)
