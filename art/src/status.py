"""Claudette status art, style B. Same contract as parts.py / props.py (points, y down,
pivot at (0,0), each function returns (svg, box)). Glyphs are shapes, never text."""
import math

from parts import C, rr
from props import INK, INK_C, gloss, _id

H = INK / 2
PILL_W, PILL_H = 88, 28
BADGE_X, BADGE_R = -30, 10  # icon badge centre x and radius (about 22 pt with its ink)
# Centre of the empty text area right of the badge (y up, from the pill centre).
PILL_LABEL = [round((BADGE_X + BADGE_R + 2 + PILL_W / 2 - 4) / 2, 2), 0]


def blob(shapes, base, shade, off=(-3, -3), inner=""):
    """Union of shapes with one shared outline: a 2x ink stroke under the fills leaves exactly
    INK visible outside, and seams between shapes vanish. Then the usual L cel shadow."""
    cid = _id("u")
    paths = "".join(f'<path d="{d}"/>' for d in shapes)
    return (f'<defs><clipPath id="{cid}">{paths}</clipPath></defs>'
            f'<g fill="{INK_C}" stroke="{INK_C}" stroke-width="{INK*2}" stroke-linejoin="round">{paths}</g>'
            f'<g fill="{shade}">{paths}</g>'
            f'<g clip-path="url(#{cid})"><g fill="{base}" transform="translate({off[0]},{off[1]})">{paths}</g>{inner}</g>')


def circle_d(cx, cy, r):
    # Clockwise like rr(): rsvg unions clipPath children by winding, so mixed directions cancel.
    return f"M{cx+r},{cy} A{r},{r} 0 1 1 {cx-r},{cy} A{r},{r} 0 1 1 {cx+r},{cy} Z"


# ---------------------------------------------------------------- bubbles
BUB_C, BUB_R = -23.5, 15.5  # bubble centre y and radius; the tail tip is the pivot


def _bubble(base, shade, glyph):
    shapes = [circle_d(0, BUB_C, BUB_R), f"M6,{BUB_C+BUB_R-5} L0,-3 L-6,{BUB_C+BUB_R-5} Z"]
    svg = blob(shapes, base, shade, inner=gloss(-10, BUB_C - 11, 9, 3, 0.75)) + glyph
    r = BUB_R + INK
    return svg, (-r, BUB_C - r, r, 0)


def status_bang():
    g = (f'<path d="{rr(-3, BUB_C-10.5, 6, 12, 3)}" fill="{INK_C}"/>'
         f'<circle cx="0" cy="{BUB_C+6.5}" r="3.1" fill="{INK_C}"/>')
    return _bubble("#FFC94D", "#E0A030", g)


def status_question():
    c = BUB_C
    g = (f'<path d="M-5,{c-5} Q-5,{c-11} 0,{c-11} Q5,{c-11} 5,{c-6} Q5,{c-2.5} 0,{c} V{c+1.5}" '
         f'stroke="{INK_C}" stroke-width="5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'
         f'<circle cx="0" cy="{c+7}" r="3.1" fill="{INK_C}"/>')
    return _bubble("#7FC8F8", "#4FA3DA", g)


# ---------------------------------------------------------------- error pills
def _pill(icon, badge="#FFF1EC", base="#E5484D", shade="#B23238"):
    w, h = PILL_W - INK, PILL_H - INK
    d = rr(-w / 2, -h / 2, w, h, h / 2)
    cid = _id("pl")
    body = (f'<defs><clipPath id="{cid}"><path d="{d}"/></clipPath></defs>'
            f'<path d="{d}" fill="{shade}"/>'
            f'<g clip-path="url(#{cid})"><path d="{d}" transform="translate(-3,-3.5)" fill="{base}"/>'
            + gloss(-26, -9.5, 34, 2.6, 0.55) + "</g>"
            f'<path d="{d}" fill="none" stroke="{INK_C}" stroke-width="{INK}"/>')
    disc = (f'<circle cx="{BADGE_X}" cy="0" r="{BADGE_R - 1}" fill="{badge}" stroke="{INK_C}" stroke-width="2"/>')
    return body + disc + icon, (-PILL_W / 2, -PILL_H / 2, PILL_W / 2, PILL_H / 2)


def _ln(d, w=2, col=INK_C, fill="none"):
    return (f'<path d="{d}" stroke="{col}" stroke-width="{w}" fill="{fill}" '
            f'stroke-linecap="round" stroke-linejoin="round"/>')


def status_err_api():
    """Cracked spark."""
    x = BADGE_X
    rays = "".join(f'<line x1="{x}" y1="0" x2="{x+math.cos(math.radians(a))*5.8:.2f}" '
                   f'y2="{math.sin(math.radians(a))*5.8:.2f}"/>' for a in range(0, 360, 45))
    spark = (f'<g stroke="{INK_C}" stroke-width="4.6" stroke-linecap="round">{rays}</g>'
             f'<g stroke="{C["spark"]}" stroke-width="2.2" stroke-linecap="round">{rays}</g>')
    crack = _ln(f"M{x-4},-7 L{x-0.5},-1.5 L{x-2.5},1 L{x+2.5},7", 1.5, "#FFF1EC")
    return _pill(spark + crack)


