"""Claudette rig parts, style B "Ink & Cel" (+ style A's blurred contact shadow).

Adapted from design/concepts/opus/src/claudette.py (style "cel").
Every part is drawn in its own PIVOT-LOCAL space: SVG units = points, y DOWN, the
node's pivot at (0, 0). Each function returns (svg_fragment, box) where box is the
drawn extent (x0, y0, x1, y1) in that space, including outline/blur.
"""
import math

INK = 4.6  # 4.6 per 123 tall: about 3.6 pt at 96 pt on screen, never under 3
HALF = INK / 2

C = dict(
    base="#E07C56", shade="#B0503A", leg="#C9643F", legd="#9C4430",
    outline="#3A1A12", eye="#26100B", cheek="#F0827A", hatch="#C93E3A",
    light="#FFE2CF", spark="#FFB48F", tongue="#E0675A",
)

CEL_EYE = (
    '<linearGradient id="celEye" x1="0" y1="0" x2="0" y2="1">'
    '<stop offset="0" stop-color="#1C0B07"/><stop offset="0.55" stop-color="#2A120C"/>'
    '<stop offset="0.56" stop-color="#5B2416"/><stop offset="1" stop-color="#B4482C"/>'
    "</linearGradient>"
)


def rr(x, y, w, h, r):
    r = min(r, w / 2, h / 2)
    return (f"M{x+r:.2f},{y:.2f} H{x+w-r:.2f} Q{x+w:.2f},{y:.2f} {x+w:.2f},{y+r:.2f} "
            f"V{y+h-r:.2f} Q{x+w:.2f},{y+h:.2f} {x+w-r:.2f},{y+h:.2f} H{x+r:.2f} "
            f"Q{x:.2f},{y+h:.2f} {x:.2f},{y+h-r:.2f} V{y+r:.2f} Q{x:.2f},{y:.2f} {x+r:.2f},{y:.2f} Z")


def grow(x0, y0, x1, y1, d):
    return (x0 - d, y0 - d, x1 + d, y1 + d)


# ---------------------------------------------------------------- parts
def shadow(width=150):
    """Style A contact shadow: two blurred ellipses, centred on the pivot."""
    rx, ry, blur = width / 2, 9, 4
    svg = (f'<defs><filter id="b4" x="-50%" y="-50%" width="200%" height="200%">'
           f'<feGaussianBlur stdDeviation="{blur}"/></filter>'
           f'<filter id="b2" x="-50%" y="-50%" width="200%" height="200%">'
           f'<feGaussianBlur stdDeviation="2"/></filter></defs>'
           f'<ellipse cx="0" cy="0" rx="{rx}" ry="{ry}" fill="#5A2A18" opacity="0.28" filter="url(#b4)"/>'
           f'<ellipse cx="0" cy="-1" rx="{rx*0.7}" ry="4" fill="#3A1A10" opacity="0.25" filter="url(#b2)"/>')
    return svg, grow(-rx, -ry, rx, ry, 3 * blur)


LEG_W, LEG_LEN, LEG_TUCK = 14, 23, 8  # tuck: hidden length above the hip, so rotation never gaps


def leg():
    """Pivot = hip (top-centre of the visible leg)."""
    x, y, w, h = -LEG_W / 2, -LEG_TUCK, LEG_W, LEG_LEN + LEG_TUCK
    d = rr(x, y, w, h, 4)
    svg = (f'<path d="{d}" fill="{C["leg"]}"/>'
           f'<rect x="{x+w-5}" y="{y+2}" width="4" height="{h-4}" fill="{C["legd"]}"/>'
           f'<path d="{d}" fill="none" stroke="{C["outline"]}" stroke-width="{INK}" stroke-linejoin="round"/>')
    return svg, grow(x, y, x + w, y + h, HALF)


ARM_W, ARM_H, ARM_TUCK = 27, 22, 6  # tuck: length hidden behind the body edge


