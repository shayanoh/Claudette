"""Claudette sleep-scene art (5-hour nap and weekly deep sleep), style B.
Same contract as parts.py: points, y down, pivot at (0,0), returns (svg, box). No text."""
from parts import C, INK as BODY_INK, rr
from props import INK, INK_C, PAPER, PAPER_D, gloss, _id, star4

NIGHT_IN, NIGHT_OUT = "#1D2440", "#3B3F66"
BLANKET, BLANKET_D, BLANKET_L, STITCH = "#7B8FD1", "#5A6CB0", "#9AACE3", "#4A5A9C"
SPARKLE = "#FFE9A8"

# ---------------------------------------------------------------- signs
DOODLE_W, TEXT_PAD = 30, 8  # left doodle zone and right padding inside the board


def sign_layout(w):
    """Board width -> (x0 of text area, x1 of text area, label centre x)."""
    x0, x1 = -w / 2 + DOODLE_W, w / 2 - TEXT_PAD
    return x0, x1, (x0 + x1) / 2


def _board(w, h, paper, shade, doodle):
    iw, ih = w - INK, h - INK
    d = rr(-iw / 2, -ih / 2, iw, ih, 7)
    cid = _id("s")
    svg = (f'<defs><clipPath id="{cid}"><path d="{d}"/></clipPath></defs>'
           f'<path d="{d}" fill="{shade}"/>'
           f'<g clip-path="url(#{cid})"><path d="{d}" transform="translate(-3,-3)" fill="{paper}"/>'
           + gloss(-iw / 2 + 6, -ih / 2 + 3, iw * 0.3, 2.4, 0.7) + "</g>"
           f'<path d="{d}" fill="none" stroke="{INK_C}" stroke-width="{INK}"/>' + doodle)
    return svg, (-w / 2, -h / 2, w / 2, h / 2)


def _crescent(cx, cy, r, fill):
    """Crescent via masks: an ink crescent under a slightly thinner coloured one."""
    out = ""
    for grow, col in ((1.2, INK_C), (0, fill)):
        mid = _id("m")
        out += (f'<mask id="{mid}"><circle cx="{cx}" cy="{cy}" r="{r+grow}" fill="#fff"/>'
                f'<circle cx="{cx+r*0.55}" cy="{cy-r*0.35}" r="{r*0.85-grow}" fill="#000"/></mask>'
                f'<circle cx="{cx}" cy="{cy}" r="{r+grow}" fill="{col}" mask="url(#{mid})"/>')
    return out


NAP_W, DEEP_W, SIGN_H = 190, 150, 34


def sign_nap():
    x = -NAP_W / 2 + DOODLE_W / 2
    doodle = _crescent(x - 2, 1, 7, "#FFC94D") + star4(x + 7, -6, 3.6, "#FFE9A8")
    return _board(NAP_W, SIGN_H, PAPER, PAPER_D, doodle)


def sign_deep():
    x = -DEEP_W / 2 + DOODLE_W / 2
    doodle = (f'<circle cx="{x}" cy="0" r="7.5" fill="#2A2E52" stroke="{INK_C}" stroke-width="1.8"/>'
              f'<path d="M{x+3.5},-5.5 A6,6 0 0 1 {x+5.5},3" stroke="#FFD9A0" stroke-width="1.4" '
              f'fill="none" stroke-linecap="round" opacity="0.8"/>')
    return _board(DEEP_W, SIGN_H, "#E9E6F5", "#C9C4E0", doodle)


# ---------------------------------------------------------------- blankets
def _wave(x0, x1, y, amp, period):
    n = max(2, round((x1 - x0) / period))
    step = (x1 - x0) / n
    d = f"Q{x0+step/4:.2f},{y-amp:.2f} {x0+step/2:.2f},{y:.2f} "
    for i in range(1, 2 * n):
        d += f"T{x0+step/2*(i+1):.2f},{y:.2f} "
    return d


def _blanket(w, top, pattern, cid):
    """Quilt with a wavy top edge; visible bottom edge (outer ink) on the pivot."""
    hw, b, amp = w / 2 - BODY_INK / 2, -BODY_INK / 2, 3
    yw = -top + BODY_INK / 2 + amp / 2  # T-chain crests sit amp/2 above the baseline
    d = (f"M{-hw},{yw} " + _wave(-hw, hw, yw, amp, 38)
         + f"V{b-6} Q{hw},{b} {hw-6},{b} H{-hw+6} Q{-hw},{b} {-hw},{b-6} Z")
    svg = (f'<defs><clipPath id="{cid}"><path d="{d}"/></clipPath></defs>'
           f'<path d="{d}" fill="{BLANKET_D}"/>'
           f'<g clip-path="url(#{cid})"><path d="{d}" transform="translate(-5,-6)" fill="{BLANKET}"/>'
           f'{pattern}</g>'
           f'<path d="{d}" fill="none" stroke="{INK_C}" stroke-width="{BODY_INK}" stroke-linejoin="round"/>')
    return svg, (-w / 2, -top, w / 2, 0)


BLANKET_TOP, DEEP_TOP = 39, 45  # visible heights: tops at y 37 / 43 in bodyPivot space


