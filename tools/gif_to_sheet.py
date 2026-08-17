#!/usr/bin/env python3
"""Turn animated GIFs into sprite sheets Godot can read.

Godot can't read animated GIFs, so authored art lands here as GIFs and this
converts it (no third-party libraries: pure GIF89a LZW plus a hand-rolled PNG
writer). Two layouts, because the two things that animate want different ones:

  sheet (default) — one row per facing (S, SE, E, NE, N, NW, W, SW), one column
  per walk frame, built from a folder of per-direction GIFs. See
  data/colonists.json for that contract.

      python3 tools/gif_to_sheet.py assets/characters assets/colonist.png

  Frames are trimmed to a common bounding box across every direction, so the
  figure keeps its footing between facings, and the anchor (the pixel the
  colonist stands on) is printed for pasting into data/colonists.json.

  strip — one GIF to one horizontal row of frames. For map objects (see
  data/objects.json), where several separate animations of the same thing have
  to line up with each other.

      python3 tools/gif_to_sheet.py --strip in.gif out.png

  Deliberately *not* trimmed: an asteroid's fall, crash and at-rest art are
  three files that must share one frame box and one anchor, and trimming each
  to its own contents is exactly what would make the rock jump between them.
"""

import os
import re
import struct
import sys
import zlib

# Sheet row order. The renderer treats row 0 as "facing the camera".
FACINGS = ["south", "south-east", "east", "north-east",
           "north", "north-west", "west", "south-west"]


# --- GIF decoding ------------------------------------------------------------

class Reader:
    def __init__(self, data):
        self.d = data
        self.i = 0

    def u8(self):
        v = self.d[self.i]
        self.i += 1
        return v

    def u16(self):
        v = struct.unpack_from("<H", self.d, self.i)[0]
        self.i += 2
        return v

    def take(self, n):
        v = self.d[self.i:self.i + n]
        self.i += n
        return v

    def blocks(self):
        """Concatenated sub-blocks, terminated by a zero-length block."""
        out = bytearray()
        while True:
            n = self.u8()
            if n == 0:
                return bytes(out)
            out += self.take(n)


def lzw_decode(min_code_size, data):
    """Standard GIF variable-width LZW."""
    clear = 1 << min_code_size
    end = clear + 1
    code_size = min_code_size + 1
    table = [bytes([i]) for i in range(clear)] + [b"", b""]
    out = bytearray()
    prev = None
    bitpos = 0
    total_bits = len(data) * 8
    while bitpos + code_size <= total_bits:
        byte = bitpos >> 3
        chunk = int.from_bytes(data[byte:byte + 3].ljust(3, b"\0"), "little")
        code = (chunk >> (bitpos & 7)) & ((1 << code_size) - 1)
        bitpos += code_size
        if code == clear:
            table = [bytes([i]) for i in range(clear)] + [b"", b""]
            code_size = min_code_size + 1
            prev = None
            continue
        if code == end:
            break
        if code < len(table):
            entry = table[code]
        elif prev is not None:
            entry = prev + prev[:1]
        else:
            break
        out += entry
        if prev is not None:
            table.append(prev + entry[:1])
            if len(table) == (1 << code_size) and code_size < 12:
                code_size += 1
        prev = entry
    return bytes(out)


def decode_gif(path):
    """Returns (width, height, [frame, ...]) with each frame a flat RGBA list."""
    r = Reader(open(path, "rb").read())
    if r.take(6) not in (b"GIF87a", b"GIF89a"):
        raise ValueError("%s is not a GIF" % path)
    w, h = r.u16(), r.u16()
    packed = r.u8()
    r.u8()  # background colour index
    r.u8()  # pixel aspect ratio
    gct = []
    if packed & 0x80:
        for _ in range(2 << (packed & 7)):
            gct.append(tuple(r.take(3)))

    canvas = [(0, 0, 0, 0)] * (w * h)
    frames = []
    transparent = None
    disposal = 0
    while r.i < len(r.d):
        block = r.u8()
        if block == 0x3B:            # trailer
            break
        if block == 0x21:            # extension
            label = r.u8()
            if label == 0xF9:        # graphic control
                r.u8()               # block size (always 4)
                flags = r.u8()
                r.u16()              # delay
                idx = r.u8()
                r.u8()               # block terminator
                disposal = (flags >> 2) & 7
                transparent = idx if flags & 1 else None
            else:
                r.blocks()
            continue
        if block != 0x2C:            # anything else: not an image descriptor
            continue

        left, top, iw, ih = r.u16(), r.u16(), r.u16(), r.u16()
        ipacked = r.u8()
        palette = gct
        if ipacked & 0x80:
            palette = [tuple(r.take(3)) for _ in range(2 << (ipacked & 7))]
        interlaced = bool(ipacked & 0x40)
        min_code_size = r.u8()
        indices = lzw_decode(min_code_size, r.blocks())

        rows = list(range(ih))
        if interlaced:
            rows = (list(range(0, ih, 8)) + list(range(4, ih, 8))
                    + list(range(2, ih, 4)) + list(range(1, ih, 2)))
        before = list(canvas)
        for n, y in enumerate(rows):
            for x in range(iw):
                p = n * iw + x
                if p >= len(indices):
                    break
                idx = indices[p]
                if transparent is not None and idx == transparent:
                    continue
                if idx >= len(palette):
                    continue
                cx, cy = left + x, top + y
                if 0 <= cx < w and 0 <= cy < h:
                    canvas[cy * w + cx] = palette[idx] + (255,)
        frames.append(list(canvas))
        if disposal == 2:
            for y in range(top, min(top + ih, h)):
                for x in range(left, min(left + iw, w)):
                    canvas[y * w + x] = (0, 0, 0, 0)
        elif disposal == 3:
            canvas = before
    return w, h, frames