def arm(side):
    """Pivot = shoulder; the nub reaches outward (side = -1 left, +1 right)."""
    x = -ARM_TUCK if side > 0 else ARM_TUCK - ARM_W
    y, w, h = -ARM_H / 2, ARM_W, ARM_H
    d = rr(x, y, w, h, 7)
    svg = (f'<path d="{d}" fill="{C["base"]}"/>'
           f'<rect x="{x+2}" y="{y+h-7}" width="{w-4}" height="5" fill="{C["shade"]}"/>'
           f'<path d="{d}" fill="none" stroke="{C["outline"]}" stroke-width="{INK}" stroke-linejoin="round"/>')
    return svg, grow(x, y, x + w, y + h, HALF)


def leg_tuck():
    """Stubby folded leg: same hip pivot, about 9 pt visible below the hip."""
    x, y, w, h = -LEG_W / 2, -LEG_TUCK, LEG_W, LEG_TUCK + 9
    d = rr(x, y, w, h, 5)
    svg = (f'<path d="{d}" fill="{C["leg"]}"/>'
           f'<rect x="{x+w-5}" y="{y+2}" width="4" height="{h-4}" fill="{C["legd"]}"/>'
           f'<path d="{d}" fill="none" stroke="{C["outline"]}" stroke-width="{INK}" stroke-linejoin="round"/>')
    return svg, grow(x, y, x + w, y + h, HALF)


BODY_W, BODY_H, BODY_R = 150, 100, 16
CEL_OFFSET = (-14, -17)  # base fill shifted up-left; what it uncovers is the cel shadow


def _body(d, cel, streak, cid):
    svg = (f'<defs><clipPath id="{cid}"><path d="{d}"/></clipPath></defs>'
           f'<path d="{d}" fill="{C["shade"]}"/>'
           f'<g clip-path="url(#{cid})">'
           f'<path d="{d}" transform="translate({cel[0]},{cel[1]})" fill="{C["base"]}"/>'
           f'<path d="{streak}" fill="{C["light"]}"/>'
           f'</g>'
           f'<path d="{d}" fill="none" stroke="{C["outline"]}" stroke-width="{INK}" stroke-linejoin="round"/>')
    # 0.5: room for body_sit's side bulge (peaks near x = 75.3) without growing the canvas
    return svg, grow(-BODY_W / 2 - 0.5, -BODY_H, BODY_W / 2 + 0.5, 0, HALF)


def body():
    """Pivot = bottom-centre. Flat fill, one hard cel shadow, one highlight streak, ink."""
    d = rr(-BODY_W / 2, -BODY_H, BODY_W, BODY_H, BODY_R)
    return _body(d, CEL_OFFSET, rr(-60, -93, 46, 7, 3.5), "bodyClip")


def body_sleep_curl():
    """Drowsy loaf: top 6 pt lower, softer top corners, deeper cel shadow, same footprint."""
    top, rt, rb = -94, 24, 12
    d = (f"M{-75+rt},{top} H{75-rt} Q75,{top} 75,{top+rt} V{-rb} Q75,0 {75-rb},0 "
         f"H{-75+rb} Q-75,0 -75,{-rb} V{top+rt} Q-75,{top} {-75+rt},{top} Z")
    return _body(d, (-10, -24), rr(-54, -88, 38, 6, 3), "curlClip")


def body_sit():
    """Squat: narrower top, sides bulging out toward a flat bottom, as if sat on a box."""
    d = ("M-56,-100 H56 Q72,-100 72,-84 C72,-50 76,-32 75,-14 Q75,0 61,0 "
         "H-61 Q-75,0 -75,-14 C-76,-32 -72,-50 -72,-84 Q-72,-100 -56,-100 Z")
    return _body(d, (-14, -20), rr(-57, -93, 44, 7, 3.5), "sitClip")


EYE_W, EYE_H = 17, 34


