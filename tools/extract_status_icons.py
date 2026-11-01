"""Extract FFXI status icons (ROM/119/57.DAT) to PNG files named by status id, e.g. 2.png = Sleep.

  py -I extract_status_icons.py <57.DAT> <output folder>

The DAT holds 640 entries of 0x1800 bytes. Entry N is status id N: a 32x32, 32-bit bitmap whose
BITMAPINFOHEADER sits at 0x295, rows bottom-up in BGRA, with FFXI's alpha range 0..0x80.
Stdlib only (PNG written with zlib).
"""
import struct
import sys
import zlib
from pathlib import Path

ENTRY = 0x1800
HEADER_AT = 0x295
SIZE = 32


def png_bytes(rgba_rows):
    raw = b"".join(b"\x00" + row for row in rgba_rows)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def icon_rows(entry):
    size, width, height, planes, bpp = struct.unpack_from("<IiiHH", entry, HEADER_AT)
    if (size, width, height, bpp) != (40, SIZE, SIZE, 32):
        return None
    pixels = entry[HEADER_AT + 40:HEADER_AT + 40 + SIZE * SIZE * 4]
    rows = []
    for y in range(SIZE - 1, -1, -1):  # bottom-up
        src = pixels[y * SIZE * 4:(y + 1) * SIZE * 4]
        row = bytearray(SIZE * 4)
        for x in range(SIZE):
            b, g, r, a = src[x * 4:x * 4 + 4]
            row[x * 4:x * 4 + 4] = bytes((r, g, b, min(255, a * 2)))
        rows.append(bytes(row))
    return rows


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    data = Path(sys.argv[1]).read_bytes()
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    written = 0
    for status_id in range(len(data) // ENTRY):
        rows = icon_rows(data[status_id * ENTRY:(status_id + 1) * ENTRY])
        if rows and any(any(row[3::4]) for row in rows):  # skip fully transparent slots
            (out / f"{status_id}.png").write_bytes(png_bytes(rows))
            written += 1
    print(f"{written} icons written to {out}")


if __name__ == "__main__":
    main()
