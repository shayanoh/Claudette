"""Per-model outfits and the per-project scarf, style B. Same contract as parts.py: points,
y DOWN, pivot at (0,0), returns (svg, box). Body pieces use the bodyPivot origin (bottom-centre
of the body) as their pivot, so their manifest position is (0, 0). No text."""
from parts import BODY_H, BODY_R, BODY_W, INK as BODY_INK, rr
from props import GREY, GREY_D, INK_C, _id, gloss

INK = 3.5  # outfit ink: between prop (3) and body (4.6)
H = INK / 2
BODY_D = rr(-BODY_W / 2, -BODY_H, BODY_W, BODY_H, BODY_R)

PLUM, PLUM_D, IVORY, IVORY_D = "#7A4FA3", "#5B3780", "#F3E3C3", "#D6C29C"
TEAL, TEAL_D = "#2F7F7A", "#1F5E5A"
PINK, PINK_D, CREAM = "#F29BC0", "#D06E98", "#FFF8F0"


def cel(d, base, shade, off=(-3, -3), inner="", ink=INK):
    cid = _id("o")
    return (f'<defs><clipPath id="{cid}"><path d="{d}"/></clipPath></defs>'
            f'<path d="{d}" fill="{shade}"/>'
            f'<g clip-path="url(#{cid})"><path d="{d}" transform="translate({off[0]},{off[1]})" fill="{base}"/>{inner}</g>'
            f'<path d="{d}" fill="none" stroke="{INK_C}" stroke-width="{ink}" stroke-linejoin="round"/>')


def on_body(d, base, shade, off, inner=""):
    """A panel painted onto the body: fill clipped to the body, its own ink only on the
    edges inside the body, and the body's outline redrawn over just this panel's area so
    the silhouette stays crisp. Works for any body texture with the same outer edge."""
    cb, cp = _id("b"), _id("p")
    return (f'<defs><clipPath id="{cb}"><path d="{BODY_D}"/></clipPath>'
            f'<clipPath id="{cp}"><path d="{d}"/></clipPath></defs>'
            f'<g clip-path="url(#{cb})">{cel(d, base, shade, off, inner)}</g>'
            f'<g clip-path="url(#{cp})"><path d="{BODY_D}" fill="none" stroke="{INK_C}" '
            f'stroke-width="{BODY_INK}" stroke-linejoin="round"/></g>')


# ---------------------------------------------------------------- heads (pivot = base centre)
HEAD_TILT = {"opus": -8, "sonnet": 10, "haiku": 8}


def _tilt(svg, deg):
    return f'<g transform="rotate({deg})">{svg}</g>'


def outfit_opus_head():
    """Small ivory crown, plum gems, worn at a jaunty tilt."""
    d = "M-19,0 V-13 L-11,-7 L-5,-19 L0,-9 L5,-19 L11,-7 L19,-13 V0 Z"
    inner = (f'<rect x="-20" y="-5" width="40" height="5" fill="{IVORY_D}"/>'
             + gloss(-15, -11, 2.2, 6, 0.8))
    gems = "".join(f'<circle cx="{x}" cy="{y}" r="2.6" fill="{PLUM}" stroke="{INK_C}" stroke-width="1.6"/>'
                   for x, y in ((-5, -19.5), (5, -19.5)))
    gems += f'<path d="M0,-6.2 L2.4,-3 L0,0.2 L-2.4,-3 Z" fill="{PLUM}" stroke="{INK_C}" stroke-width="1.4" stroke-linejoin="round"/>'
    return _tilt(cel(d, IVORY, IVORY_D, inner=inner) + gems, HEAD_TILT["opus"]), (-24, -26, 24, 4)


def outfit_sonnet_head():
    """Deep-teal beret with a little stem, tipped to one side."""
    d = "M-24,-2 Q-27,-15 -2,-17 Q24,-18 25,-6 Q25,-1 16,-1 H-17 Q-23,-0.5 -24,-2 Z"
    stem = cel(rr(-1.5, -22, 4, 6, 2), TEAL, TEAL_D, off=(-1, 0), ink=2.4)
    band = f'<path d="M-21,-3.5 Q0,-6 22,-3.5" stroke="{TEAL_D}" stroke-width="2.2" fill="none"/>'
    svg = stem + cel(d, TEAL, TEAL_D, inner=band + gloss(-17, -14, 12, 2.4, 0.45))
    return _tilt(svg, HEAD_TILT["sonnet"]), (-29, -27, 29, 6)


def outfit_haiku_head():
    """Cream-and-pink propeller beanie: light, quick, a bit silly."""
    dome = "M-15,0 A15,13 0 0 1 15,0 Z"
    gores = (f'<path d="M-5,0 Q-6,-8 0,-13 Q-2,-6 -1,0 Z" fill="{PINK}"/>'
             f'<path d="M7,0 Q8,-8 3,-12.6 Q6,-6 10.5,0 Z" fill="{PINK}"/>' + gloss(-11, -8, 2, 5, 0.8))
    brim = cel(rr(-16.5, -3.5, 33, 4.5, 2.2), PINK, PINK_D, off=(-1, -1), ink=2.6)
    stem = f'<rect x="-1.1" y="-19" width="2.2" height="7" fill="{INK_C}"/>'
    blades = (f'<g stroke="{INK_C}" stroke-width="1.8"><ellipse cx="-6.5" cy="-19.5" rx="6.5" ry="2.4" fill="{PINK}"/>'
              f'<ellipse cx="6.5" cy="-19.5" rx="6.5" ry="2.4" fill="{CREAM}"/></g>'
              f'<circle cx="0" cy="-19.5" r="2" fill="{INK_C}"/>')
    svg = stem + cel(dome, CREAM, "#E3D5C6", inner=gores) + brim + blades
    return _tilt(svg, HEAD_TILT["haiku"]), (-20, -26, 20, 5)


