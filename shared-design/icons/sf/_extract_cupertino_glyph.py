"""Extract CupertinoIcons glyph outlines to SVG path data."""
from __future__ import annotations

import sys
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont


def extract(ttf: Path, codepoints: list[int], out_dir: Path) -> None:
    font = TTFont(str(ttf))
    glyph_set = font.getGlyphSet()
    cmap = font.getBestCmap()
    units = font["head"].unitsPerEm
    print(f"unitsPerEm={units} numGlyphs={font['maxp'].numGlyphs}")

    for name in (
        "arrow_clockwise_circle_fill",
        "arrow_clockwise_circle",
        "arrow_clockwise",
        "bolt_horizontal_circle_fill",
    ):
        print(f"glyph-by-name {name}: {'YES' if name in glyph_set else 'no'}")

    out_dir.mkdir(parents=True, exist_ok=True)
    # Target viewBox 0 0 24 24, glyph usually has y-up font coords
    target = 24.0
    pad = 1.2

    for cp in codepoints:
        gname = cmap.get(cp)
        print(f"U+{cp:04X} -> {gname}")
        if not gname:
            continue
        glyph = glyph_set[gname]
        pen = SVGPathPen(glyph_set)
        glyph.draw(pen)
        path = pen.getCommands()
        bp = BoundsPen(glyph_set)
        glyph.draw(bp)
        bounds = bp.bounds
        print(f"  bounds={bounds}")
        if not bounds:
            continue

        xmin, ymin, xmax, ymax = bounds
        w = xmax - xmin
        h = ymax - ymin
        side = max(w, h)
        # scale into (pad .. target-pad)
        usable = target - 2 * pad
        scale = usable / side
        # center
        cx = (xmin + xmax) / 2
        cy = (ymin + ymax) / 2

        # Font y-up -> SVG y-down: invert Y around center after scale
        # Transform: translate to origin, scale, flip Y, translate to 12,12
        # SVG transform: translate(12,12) scale(s,-s) translate(-cx,-cy)
        transform = f"translate(12,12) scale({scale:.8f},{-scale:.8f}) translate({-cx:.8f},{-cy:.8f})"

        # Theme yellow like Mac foregroundColor(Theme.yellow) on circle.fill
        # Cutout appears as hole; for standalone SVG use yellow fill of compound path
        svg = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <!-- Extracted from CupertinoIcons.ttf U+{cp:04X} ({gname}) — SF Symbol proxy -->
  <g transform="{transform}">
    <path fill="#FFC400" fill-rule="evenodd" d="{path}"/>
  </g>
</svg>
"""
        # Prefer SF-style names for known icons
        name_map = {
            0xF49C: "arrow.clockwise.circle.fill",
            0xF49B: "arrow.clockwise.circle",
            0xF49A: "arrow.clockwise",
            0xF59B: "bolt.horizontal.circle.fill",
            0xF785: "power",
            0xF598: "bolt.fill",
        }
        out_name = name_map.get(cp, f"U+{cp:04X}")
        out_path = out_dir / f"{out_name}.svg"
        out_path.write_text(svg, encoding="utf-8")
        print(f"  wrote {out_path}")

        # Also dump raw path for debugging
        (out_dir / f"{out_name}.path.txt").write_text(path, encoding="utf-8")


if __name__ == "__main__":
    ttf = Path(sys.argv[1])
    args = sys.argv[2:]
    if args and any(c not in "0123456789abcdefABCDEF" for c in args[-1]):
        out = Path(args[-1])
        cps = [int(x, 16) for x in args[:-1]]
    else:
        out = Path("d:/clev-projects/ClevVPN/shared-design/icons/sf")
        cps = [int(x, 16) for x in args]
    extract(ttf, cps, out)