def eye():
    """Pivot = centre (blink = scaleY)."""
    x, y = -EYE_W / 2, -EYE_H / 2
    svg = (f'<defs>{CEL_EYE}</defs>'
           f'<path d="{rr(x, y, EYE_W, EYE_H, 4)}" fill="url(#celEye)"/>'
           f'<path d="{rr(x+2.2, y+3, 6.5, 10, 1.5)}" fill="#fff"/>'
           f'<rect x="{x+9}" y="{y+21}" width="3.2" height="3.2" fill="#fff"/>')
    return svg, (x, y, -x, -y)


def _ink_arc(d, w):
    return (f'<path d="{d}" fill="none" stroke="{C["eye"]}" stroke-width="{w}" '
            f'stroke-linecap="round" stroke-linejoin="round"/>')


def eye_happy():
    """^ arc, thick ink."""
    return _ink_arc("M-8,4 Q0,-16 8,4", 7), (-11.5, -9.5, 11.5, 7.5)


def eye_sleep():
    """Closed, smiling-down arc."""
    return _ink_arc("M-8,2 Q0,10 8,2", 5), (-10.5, -0.5, 10.5, 8.5)


def eye_focus():
    """Narrowed: flat top lid, looking slightly left-down, with a catchlight."""
    dx, dy = -2, 2
    x0, x1, y0, y1 = -8.5 + dx, 8.5 + dx, -5 + dy, 15 + dy
    d = (f"M{x0},{y0} H{x1} V{y1-4} Q{x1},{y1} {x1-4},{y1} H{x0+4} "
         f"Q{x0},{y1} {x0},{y1-4} Z")
    svg = (f'<defs>{CEL_EYE}</defs><path d="{d}" fill="url(#celEye)"/>'
           f'<rect x="{x0+3}" y="{y0+3}" width="5" height="6" fill="#fff"/>')
    return svg, (x0, y0, x1, y1)


def eye_half():
    """Half-lid: lower half of the open eye under a flat ink lid line."""
    x0, x1, y0, y1 = -EYE_W / 2, EYE_W / 2, -1, EYE_H / 2
    d = (f"M{x0},{y0} H{x1} V{y1-4} Q{x1},{y1} {x1-4},{y1} H{x0+4} "
         f"Q{x0},{y1} {x0},{y1-4} Z")
    svg = (f'<defs>{CEL_EYE}</defs><path d="{d}" fill="url(#celEye)"/>'
           f'<rect x="{x0+2.5}" y="{y0+3}" width="5" height="5" fill="#fff"/>'
           f'<path d="M{x0-1.5},{y0} H{x1+1.5}" stroke="{C["outline"]}" stroke-width="3" stroke-linecap="round"/>')
    return svg, (x0 - 3, y0 - 1.5, x1 + 3, y1)


def blush():
    """Pivot = centre. Cheek ellipse at the neutral 0.55 alpha plus three hatch strokes."""
    rx, ry = 10, 5
    o = [f'<ellipse cx="0" cy="0" rx="{rx}" ry="{ry}" fill="{C["cheek"]}" opacity="0.55"/>']
    for k in range(3):
        x0 = -6 + k * 5
        o.append(f'<path d="M{x0},3 L{x0+3},-3" stroke="{C["hatch"]}" stroke-width="1.4" stroke-linecap="round"/>')
    return "".join(o), (-rx, -ry, rx, ry)


def mouth():
    """Pivot = centre. Small open smile with a tongue line; hidden at rest by code."""
    svg = (f'<path d="M-6,-2.25 Q0,6.75 6,-2.25 Z" fill="{C["eye"]}"/>'
           f'<path d="M-3,2.25 Q0,4.75 3,2.25" stroke="{C["tongue"]}" stroke-width="2" fill="none" stroke-linecap="round"/>')
    return svg, (-6, -2.25, 6, 4.75)


def mouth_blep():
    """Tongue-out concentration (concept's focused pose), centred on the pivot."""
    svg = (f'<path d="M-7,-3 Q1,0 7,-4" stroke="{C["eye"]}" stroke-width="2.6" fill="none" stroke-linecap="round"/>'
           f'<path d="M1,-1.6 Q4,6 7.5,2 Q7,-1 6,-3 Z" fill="#E86A60" stroke="{C["eye"]}" '
           f'stroke-width="1.6" stroke-linejoin="round"/>')
    return svg, (-8.3, -5.3, 8.5, 6.5)