def status_err_auth():
    """Padlock."""
    x = BADGE_X
    icon = (_ln(f"M{x-3},-1.5 V-4 A3,3 0 0 1 {x+3},-4 V-1.5", 2.2)
            + f'<path d="{rr(x-5, -1.5, 10, 8, 1.5)}" fill="#FFC94D" stroke="{INK_C}" stroke-width="1.6"/>'
            + f'<circle cx="{x}" cy="1.8" r="1.2" fill="{INK_C}"/>'
            + f'<rect x="{x-0.5}" y="2" width="1" height="2.4" fill="{INK_C}"/>')
    return _pill(icon, base="#E04452")


def status_err_billing():
    """Coin with a slash."""
    x = BADGE_X
    icon = (f'<circle cx="{x}" cy="0" r="6" fill="#FFC94D" stroke="{INK_C}" stroke-width="1.6"/>'
            f'<circle cx="{x}" cy="0" r="3.4" fill="none" stroke="#E0A030" stroke-width="1.2"/>'
            + _ln(f"M{x-6.5},6.5 L{x+6.5},-6.5", 3.4, "#FFF1EC")
            + _ln(f"M{x-6.5},6.5 L{x+6.5},-6.5", 1.8))
    return _pill(icon, base="#E5524A")


def status_err_ratelimit():
    """Hourglass."""
    x = BADGE_X
    glass = f"M{x-4},-5.5 H{x+4} L{x},0 L{x+4},5.5 H{x-4} L{x},0 Z"
    icon = (f'<path d="{glass}" fill="#FFE9A8" stroke="{INK_C}" stroke-width="1.5" stroke-linejoin="round"/>'
            f'<path d="M{x-2.6},5 H{x+2.6} L{x},2 Z" fill="#E0A030"/>'
            f'<path d="M{x-1.6},-4 H{x+1.6} L{x},-2 Z" fill="#E0A030"/>'
            + _ln(f"M{x-5.5},-6.5 H{x+5.5} M{x-5.5},6.5 H{x+5.5}", 2.2))
    return _pill(icon, base="#E3485A")


def status_err_offline():
    """Unplugged cable with a small no-signal cloud, on a grey badge."""
    x = BADGE_X
    cloud = (f"M{x-1},-2 H{x+5.5} A2,2 0 0 0 {x+5.5},-6 A2.6,2.6 0 0 0 {x+1},-7 "
             f"A2.2,2.2 0 0 0 {x-1},-2 Z")
    icon = (f'<path d="{cloud}" fill="#fff" stroke="{INK_C}" stroke-width="1.2" stroke-linejoin="round"/>'
            + _ln(f"M{x-0.5},-7.5 L{x+6.5},-1.5", 1.3)
            + _ln(f"M{x-8},6 Q{x-6.5},2.5 {x-4.5},2.5", 1.8)
            + f'<path d="{rr(x-4.5, 0.5, 4.5, 4, 1)}" fill="#C9C9D1" stroke="{INK_C}" stroke-width="1.2"/>'
            + _ln(f"M{x},1.6 H{x+1.6} M{x},3.4 H{x+1.6}", 1)
            + _ln(f"M{x+3.5},1 V5 M{x+5.5},1 V5", 1.4, "#8A8FA3"))
    return _pill(icon, badge="#D8D8DE", base="#D2474E", shade="#A0363C")


def status_err_unknown():
    """Warning triangle with an exclamation."""
    x = BADGE_X
    icon = (f'<path d="M{x},-6.5 L{x+6.8},5.5 H{x-6.8} Z" fill="#FFC94D" stroke="{INK_C}" '
            f'stroke-width="1.6" stroke-linejoin="round"/>'
            f'<path d="{rr(x-0.9, -3, 1.8, 4.6, 0.9)}" fill="{INK_C}"/>'
            f'<circle cx="{x}" cy="3.3" r="1" fill="{INK_C}"/>')
    return _pill(icon)


# ---------------------------------------------------------------- relief
RELIEF_LABEL = [0, 1]  # interior centre (y down -1), as y up from the anchor


def status_relief():
    """Soft sigh puff: white cloud, ink outline, cool cel shadow; text goes inside."""
    # Lobes end level with the base so the cel band runs cleanly along the bottom.
    shapes = [circle_d(-11, 1, 8), circle_d(0, -2, 9), circle_d(11, 1, 8), rr(-17, 0, 34, 9, 4.5)]
    svg = blob(shapes, "#FFFFFF", "#D9DCE8", off=(-1, -2.5), inner=gloss(-9, -8, 9, 2.4, 0.9).replace("#fff", "#EEF0F7"))
    return svg, (-19 - INK, -11 - INK, 19 + INK, 9 + INK)
