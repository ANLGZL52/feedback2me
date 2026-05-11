#!/usr/bin/env python3
"""Remove horizontal white letterboxing from square app icon PNGs.

Apple / flutter_launcher_icons expect a full-bleed square; white side bars
in the source become visible on the App Store. This script detects columns
that are mostly white and replaces only those margin pixels with the icon
corner background color (does not touch white inside the artwork).
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image


def column_white_fraction(im: Image.Image, x: int, white_lo: int = 245) -> float:
    w, h = im.size
    n = 0
    for y in range(h):
        r, g, b, *_ = im.getpixel((x, y))
        if r > white_lo and g > white_lo and b > white_lo:
            n += 1
    return n / h


def margin_columns(im: Image.Image, frac_threshold: float = 0.15) -> tuple[int, int]:
    w, _h = im.size
    left = None
    for x in range(w):
        if column_white_fraction(im, x) < frac_threshold:
            left = x
            break
    if left is None:
        return 0, w - 1
    right = None
    for x in range(w - 1, -1, -1):
        if column_white_fraction(im, x) < frac_threshold:
            right = x
            break
    if right is None:
        return left, w - 1
    return left, right


def fix_icon(path: Path, out: Path | None = None) -> None:
    out = out or path
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    if w != h:
        raise SystemExit(f"Expected square icon, got {w}x{h}: {path}")

    corner = im.getpixel((0, 0))
    if len(corner) == 4 and corner[3] == 0:
        corner = (13, 17, 23, 255)
    left, right = margin_columns(im)
    fill = (corner[0], corner[1], corner[2], 255)
    px = im.load()
    changed = 0
    for y in range(h):
        for x in range(w):
            if left <= x <= right:
                continue
            r, g, b, a = px[x, y]
            if r > 245 and g > 245 and b > 245 and a > 200:
                px[x, y] = fill
                changed += 1
    rgb = im.convert("RGB")
    rgb.save(out, format="PNG", optimize=True)
    print(f"{path.name}: margins columns x<{left} or x>{right}, replaced {changed} px -> {out}")


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    p = root / "assets" / "app_icon.png"
    if not p.is_file():
        raise SystemExit(f"Missing {p}")
    fix_icon(p)
    print("Sonra: dart run flutter_launcher_icons")


if __name__ == "__main__":
    main()