def mouth_o():
    """Open yawn."""
    svg = (f'<ellipse cx="0" cy="0" rx="4.5" ry="5.5" fill="{C["eye"]}"/>'
           f'<ellipse cx="0" cy="3" rx="2.6" ry="1.6" fill="{C["tongue"]}"/>')
    return svg, (-4.5, -5.5, 4.5, 5.5)


def mouth_wobble():
    """Wavy worry line."""
    d = "M-7,0 Q-5.25,-2.5 -3.5,0 T0,0 T3.5,0 T7,0"
    return _ink_arc(d, 2.4), (-8.2, -2.5, 8.2, 2.5)


# ---------------------------------------------------------------- props
# Props anchored [0.5, 0]: drawn so their visible bottom edge sits at y = 0 (the pivot).
TAN, TAN_D, FILL = "#D8B98A", "#B8956A", "#F08A4B"


# Pocket window in the bag's front panel (y down, bag pivot = visible bottom edge).
BAG_WIN = (-6, -13, 12, 9, 3)  # x, y, w, h, r: spans 4..13 pt above the bag's bottom


def bag():
    """Little backpack, about 22x28 visible: tan body with a see-through pocket window,
    flap, strap and buckle. bag_fill sits behind it (z -1) and shows through the window."""
    w, h = 22, 28
    x, y, iw, ih = -w / 2 + HALF, -h + HALF, w - INK, h - INK  # stroke centred inside the visible box
    d = rr(x, y, iw, ih, 5)
    win = rr(*BAG_WIN)
    flap = f"M{x},{y+10} V{y+4} Q{x},{y} {x+4},{y} H{x+iw-4} Q{x+iw},{y} {x+iw},{y+4} V{y+10} Q0,{y+14} {x},{y+10} Z"
    svg = (f'<defs><clipPath id="bagClip"><path d="{d} {win}" clip-rule="evenodd"/></clipPath></defs>'
           f'<path d="{d} {win}" fill="{TAN}" fill-rule="evenodd"/>'
           f'<g clip-path="url(#bagClip)"><rect x="{x+iw-4}" y="{y}" width="4" height="{ih}" fill="{TAN_D}"/>'
           f'<path d="{flap}" fill="{TAN_D}" stroke="{C["outline"]}" stroke-width="2"/>'
           f'<rect x="-1.6" y="{y+10}" width="3.2" height="{BAG_WIN[1]-y-10}" fill="{TAN_D}"/></g>'
           f'<path d="{win}" fill="none" stroke="{C["outline"]}" stroke-width="2"/>'
           f'<rect x="-2.5" y="{y+8.5}" width="5" height="5" rx="1" fill="{C["light"]}" stroke="{C["outline"]}" stroke-width="1.6"/>'
           f'<path d="{d}" fill="none" stroke="{C["outline"]}" stroke-width="{INK}" stroke-linejoin="round"/>')
    return svg, (-w / 2, -h, w / 2, 0)


def bag_fill():
    """Flat fill, no outline, drawn behind the bag. Its bottom is the window's bottom and at
    yScale 1 it reaches just under the window's top ink; wider than the window so the
    sides stay hidden behind the panel."""
    wx, wy, ww, wh, _r = BAG_WIN
    fh = wh + 0.5
    return f'<rect x="{wx-1}" y="{-fh}" width="{ww+2}" height="{fh}" fill="{FILL}"/>', (wx - 1, -fh, wx + ww + 1, 0)


BAG_FILL_Y = -(BAG_WIN[1] + BAG_WIN[3])  # window bottom, points above the bag's pivot (y up)


