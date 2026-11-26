"""Minimal PNG decode/encode used to make depth and confidence visible.

Depth arrives as 16-bit millimetres and confidence as 0/1/2, so drawing them
directly looks almost black. These helpers normalize depth to a colour ramp
and map confidence levels to distinct colours. Standard library only.
"""

from __future__ import annotations

import struct
import zlib

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class PNGError(ValueError):
    pass


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def decode_png(data: bytes) -> tuple[int, int, int, int, bytes]:
    """Returns width, height, channels, bit_depth and pixel bytes.

    Supports non-interlaced grayscale 8/16-bit and RGB/RGBA 8-bit, which covers
    everything CoreGraphics writes for the capture pipeline.
    """
    if not data.startswith(PNG_SIGNATURE):
        raise PNGError("not a PNG")
    offset = len(PNG_SIGNATURE)
    width = height = bit_depth = color_type = interlace = 0
    idat = bytearray()

    while offset + 8 <= len(data):
        length, kind = struct.unpack_from(">I4s", data, offset)
        offset += 8
        body = data[offset : offset + length]
        offset += length + 4  # skip CRC
        if kind == b"IHDR":
            width, height, bit_depth, color_type, _c, _f, interlace = struct.unpack(
                ">IIBBBBB", body
            )
        elif kind == b"IDAT":
            idat.extend(body)
        elif kind == b"IEND":
            break

    if interlace:
        raise PNGError("interlaced PNG is not supported")
    channels = {0: 1, 2: 3, 4: 2, 6: 4}.get(color_type)
    if channels is None:
        raise PNGError(f"unsupported colour type {color_type}")
    if bit_depth not in (8, 16):
        raise PNGError(f"unsupported bit depth {bit_depth}")

    raw = zlib.decompress(bytes(idat))
    bytes_per_pixel = channels * (bit_depth // 8)
    stride = width * bytes_per_pixel
    out = bytearray(height * stride)
    previous = bytearray(stride)
    pos = 0

    for row in range(height):
        if pos >= len(raw):
            raise PNGError("truncated image data")
        filter_type = raw[pos]
        pos += 1
        line = bytearray(raw[pos : pos + stride])
        if len(line) < stride:
            raise PNGError("truncated scanline")
        pos += stride

        if filter_type == 1:  # Sub
            for i in range(bytes_per_pixel, stride):
                line[i] = (line[i] + line[i - bytes_per_pixel]) & 0xFF
        elif filter_type == 2:  # Up
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 0xFF
        elif filter_type == 3:  # Average
            for i in range(stride):
                left = line[i - bytes_per_pixel] if i >= bytes_per_pixel else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 0xFF
        elif filter_type == 4:  # Paeth
            for i in range(stride):
                left = line[i - bytes_per_pixel] if i >= bytes_per_pixel else 0
                upper_left = previous[i - bytes_per_pixel] if i >= bytes_per_pixel else 0
                line[i] = (line[i] + _paeth(left, previous[i], upper_left)) & 0xFF
        elif filter_type != 0:
            raise PNGError(f"unsupported filter {filter_type}")

        out[row * stride : (row + 1) * stride] = line
        previous = line

    return width, height, channels, bit_depth, bytes(out)


def encode_png(width: int, height: int, rgb: bytes) -> bytes:
    """Encodes an 8-bit RGB image (3 bytes per pixel)."""
    stride = width * 3
    raw = bytearray()
    for row in range(height):
        raw.append(0)  # filter: none
        raw.extend(rgb[row * stride : (row + 1) * stride])

    def chunk(kind: bytes, body: bytes) -> bytes:
        return (
            struct.pack(">I", len(body))
            + kind
            + body
            + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (
        PNG_SIGNATURE
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 6))
        + chunk(b"IEND", b"")
    )


# Blue (far) -> cyan -> yellow -> red (near), readable on light UIs.
_RAMP = [
    (0.00, (31, 41, 89)),
    (0.20, (35, 110, 168)),
    (0.40, (34, 168, 172)),
    (0.60, (126, 197, 92)),
    (0.80, (247, 200, 63)),
    (1.00, (222, 84, 52)),
]


def _ramp_color(t: float) -> tuple[int, int, int]:
    t = min(1.0, max(0.0, t))
    for index in range(len(_RAMP) - 1):
        start, start_color = _RAMP[index]
        end, end_color = _RAMP[index + 1]
        if start <= t <= end:
            span = end - start
            f = 0.0 if span <= 0 else (t - start) / span
            return tuple(int(round(a + (b - a) * f)) for a, b in zip(start_color, end_color))
    return _RAMP[-1][1]


def _percentile(sorted_values: list[int], fraction: float) -> int:
    if not sorted_values:
        return 0
    index = min(len(sorted_values) - 1, max(0, int(fraction * (len(sorted_values) - 1))))
    return sorted_values[index]


def colorize_depth(data: bytes) -> bytes:
    """16-bit millimetre depth -> 8-bit RGB PNG (near = warm)."""
    if not data:
        return b""
    try:
        width, height, _channels, bit_depth, pixels = decode_png(data)
    except (PNGError, zlib.error):
        return data  # thumbnails are decorative: fall back to the original

    count = width * height
    if bit_depth == 16:
        values = list(struct.unpack_from(f"<{count}H", pixels, 0))
    else:
        values = list(pixels[:count])

    valid = sorted(v for v in values if v > 0)
    if not valid:
        return encode_png(width, height, bytes([16, 20, 28]) * count)

    low = _percentile(valid, 0.02)
    high = _percentile(valid, 0.98)
    if high <= low:
        high = low + 1

    out = bytearray(count * 3)
    for index, value in enumerate(values):
        if value == 0:
            out[index * 3 : index * 3 + 3] = bytes((26, 31, 43))
        else:
            out[index * 3 : index * 3 + 3] = bytes(_ramp_color((value - low) / (high - low)))
    return encode_png(width, height, bytes(out))


_CONFIDENCE_COLORS = {
    0: (198, 62, 62),    # low
    1: (232, 158, 48),   # medium
    2: (58, 165, 118),   # high
}


def colorize_confidence(data: bytes) -> bytes:
    """Confidence 0/1/2 -> 8-bit RGB PNG with red/amber/green levels."""
    if not data:
        return b""
    try:
        width, height, _channels, bit_depth, pixels = decode_png(data)
    except (PNGError, zlib.error):
        return data

    count = width * height
    out = bytearray(count * 3)
    for index in range(count):
        if bit_depth == 16:
            level = struct.unpack_from("<H", pixels, index * 2)[0]
        else:
            level = pixels[index]
        colour = _CONFIDENCE_COLORS.get(int(level), (140, 140, 150))
        out[index * 3 : index * 3 + 3] = bytes(colour)
    return encode_png(width, height, bytes(out))
