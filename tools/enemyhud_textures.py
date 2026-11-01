"""Generate EnemyHUD's rounded-shape textures (stdlib only).

  py -I enemyhud_textures.py <EnemyHUD folder>

corner_tl/tr/bl/br.png: panel corners with the gold rim and navy fill baked in (drawn untinted).
cap_l/cap_r.png: white half discs, tinted in game to make pill-shaped bars of any length.
Textures are drawn at high resolution and scaled down in game, so they stay smooth at UI scale 2.
"""
import struct
import sys
import zlib
from pathlib import Path

NAVY = (29, 42, 68, 215)
GOLD = (184, 154, 85, 255)
RADIUS = 6      # UI pixels, must match CORNER in EnemyHUD.lua
SCALE = 8       # texture pixels per UI pixel
SS = 4          # supersamples per axis


def png(width, height, pixels):
    raw = b"".join(b"\x00" + bytes(pixels[y * width * 4:(y + 1) * width * 4]) for y in range(height))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def corner_tl():
    size = RADIUS * SCALE
    r_out, r_in = RADIUS * SCALE, (RADIUS - 1) * SCALE
    px = bytearray(size * size * 4)
    for y in range(size):
        for x in range(size):
            gold = navy = 0
            for sy in range(SS):
                for sx in range(SS):
                    dx = size - (x + (sx + 0.5) / SS)
                    dy = size - (y + (sy + 0.5) / SS)
                    d = (dx * dx + dy * dy) ** 0.5
                    if d <= r_in:
                        navy += 1
                    elif d <= r_out:
                        gold += 1
            n = SS * SS
            cover = (gold + navy) / n
            if cover == 0:
                continue
            g = gold / (gold + navy)
            rgb = [round(GOLD[i] * g + NAVY[i] * (1 - g)) for i in range(3)]
            alpha = (GOLD[3] * gold + NAVY[3] * navy) / n
            px[(y * size + x) * 4:(y * size + x) * 4 + 4] = bytes(rgb + [round(alpha)])
    return size, px


def flip(size, px, horizontal, vertical):
    out = bytearray(len(px))
    for y in range(size):
        for x in range(size):
            sx = size - 1 - x if horizontal else x
            sy = size - 1 - y if vertical else y
            out[(y * size + x) * 4:(y * size + x) * 4 + 4] = px[(sy * size + sx) * 4:(sy * size + sx) * 4 + 4]
    return out


def cap_left():
    w, h = 32, 64
    r = h / 2
    px = bytearray(w * h * 4)
    for y in range(h):
        for x in range(w):
            inside = 0
            for sy in range(SS):
                for sx in range(SS):
                    dx = w - (x + (sx + 0.5) / SS)
                    dy = (y + (sy + 0.5) / SS) - r
                    inside += (dx * dx + dy * dy) <= r * r
            a = round(255 * inside / (SS * SS))
            px[(y * w + x) * 4:(y * w + x) * 4 + 4] = bytes((255, 255, 255, a))
    return w, h, px


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    out = Path(sys.argv[1])
    size, tl = corner_tl()
    for name, h, v in (("tl", False, False), ("tr", True, False), ("bl", False, True), ("br", True, True)):
        (out / f"corner_{name}.png").write_bytes(png(size, size, flip(size, tl, h, v)))
    w, h, left = cap_left()
    right = bytearray(len(left))
    for y in range(h):
        for x in range(w):
            right[(y * w + x) * 4:(y * w + x) * 4 + 4] = left[(y * w + (w - 1 - x)) * 4:(y * w + (w - 1 - x)) * 4 + 4]
    (out / "cap_l.png").write_bytes(png(w, h, left))
    (out / "cap_r.png").write_bytes(png(w, h, right))
    print(f"textures written to {out}")


if __name__ == "__main__":
    main()
