#!/usr/bin/env python3
"""Builds the Windows app icon from the app icon artwork.

An .ico that holds a single 256x256 entry leaves Windows to scale the icon
down for the taskbar, the Explorer view and the small sizes, where it turns
into a blue smudge. One entry per size gives each of them a sharp image.

The artwork is the app icon the other platforms use, so the Windows icon is
the same picture everywhere.

Usage: scripts/build_windows_icon.py
"""

import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "images" / "source" / "ic_launcher_border.png"
TARGETS = [
    ROOT / "windows" / "runner" / "resources" / "app_icon.ico",
    ROOT / "assets" / "images" / "source" / "hiddify.ico",
]

# The sizes Windows asks for, from the smallest to the largest.
SIZES = [16, 24, 32, 48, 64, 128, 256]


def scaled(source, size, out):
    """Writes [source] scaled to [size]x[size] as a PNG."""
    subprocess.run(
        ["sips", "-z", str(size), str(size), str(source), "--out", str(out)],
        check=True,
        capture_output=True,
    )
    return out.read_bytes()


def build_ico(images):
    """Packs the PNGs into an .ico, one directory entry per size."""
    header = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    directory = b""
    body = b""
    for size, payload in images:
        directory += struct.pack(
            "<BBBBHHII",
            size if size < 256 else 0,
            size if size < 256 else 0,
            0,
            0,
            1,
            32,
            len(payload),
            offset,
        )
        offset += len(payload)
        body += payload
    return header + directory + body


def main():
    if not SOURCE.exists():
        raise SystemExit(f"{SOURCE} does not exist")

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        images = [(size, scaled(SOURCE, size, tmp / f"{size}.png")) for size in SIZES]
        ico = build_ico(images)

    for target in TARGETS:
        target.write_bytes(ico)
        count = struct.unpack("<H", ico[4:6])[0]
        print(f"{target.relative_to(ROOT)}: {count} entries, {len(ico)} bytes")

    return 0


if __name__ == "__main__":
    sys.exit(main())