# ---------------------------------------------------------------- body pieces (pivot = bodyPivot origin)
def outfit_opus_body():
    """Plum cape worn BEHIND the body and the arms (z -0.5): high collar points peek above the top corners and the
    hem flares wide at the lower sides, with an ivory trim."""
    d = ("M-58,-98 L-84,-108 L-80,-42 L-104,8 Q-78,13 -52,8 T0,8 T52,8 T104,8 "
         "L80,-42 L84,-108 L58,-98 Z")
    trim = "M-104,8 Q-78,13 -52,8 T0,8 T52,8 T104,8"
    inner = (f'<path d="{trim}" stroke="{IVORY}" stroke-width="8" fill="none"/>'
             f'<path d="{trim}" stroke="{INK_C}" stroke-width="1.4" fill="none" transform="translate(0,-4)"/>'
             f'<path d="M-84,-108 L-72,-101 M84,-108 L72,-101" stroke="{IVORY}" stroke-width="3"/>')
    return cel(d, PLUM, PLUM_D, off=(-6, -3), inner=inner), (-106, -111, 106, 14)


def outfit_sonnet_body():
    """Teal open vest: two side panels with ivory buttons, the face left clear."""
    out = ""
    for s in (-1, 1):
        d = (f"M{s*44},2 L{s*64},-26 V-72 L{s*80},-80 V2 Z")
        btn = "".join(f'<circle cx="{s*69.5}" cy="{y}" r="2.1" fill="{IVORY}" stroke="{INK_C}" stroke-width="1.2"/>'
                      for y in (-36, -52))
        out += on_body(d, TEAL, TEAL_D, (-3, -3), gloss(s * 70 - 2, -68, 2, 14, 0.4)) + btn
    return out, (-78, -82, 78, 3)


def outfit_haiku_body():
    """Pink ribbon belt low on the body; the bow's tails stream out to the right."""
    band = "M-80,-11 H80 V-4 H-80 Z"
    belt = on_body(band, PINK, PINK_D, (0, -1.6))
    tails = (cel("M58,-9 Q74,-12 92,-4 L86,-1 L91,4 Q72,1 58,-6 Z", PINK, PINK_D, off=(-1, -2), ink=2.6)
             + cel("M58,-7 Q72,-2 84,10 L78,10 L80,15 Q68,6 57,-5 Z", PINK, PINK_D, off=(-1, -2), ink=2.6))
    bow = (cel("M56,-8 Q46,-17 44,-8 Q46,0 56,-8 Z", PINK, PINK_D, off=(-1, -1.5), ink=2.6)
           + cel("M56,-8 Q66,-17 68,-8 Q66,0 56,-8 Z", PINK, PINK_D, off=(-1, -1.5), ink=2.6)
           + f'<circle cx="56" cy="-8" r="3" fill="{PINK_D}" stroke="{INK_C}" stroke-width="1.8"/>')
    return belt + tails + bow, (-78, -20, 95, 18)


# ---------------------------------------------------------------- scarf (tintable)
SCARF_Y = (14, 26)  # band bottom/top in bodyPivot space (y up): under the mouth/blush
TAIL_AT = (60, 14)
SCARF_PIVOT = (0, (SCARF_Y[0] + SCARF_Y[1]) / 2)  # scarf's manifest position  # where scarf_tail hangs from (bodyPivot space, y up)


def scarf():
    """Neutral light scarf wrapped round the lower body, knot on her right side."""
    b, t = -SCARF_Y[0], -SCARF_Y[1]
    d = (f"M-80,{t-1} Q0,{t+3} 80,{t-1} Q83,{(t+b)/2} 80,{b+1} Q0,{b+4} -80,{b+1} "
         f"Q-83,{(t+b)/2} -80,{t-1} Z")
    stripes = "".join(f'<path d="M{x},{t-4} V{b+6}" stroke="#C8C8C8" stroke-width="3"/>' for x in (-60, -54, 30, 36))
    knot = cel(rr(TAIL_AT[0] - 7, t - 2, 14, b - t + 4, 5), GREY, GREY_D, off=(-1.5, -2))
    svg = cel(d, GREY, GREY_D, off=(0, -3), inner=stripes + gloss(-60, t + 1.5, 40, 2.2, 0.7)) + knot
    # Pivot on the band's centre (SCARF_PIVOT) so the anchor lies inside the canvas.
    cy = SCARF_PIVOT[1]
    return f'<g transform="translate(0,{cy})">{svg}</g>', (-84, t - 4 + cy, 84, b + 6 + cy)


def scarf_tail():
    """Hanging tail with a fringe; pivot = top attachment (top-centre)."""
    d = "M-6,-1 H6 Q7,14 9,26 H-3 Q-5,14 -6,-1 Z"
    stripes = f'<path d="M-6,14 H9" stroke="#C8C8C8" stroke-width="3"/>'
    fringe = "".join(f'<rect x="{x}" y="25" width="2" height="5" rx="1" fill="{GREY_D}" stroke="{INK_C}" stroke-width="1"/>'
                     for x in (-2.5, 1.5, 5.5))
    return fringe + cel(d, GREY, GREY_D, off=(-1.5, 0), inner=stripes), (-8, -3, 11, 31)