def blanket():
    """Stitched patchwork: lighter square patches in a checker, dashed stitch lines."""
    p = ""
    for i, x in enumerate(range(-80, 80, 20)):
        for j, y in enumerate(range(-44, 0, 15)):
            if (i + j) % 2 == 0:
                p += f'<rect x="{x}" y="{y}" width="20" height="15" fill="{BLANKET_L}" opacity="0.55"/>'
    for x in range(-60, 80, 20):
        p += f'<path d="M{x},-44 V0" stroke="{STITCH}" stroke-width="1" stroke-dasharray="2 2" opacity="0.8"/>'
    for y in (-29, -14):
        p += f'<path d="M-80,{y} H80" stroke="{STITCH}" stroke-width="1" stroke-dasharray="2 2" opacity="0.8"/>'
    return _blanket(160, BLANKET_TOP, p, "blk")


def blanket_deep():
    """Pulled higher; scattered stars and crescents."""
    p = ""
    spots = [(-60, -30), (-34, -14), (-8, -34), (18, -18), (44, -32), (64, -12), (-70, -10), (30, -6)]
    for i, (x, y) in enumerate(spots):
        if i % 3 == 1:
            mid = _id("bm")
            p += (f'<mask id="{mid}"><circle cx="{x}" cy="{y}" r="4" fill="#fff"/>'
                  f'<circle cx="{x+2.2}" cy="{y-1.4}" r="3.4" fill="#000"/></mask>'
                  f'<circle cx="{x}" cy="{y}" r="4" fill="{SPARKLE}" mask="url(#{mid})"/>')
        else:
            k = 3.2 * 0.28
            p += (f'<path d="M{x},{y-3.2} Q{x+k},{y-k} {x+3.2},{y} Q{x+k},{y+k} {x},{y+3.2} '
                  f'Q{x-k},{y+k} {x-3.2},{y} Q{x-k},{y-k} {x},{y-3.2} Z" fill="{SPARKLE}"/>')
    return _blanket(164, DEEP_TOP, p, "bld")


# ---------------------------------------------------------------- night
PATCH_W, PATCH_H = 300, 250


def night_patch():
    """Navy glow card, transparent at every edge, a few tiny sparkles. Pivot = bottom-centre."""
    sparkles = [(-92, -190, 2.6), (-40, -215, 1.8), (58, -205, 2.4), (100, -150, 1.8),
                (-115, -120, 1.8), (82, -95, 2.0), (-70, -70, 1.6), (12, -228, 1.6)]
    stars = ""
    for x, y, r in sparkles:
        k = r * 0.28
        stars += (f'<path d="M{x},{y-r} Q{x+k},{y-k} {x+r},{y} Q{x+k},{y+k} {x},{y+r} '
                  f'Q{x-k},{y+k} {x-r},{y} Q{x-k},{y-k} {x},{y-r} Z" fill="{SPARKLE}" opacity="0.9"/>')
    svg = ('<defs><radialGradient id="np" cx="0.5" cy="0.5" r="0.5">'
           f'<stop offset="0" stop-color="{NIGHT_IN}" stop-opacity="0.8"/>'
           f'<stop offset="0.5" stop-color="#2B3256" stop-opacity="0.72"/>'
           f'<stop offset="0.8" stop-color="{NIGHT_OUT}" stop-opacity="0.35"/>'
           f'<stop offset="1" stop-color="{NIGHT_OUT}" stop-opacity="0"/></radialGradient></defs>'
           f'<rect x="{-PATCH_W/2}" y="{-PATCH_H}" width="{PATCH_W}" height="{PATCH_H}" fill="url(#np)"/>' + stars)
    # Box shrunk by the 1 pt export margin so the canvas lands on exactly 300x250.
    return svg, (-PATCH_W / 2 + 1, -PATCH_H + 1, PATCH_W / 2 - 1, 0)


# ---------------------------------------------------------------- moon and twinkle
def moon_new():
    """56 pt new moon: dark disc, faint warm rim on the upper right, dimples, ink outline."""
    r = 28 - INK / 2
    cid, fid = _id("mn"), _id("mf")
    svg = (f'<defs><clipPath id="{cid}"><circle r="{r}"/></clipPath>'
           f'<filter id="{fid}" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="1.4"/></filter></defs>'
           f'<g clip-path="url(#{cid})"><circle r="{r}" fill="#FFD9A0" opacity="0.55"/>'
           f'<circle cx="-3.5" cy="3" r="{r}" fill="#2A2E52" filter="url(#{fid})"/>'
           f'<circle cx="-8" cy="-6" r="5.5" fill="#20243F"/><path d="M-12.5,-3.5 A5.5,5.5 0 0 0 -3,-3" '
           f'stroke="#3A3F6A" stroke-width="1.2" fill="none"/>'
           f'<circle cx="9" cy="9" r="3.6" fill="#20243F"/><circle cx="3" cy="-14" r="2.4" fill="#20243F"/>'
           f'<circle cx="-12" cy="12" r="2" fill="#20243F"/></g>'
           f'<circle r="{r}" fill="none" stroke="{INK_C}" stroke-width="{INK}"/>')
    return svg, (-28, -28, 28, 28)


def star_twinkle():
    """12x12 sparkle with a soft ink-less glow."""
    fid = _id("tw")
    r, k = 4.6, 4.6 * 0.28
    svg = (f'<defs><filter id="{fid}" x="-100%" y="-100%" width="300%" height="300%">'
           f'<feGaussianBlur stdDeviation="0.9"/></filter></defs>'
           f'<circle r="2.4" fill="{SPARKLE}" opacity="0.7" filter="url(#{fid})"/>'
           f'<path d="M0,{-r} Q{k},{-k} {r},0 Q{k},{k} 0,{r} Q{-k},{k} {-r},0 Q{-k},{-k} 0,{-r} Z" fill="{SPARKLE}"/>')
    return svg, (-5, -5, 5, 5)