# --- PNG writing -------------------------------------------------------------

def write_png(path, w, h, pixels):
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter: none
        for x in range(w):
            raw += bytes(pixels[y * w + x])

    def chunk(tag, payload):
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
           + chunk(b"IEND", b""))
    open(path, "wb").write(png)


# --- Sheet assembly ----------------------------------------------------------

def find_gifs(folder):
    """direction -> path, matched on the direction word in the filename."""
    found = {}
    for name in sorted(os.listdir(folder)):
        if not name.lower().endswith(".gif"):
            continue
        stem = re.sub(r"[^a-z]+", "-", os.path.splitext(name)[0].lower())
        for facing in sorted(FACINGS, key=len, reverse=True):
            if stem.endswith("-" + facing) and facing not in found:
                found[facing] = os.path.join(folder, name)
                break
    missing = [f for f in FACINGS if f not in found]
    if missing:
        raise SystemExit("missing a GIF for: %s" % ", ".join(missing))
    return found


def bounds(frames, w, h):
    """Tight bounding box of every non-transparent pixel across all frames."""
    x0, y0, x1, y1 = w, h, -1, -1
    for frame in frames:
        for y in range(h):
            for x in range(w):
                if frame[y * w + x][3]:
                    x0, y0 = min(x0, x), min(y0, y)
                    x1, y1 = max(x1, x), max(y1, y)
    return x0, y0, x1, y1


def write_strip(src, dst):
    """One GIF -> one horizontal row of full-canvas frames."""
    w, h, frames = decode_gif(src)
    sheet_w = w * len(frames)
    sheet = [(0, 0, 0, 0)] * (sheet_w * h)
    for col, frame in enumerate(frames):
        for y in range(h):
            for x in range(w):
                sheet[y * sheet_w + col * w + x] = frame[y * w + x]
    write_png(dst, sheet_w, h, sheet)
    print("wrote %s  (%dx%d, %d frames of %dx%d)"
          % (dst, sheet_w, h, len(frames), w, h))
    return len(frames), w, h


def main():
    if "--strip" in sys.argv:
        args = [a for a in sys.argv[1:] if a != "--strip"]
        if len(args) != 2:
            raise SystemExit("usage: gif_to_sheet.py --strip <in.gif> <out.png>")
        write_strip(args[0], args[1])
        return

    folder = sys.argv[1] if len(sys.argv) > 1 else "assets/characters"
    out = sys.argv[2] if len(sys.argv) > 2 else "assets/colonist.png"
    gifs = find_gifs(folder)

    decoded = {}
    for facing, path in gifs.items():
        decoded[facing] = decode_gif(path)

    w = h = None
    box = None
    counts = set()
    for facing in FACINGS:
        fw, fh, frames = decoded[facing]
        w, h = fw, fh
        counts.add(len(frames))
        b = bounds(frames, fw, fh)
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]),
                                     max(box[2], b[2]), max(box[3], b[3]))
    frame_count = max(counts)
    x0, y0, x1, y1 = box
    fw, fh = x1 - x0 + 1, y1 - y0 + 1

    sheet_w, sheet_h = fw * frame_count, fh * len(FACINGS)
    sheet = [(0, 0, 0, 0)] * (sheet_w * sheet_h)
    for row, facing in enumerate(FACINGS):
        _, _, frames = decoded[facing]
        for col in range(frame_count):
            frame = frames[col % len(frames)]
            for y in range(fh):
                for x in range(fw):
                    px = frame[(y0 + y) * w + (x0 + x)]
                    sheet[(row * fh + y) * sheet_w + col * fw + x] = px

    write_png(out, sheet_w, sheet_h, sheet)
    print("wrote %s  (%dx%d)" % (out, sheet_w, sheet_h))
    print("  rows   : %s" % ", ".join(FACINGS))
    print("  frames : %d per row (source frame counts: %s)"
          % (frame_count, sorted(counts)))
    print("  data/colonists.json →  \"frame_size\": [%d, %d], \"walk_frames\": %d,"
          "  \"anchor\": [%d, %d]" % (fw, fh, frame_count, fw // 2, fh - 1))


if __name__ == "__main__":
    main()