def jar_glass():
    """22x34 visible glass jar: ink outline, soft sheen, transparent inside."""
    w, h = 22, 34
    x, y, iw, ih = -w / 2 + HALF, -h + HALF, w - INK, h - INK
    svg = ('<defs><filter id="soft" x="-50%" y="-50%" width="200%" height="200%">'
           '<feGaussianBlur stdDeviation="0.8"/></filter></defs>'
           f'<path d="{rr(x+2, y+3, 3.2, ih-9, 1.6)}" fill="#fff" opacity="0.55" filter="url(#soft)"/>'
           f'<path d="{rr(x+iw-4.5, y+4, 2, 5, 1)}" fill="#fff" opacity="0.45" filter="url(#soft)"/>'
           f'<path d="{rr(x, y, iw, ih, 5)}" fill="none" stroke="{C["outline"]}" stroke-width="{INK}"/>')
    return svg, (-w / 2, -h, w / 2, 0)


def jar_fill():
    """Warm spark fill 18x30, vertical gradient, no outline; code scales it in Y."""
    svg = ('<defs><linearGradient id="jf" x1="0" y1="1" x2="0" y2="0">'
           '<stop offset="0" stop-color="#F08A4B"/><stop offset="1" stop-color="#FFD978"/></linearGradient></defs>'
           f'<path d="{rr(-9, -30, 18, 30, 3)}" fill="url(#jf)"/>')
    return svg, (-9, -30, 9, 0)


def jar_lid():
    """26x8 visible lid."""
    w, h, ink = 26, 8, 3  # full 4.6 ink would leave no visible lid colour in 8 pt
    d = rr(-w / 2 + ink / 2, -h + ink / 2, w - ink, h - ink, 1.5)
    svg = f'<path d="{d}" fill="{C["shade"]}" stroke="{C["outline"]}" stroke-width="{ink}" stroke-linejoin="round"/>'
    return svg, (-w / 2, -h, w / 2, 0)


def moon_dark():
    """40 pt night disc with ink outline and two crater dimples."""
    r = 20 - HALF
    svg = (f'<circle r="{r}" fill="#3B3F66" stroke="{C["outline"]}" stroke-width="{INK}"/>'
           '<circle cx="-6" cy="-5" r="4" fill="#2E3157"/><circle cx="7" cy="6" r="2.6" fill="#2E3157"/>'
           '<circle cx="2" cy="-9" r="1.6" fill="#2E3157"/>')
    return svg, (-20, -20, 20, 20)


def moon_lit():
    """36 pt bright disc, soft craters, no outline (masked into phases by code)."""
    svg = ('<defs><filter id="sc" x="-50%" y="-50%" width="200%" height="200%">'
           '<feGaussianBlur stdDeviation="0.7"/></filter></defs>'
           '<circle r="18" fill="#FFE9A8"/>'
           '<g fill="#EDD08A" filter="url(#sc)"><circle cx="-6" cy="-5" r="4"/>'
           '<circle cx="7" cy="6" r="2.6"/><circle cx="2" cy="-9" r="1.6"/></g>')
    return svg, (-18, -18, 18, 18)


SPARK_R = 10
SPARK_RAYS = [1.0, 0.78, 0.95, 0.82, 1.0, 0.76, 0.92, 0.85]


def spark(r=SPARK_R, sw=HALF):
    """Pivot = centre. Claude asterisk: 8 round-capped rays, ink rim of sw."""
    lines = []
    for i, L in enumerate(SPARK_RAYS):
        a = math.radians(i * 45)
        lines.append(f'<line x1="0" y1="0" x2="{math.cos(a)*r*L:.2f}" y2="{math.sin(a)*r*L:.2f}"/>')
    rays = "".join(lines)
    core = r * 0.34
    svg = (f'<g stroke="{C["outline"]}" stroke-width="{core+sw*2:.2f}" stroke-linecap="round">{rays}</g>'
           f'<g stroke="{C["spark"]}" stroke-width="{core:.2f}" stroke-linecap="round">{rays}</g>')
    e = r + core / 2 + sw
    return svg, (-e, -e, e, e)
