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


BODY_W, BODY_H, BODY_R = 150, 100, 16
CEL_OFFSET = (-14, -17)  # base fill shifted up-left; what it uncovers is the cel shadow


def body():
    """Pivot = bottom-centre. Flat fill, one hard cel shadow, one highlight streak, ink."""
    x, y = -BODY_W / 2, -BODY_H
    d = rr(x, y, BODY_W, BODY_H, BODY_R)
    svg = (f'<defs><clipPath id="bodyClip"><path d="{d}"/></clipPath></defs>'
           f'<path d="{d}" fill="{C["shade"]}"/>'
           f'<g clip-path="url(#bodyClip)">'
           f'<path d="{d}" transform="translate({CEL_OFFSET[0]},{CEL_OFFSET[1]})" fill="{C["base"]}"/>'
           f'<path d="{rr(-60, -93, 46, 7, 3.5)}" fill="{C["light"]}"/>'
           f'</g>'
           f'<path d="{d}" fill="none" stroke="{C["outline"]}" stroke-width="{INK}" stroke-linejoin="round"/>')
    return svg, grow(x, y, -x, 0, HALF)


EYE_W, EYE_H = 17, 34


def eye():
    """Pivot = centre (blink = scaleY)."""
    x, y = -EYE_W / 2, -EYE_H / 2
    svg = (f'<defs>{CEL_EYE}</defs>'
           f'<path d="{rr(x, y, EYE_W, EYE_H, 4)}" fill="url(#celEye)"/>'
           f'<path d="{rr(x+2.2, y+3, 6.5, 10, 1.5)}" fill="#fff"/>'
           f'<rect x="{x+9}" y="{y+21}" width="3.2" height="3.2" fill="#fff"/>')
    return svg, (x, y, -x, -y)


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
