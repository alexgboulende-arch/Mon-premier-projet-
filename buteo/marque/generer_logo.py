"""Génère les fichiers SVG de la marque Buteo.

Usage : python3 generer_logo.py <dossier_de_sortie>
Nécessite : pip install fonttools, et la police Inter (Inter Display Black,
Inter SemiBold). Le texte est converti en tracés, donc les SVG produits
s'affichent correctement même sans la police installée.
"""
import math, sys, os
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)

NAVY_1, NAVY_2 = "#0A1230", "#132457"
GREEN_1, GREEN_2 = "#2BF59A", "#10C878"
GOLD = "#FFC53D"
INK = "#0A1230"

def text_path(font_file, text, size, tracking=0.0):
    """Outline `text` into one SVG path; returns (d, width, cap_height)."""
    font = TTFont(font_file)
    gs = font.getGlyphSet()
    cmap = font.getBestCmap()
    upm = font["head"].unitsPerEm
    scale = size / upm
    cap = font["OS/2"].sCapHeight * scale
    pen = SVGPathPen(gs)
    x = 0.0
    for ch in text:
        name = cmap[ord(ch)]
        g = gs[name]
        # flip y: font units are y-up, SVG is y-down; baseline at y = cap
        tp = TransformPen(pen, (scale, 0, 0, -scale, x, cap))
        g.draw(tp)
        x += g.width * scale + tracking * size
    return pen.getCommands(), x - tracking * size, cap

def pentagon(cx, cy, r, rot):
    pts = []
    for i in range(5):
        a = math.radians(rot + i * 72)
        pts.append((cx + r * math.sin(a), cy - r * math.cos(a)))
    return pts

def poly(pts):
    return "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + " Z"

def mark(uid, ball_cx=258, ball_cy=274, eye_fill="none"):
    """Hawk eye whose iris is a football. Drawn in a 512x512 box."""
    R = 74
    c = pentagon(ball_cx, ball_cy, 24, 0)
    seams, patches = [], []
    for i, (vx, vy) in enumerate(c):
        a = math.radians(i * 72)
        ux, uy = math.sin(a), -math.cos(a)
        ox, oy = ball_cx + ux * 76, ball_cy + uy * 76
        patches.append(poly(pentagon(ox, oy, 26, i * 72 + 36)))
        seams.append(f"M{vx:.1f} {vy:.1f} L{ball_cx + ux*54:.1f} {ball_cy + uy*54:.1f}")
    return f'''
  <defs>
    <linearGradient id="g{uid}" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{GREEN_1}"/><stop offset="1" stop-color="{GREEN_2}"/>
    </linearGradient>
    <clipPath id="c{uid}"><circle cx="{ball_cx}" cy="{ball_cy}" r="{R}"/></clipPath>
  </defs>
  <!-- eye -->
  <path d="M60 280 C 130 140, 372 128, 456 262 C 384 404, 150 414, 60 280 Z"
        fill="{eye_fill}" stroke="url(#g{uid})" stroke-width="30" stroke-linejoin="round"/>
  <!-- football iris -->
  <circle cx="{ball_cx}" cy="{ball_cy}" r="{R}" fill="#FFFFFF"/>
  <g clip-path="url(#c{uid})" fill="{INK}">
    {''.join(f'<path d="{p}"/>' for p in patches)}
  </g>
  <path d="{poly(c)}" fill="{INK}"/>
  <path d="{' '.join(seams)}" stroke="{INK}" stroke-width="7" stroke-linecap="round"/>
  <circle cx="{ball_cx}" cy="{ball_cy}" r="{R - 3}" fill="none" stroke="#FFFFFF" stroke-width="6"/>
  <!-- hawk brow: one blade sweeping down toward the front of the eye -->
  <path d="M40 132 C 190 92, 360 104, 478 214 C 470 226, 458 236, 446 242 C 352 166, 208 138, 58 178 Z" fill="{GOLD}"/>
'''

def icon_svg(rounded=True):
    bg = (f'<rect width="512" height="512" rx="{116 if rounded else 0}" fill="url(#bg)"/>')
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{NAVY_2}"/><stop offset="1" stop-color="{NAVY_1}"/>
    </linearGradient>
  </defs>
  {bg}
  <g transform="translate(256 256) scale(0.86) translate(-258 -262)">{mark("i")}</g>
</svg>
'''

INTER_BLACK = "/usr/share/fonts/opentype/inter/InterDisplay-Black.otf"
INTER_SEMI = "/usr/share/fonts/opentype/inter/Inter-SemiBold.otf"

def horizontal_svg(word_color, tag_color, bg=None, eye_fill="none"):
    wd, ww, wcap = text_path(INTER_BLACK, "BUTEO", 150, tracking=0.02)
    td, tw, tcap = text_path(INTER_SEMI, "PRONOSTICS SPORTIFS", 30, tracking=0.28)
    mark_w = 300
    gap = 36
    x_text = mark_w + gap
    width = int(x_text + max(ww, tw) + 20)
    height = 300
    word_y = 58
    tag_y = word_y + wcap + 34
    bgrect = f'<rect width="{width}" height="{height}" fill="{bg}"/>' if bg else ""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}">
  {bgrect}
  <g transform="translate(-6 -2) scale({mark_w/512:.4f}) translate(0 -10)">{mark("h" + word_color[1:], eye_fill=eye_fill)}</g>
  <path transform="translate({x_text} {word_y})" d="{wd}" fill="{word_color}"/>
  <path transform="translate({x_text + 4} {tag_y})" d="{td}" fill="{tag_color}"/>
</svg>
'''

with open(f"{OUT}/buteo-icone.svg", "w") as f:
    f.write(icon_svg())
with open(f"{OUT}/buteo-logo.svg", "w") as f:
    f.write(horizontal_svg("#FFFFFF", GREEN_1))
with open(f"{OUT}/buteo-logo-clair.svg", "w") as f:
    f.write(horizontal_svg(INK, GREEN_2, eye_fill=INK))
with open(f"{OUT}/buteo-symbole.svg", "w") as f:
    f.write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="20 70 480 370" width="480" height="370">{mark("s")}</svg>\n')
print("ok")
with open(f"{OUT}/buteo-icone-carree.svg", "w") as f:
    f.write(icon_svg(rounded=False))
