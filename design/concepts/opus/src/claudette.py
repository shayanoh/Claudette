"""Parametric Claudette generator -> SVG concept sheets.

Local character space: ground at y=0, feet on ground, y down.
Body local: x -75..75, y -100..0 (bottom of body = 0), placed on legs.
"""
import math, random, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "."

# ---------------------------------------------------------------- helpers
def rr(x, y, w, h, r):
    r = min(r, w / 2, h / 2)
    return (f"M{x+r:.2f},{y:.2f} H{x+w-r:.2f} Q{x+w:.2f},{y:.2f} {x+w:.2f},{y+r:.2f} "
            f"V{y+h-r:.2f} Q{x+w:.2f},{y+h:.2f} {x+w-r:.2f},{y+h:.2f} H{x+r:.2f} "
            f"Q{x:.2f},{y+h:.2f} {x:.2f},{y+h-r:.2f} V{y+r:.2f} Q{x:.2f},{y:.2f} {x+r:.2f},{y:.2f} Z")


def wobbly(x, y, w, h, r, seed, amp=1.2, n=56):
    """Hand-cut paper rounded rect: perimeter points with jitter."""
    rnd = random.Random(seed)
    r = min(r, w / 2, h / 2)
    pts = []
    # sample perimeter of rounded rect param t in [0,1)
    segs = []
    cx = [x + w - r, x + w - r, x + r, x + r]
    cy = [y + r, y + h - r, y + h - r, y + r]
    for i in range(n):
        a = 2 * math.pi * i / n
        # superellipse-ish mapping for rounded rect
        ca, sa = math.cos(a), math.sin(a)
        px = x + w / 2 + (w / 2) * (abs(ca) ** 0.25) * (1 if ca >= 0 else -1)
        py = y + h / 2 + (h / 2) * (abs(sa) ** 0.25) * (1 if sa >= 0 else -1)
        px += rnd.uniform(-amp, amp)
        py += rnd.uniform(-amp, amp)
        pts.append((px, py))
    d = f"M{pts[0][0]:.2f},{pts[0][1]:.2f} " + " ".join(f"L{p[0]:.2f},{p[1]:.2f}" for p in pts[1:]) + " Z"
    return d


def star4(x, y, r, fill, extra=""):
    k = r * 0.28
    return (f'<path d="M{x},{y-r} Q{x+k},{y-k} {x+r},{y} Q{x+k},{y+k} {x},{y+r} '
            f'Q{x-k},{y+k} {x-r},{y} Q{x-k},{y-k} {x},{y-r} Z" fill="{fill}" {extra}/>')


def spark(x, y, r, fill, stroke=None, sw=0, rot=0, opacity=1):
    """Claude-style asterisk: 8 tapered rounded rays of uneven length."""
    lens = [1.0, 0.78, 0.95, 0.82, 1.0, 0.76, 0.92, 0.85]
    parts = []
    for i, L in enumerate(lens):
        a = math.radians(rot + i * 45)
        ex, ey = x + math.cos(a) * r * L, y + math.sin(a) * r * L
        parts.append(f'<line x1="{x}" y1="{y}" x2="{ex:.2f}" y2="{ey:.2f}" />')
    g = ""
    if stroke:
        g += (f'<g stroke="{stroke}" stroke-width="{r*0.34+sw*2:.2f}" stroke-linecap="round" opacity="{opacity}">'
              + "".join(parts) + "</g>")
    g += (f'<g stroke="{fill}" stroke-width="{r*0.34:.2f}" stroke-linecap="round" opacity="{opacity}">'
          + "".join(parts) + "</g>")
    return g


# ---------------------------------------------------------------- styles
STYLES = {
    "vinyl": dict(
        base="#DE7A55", shade="#B9583A", light="#F7A982", leg="#C4623F", legd="#A34A2D",
        outline="#7A321E", ow=2.4, eye="#24120D", cheek="#F06C62", r=26, rim="#FFD8BF",
        spark="#F4A27F", sparkstroke="#FFF4EA"),
    "cel": dict(
        base="#E07C56", shade="#B0503A", light="#F9BC98", leg="#C9643F", legd="#9C4430",
        outline="#3A1A12", ow=4.6, eye="#26100B", cheek="#F0827A", r=16, rim=None,
        spark="#FFB48F", sparkstroke="#3A1A12"),
    "paper": dict(
        base="#D97757", shade="#B85E40", light="#E99573", leg="#B95C3D", legd="#9A4A30",
        outline="#FFFFFF", ow=0, eye="#2B1D18", cheek="#F2A08A", r=12, rim=None,
        spark="#F7D6A8", sparkstroke="#FFFFFF"),
}

POSES = {
    #          sx    sy   lift legL armL armR  eyes      lean
    "neutral": (1.00, 1.00, 0, 23, 0, 0, "open", 0),
    "happy":   (0.95, 1.07, -16, 21, 42, -42, "happy", 0),
    "focused": (1.00, 1.00, 0, 23, 8, -38, "focus", -3),
    "sleepy":  (1.07, 0.90, 0, 7, -14, 14, "closed", 0),
    "waiting": (1.00, 1.00, 0, 23, 0, -70, "open", 0),
}

_uid = [0]
def uid(p):
    _uid[0] += 1
    return f"{p}{_uid[0]}"


def defs_common():
    return """
<filter id="blur1" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="1"/></filter>
<filter id="blur2" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="2"/></filter>
<filter id="blur4" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="4"/></filter>
<filter id="blur8" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="8"/></filter>
<radialGradient id="vinylBody" cx="0.32" cy="0.22" r="0.95">
  <stop offset="0" stop-color="#F8AE88"/><stop offset="0.45" stop-color="#E07D58"/><stop offset="1" stop-color="#B4532F"/></radialGradient>
<linearGradient id="vinylLeg" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#A9492C"/><stop offset="0.5" stop-color="#C9673F"/><stop offset="1" stop-color="#B85A38"/></linearGradient>
<linearGradient id="vinylEye" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#140906"/><stop offset="0.6" stop-color="#2E1710"/><stop offset="1" stop-color="#5A2A1C"/></linearGradient>
<linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.85"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient>
<linearGradient id="celEye" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#1C0B07"/><stop offset="0.55" stop-color="#2A120C"/><stop offset="0.56" stop-color="#5B2416"/><stop offset="1" stop-color="#B4482C"/></linearGradient>
<filter id="grain" x="0" y="0" width="100%" height="100%">
  <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="3" result="n"/>
  <feColorMatrix type="saturate" values="0"/>
  <feComponentTransfer><feFuncA type="table" tableValues="0 0.18"/></feComponentTransfer>
  <feComposite in2="SourceGraphic" operator="in"/>
</filter>
"""


# ---------------------------------------------------------------- eyes
def eyes(style, kind, S, dx=0):
    out = []
    for side in (-1, 1):
        cx = side * 32 + dx
        if kind == "open":
            x, y, w, h = cx - 7.5, -73, 15, 31
            if style == "vinyl":
                out.append(f'<path d="{rr(x,y,w,h,5.5)}" fill="url(#vinylEye)"/>')
                out.append(f'<path d="{rr(x+2.2,y+3.2,6,9,3)}" fill="#fff" opacity="0.95"/>')
                out.append(f'<circle cx="{x+9.6}" cy="{y+25}" r="1.8" fill="#fff" opacity="0.75"/>')
            elif style == "cel":
                x, y, w, h = cx - 8.5, -75, 17, 34
                out.append(f'<path d="{rr(x,y,w,h,4)}" fill="url(#celEye)"/>')
                out.append(f'<path d="{rr(x+2.2,y+3,6.5,10,1.5)}" fill="#fff"/>')
                out.append(f'<rect x="{x+9}" y="{y+21}" width="3.2" height="3.2" fill="#fff"/>')
            else:
                out.append(f'<path d="{wobbly(x,y,w,h,3,int(cx*7)+11,0.5,36)}" fill="{S["eye"]}"/>')
                out.append(f'<rect x="{x+2.5}" y="{y+3}" width="4.5" height="6" fill="#FFF8EE" transform="rotate(-6 {x+4} {y+6})"/>')
        elif kind == "focus":
            x, y, w, h = cx - 7.5, -63, 15, 19
            # flat, slightly inward-slanted top lid = determined
            tilt = 0
            d = (f"M{x},{y+tilt if side<0 else y-tilt} L{x+w},{y-tilt if side<0 else y+tilt} "
                 f"V{y+h-5} Q{x+w},{y+h} {x+w-5},{y+h} H{x+5} Q{x},{y+h} {x},{y+h-5} Z")
            if style == "cel":
                d = (f"M{x-1},{y+tilt if side<0 else y-tilt} L{x+w+1},{y-tilt if side<0 else y+tilt} "
                     f"V{y+h-4} Q{x+w+1},{y+h+1} {x+w-4},{y+h+1} H{x+4} Q{x-1},{y+h+1} {x-1},{y+h-4} Z")
            fill = "url(#vinylEye)" if style == "vinyl" else ("url(#celEye)" if style == "cel" else S["eye"])
            out.append(f'<path d="{d}" fill="{fill}"/>')
            if style == "cel":
                out.append(f'<rect x="{x+6}" y="{y+4}" width="5" height="6" fill="#fff"/>')
            elif style == "vinyl":
                out.append(f'<path d="{rr(x+6.5,y+4,4.5,5.5,2)}" fill="#fff" opacity="0.95"/>')
            else:
                out.append(f'<rect x="{x+6.5}" y="{y+4}" width="4" height="4.5" fill="#FFF8EE"/>')
        elif kind == "happy":
            sw = 6.5 if style != "cel" else 7
            col = S["eye"]
            out.append(f'<path d="M{cx-8},{-54} Q{cx},{-74} {cx+8},{-54}" fill="none" stroke="{col}" '
                       f'stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"/>')
        elif kind == "closed":
            col = S["eye"]
            out.append(f'<path d="M{cx-8},{-56} Q{cx},{-48} {cx+8},{-56}" fill="none" stroke="{col}" '
                       f'stroke-width="{4.5 if style!="cel" else 5}" stroke-linecap="round"/>')
    return "".join(out)


# ---------------------------------------------------------------- parts
def leg_paths(sx, legL):
    xs = [-51, -22, 22, 51]
    return [(x * sx - 7, -legL - 8, 14, legL + 8) for x in xs]


def arm_path(side):
    # shoulder at (side*70,-48); nub extends outward 27, height 22
    x = 64 if side > 0 else -91
    return (x, -59, 27, 22)


def character(style, pose, cx, ground, H, extras=True, prop=None):
    """H = pixel height of a neutral standing figure (body 100 + legs 23)."""
    S = STYLES[style]
    sx, sy, lift, legL, armL, armR, ek, lean = POSES[pose]
    s = H / 123.0
    o = [f'<g transform="translate({cx:.2f},{ground:.2f}) scale({s:.4f})">']
    bodyT = f"translate(0,{-legL+lift}) rotate({lean} 0 -50) scale({sx},{sy})"
    body_d = rr(-75, -100, 150, 100, S["r"])
    legs = leg_paths(sx, legL)

    # ---- ground shadow
    shw = 82 * sx * (0.8 if lift else 1)
    if style == "cel":
        o.append(f'<ellipse cx="0" cy="1" rx="{shw}" ry="7" fill="#2A1410" opacity="0.16"/>')
    elif style == "vinyl":
        o.append(f'<ellipse cx="0" cy="2" rx="{shw}" ry="9" fill="#5A2A18" opacity="0.28" filter="url(#blur4)"/>')
        o.append(f'<ellipse cx="0" cy="1" rx="{shw*0.7}" ry="4" fill="#3A1A10" opacity="0.25" filter="url(#blur2)"/>')
    else:
        o.append(f'<ellipse cx="4" cy="4" rx="{shw}" ry="9" fill="#10201C" opacity="0.35" filter="url(#blur4)"/>')

    def arm_g(side, rot):
        ax, ay, aw, ah = arm_path(side)
        pivot = (side * 70, -48)
        return ax, ay, aw, ah, f"rotate({rot} {pivot[0]} {pivot[1]})"

    # ---------------- PAPER: sticker backing first
    if style == "paper":
        sil = []
        for i, (lx, ly, lw, lh) in enumerate(legs):
            sil.append(f'<path d="{rr(lx,ly+lift,lw,lh,5)}"/>')
        bg = []
        for side, rot in ((-1, armL), (1, armR)):
            ax, ay, aw, ah, tr = arm_g(side, rot)
            bg.append(f'<path d="{rr(ax,ay,aw,ah,7)}" transform="{tr}"/>')
        bg.append(f'<path d="{body_d}"/>')
        sil_body = f'<g transform="{bodyT}">' + "".join(bg) + "</g>"
        allsil = "".join(sil) + sil_body
        o.append(f'<g transform="translate(3,5)" fill="#0E1C18" stroke="#0E1C18" stroke-width="12" '
                 f'stroke-linejoin="round" opacity="0.35" filter="url(#blur4)">{allsil}</g>')
        o.append(f'<g fill="#FFFDF7" stroke="#FFFDF7" stroke-width="12" stroke-linejoin="round">{allsil}</g>')

    # ---------------- legs
    for i, (lx, ly, lw, lh) in enumerate(legs):
        ly += lift
        if style == "vinyl":
            o.append(f'<path d="{rr(lx,ly,lw,lh,6)}" fill="url(#vinylLeg)" stroke="{S["outline"]}" stroke-width="{S["ow"]}"/>')
            o.append(f'<path d="{rr(lx+3,ly+lh-7,4,4,2)}" fill="#F3B494" opacity="0.6"/>')
        elif style == "cel":
            o.append(f'<path d="{rr(lx,ly,lw,lh,4)}" fill="{S["leg"]}" stroke="{S["outline"]}" stroke-width="{S["ow"]}"/>')
            o.append(f'<rect x="{lx+lw-5}" y="{ly+2}" width="4" height="{lh-4}" fill="{S["legd"]}"/>')
            o.append(f'<path d="{rr(lx,ly,lw,lh,4)}" fill="none" stroke="{S["outline"]}" stroke-width="{S["ow"]}"/>')
        else:
            o.append(f'<path d="{wobbly(lx,ly,lw,lh,4,i*13+5,0.5,30)}" fill="{S["leg"]}"/>')
            o.append(f'<path d="M{lx+lw*0.55},{ly+3} V{ly+lh-2}" stroke="{S["legd"]}" stroke-width="1" opacity="0.6"/>')

    # ---------------- body group (arms + body + face)
    o.append(f'<g transform="{bodyT}">')
    for side, rot in ((-1, armL), (1, armR)):
        ax, ay, aw, ah, tr = arm_g(side, rot)
        if style == "vinyl":
            o.append(f'<path d="{rr(ax,ay,aw,ah,10)}" fill="url(#vinylBody)" stroke="{S["outline"]}" stroke-width="{S["ow"]}" transform="{tr}"/>')
        elif style == "cel":
            o.append(f'<g transform="{tr}"><path d="{rr(ax,ay,aw,ah,7)}" fill="{S["base"]}" stroke="{S["outline"]}" stroke-width="{S["ow"]}"/>'
                     f'<rect x="{ax+2}" y="{ay+ah-7}" width="{aw-4}" height="5" fill="{S["shade"]}"/>'
                     f'<path d="{rr(ax,ay,aw,ah,7)}" fill="none" stroke="{S["outline"]}" stroke-width="{S["ow"]}"/></g>')
        else:
            o.append(f'<path d="{wobbly(ax,ay,aw,ah,8,side*31+7,0.5,34)}" fill="{S["shade"]}" transform="{tr}"/>')

    cid = uid("clip")
    o.append(f'<clipPath id="{cid}"><path d="{body_d}"/></clipPath>')
    if style == "vinyl":
        o.append(f'<path d="{body_d}" fill="url(#vinylBody)"/>')
        # rim light: bottom-right crescent
        o.append(f'<g clip-path="url(#{cid})"><path d="{body_d}" fill="{S["rim"]}" opacity="0.9"/>'
                 f'<path d="{body_d}" transform="translate(-4,-4.5)" fill="url(#vinylBody)" filter="url(#blur1)"/>'
                 # warm bounce at bottom
                 f'<ellipse cx="0" cy="4" rx="70" ry="12" fill="#8E3A20" opacity="0.35" filter="url(#blur4)"/>'
                 # sheen
                 f'<path d="{rr(-58,-94,74,13,6.5)}" fill="url(#gloss)" opacity="0.8"/>'
                 f'<circle cx="26" cy="-87" r="3.2" fill="#fff" opacity="0.7"/></g>')
        o.append(f'<path d="{body_d}" fill="none" stroke="{S["outline"]}" stroke-width="{S["ow"]}"/>')
    elif style == "cel":
        o.append(f'<path d="{body_d}" fill="{S["shade"]}"/>')
        o.append(f'<g clip-path="url(#{cid})">'
                 f'<path d="{rr(-75,-100,150,100,S["r"])}" transform="translate(-14,-17)" fill="{S["base"]}"/>'
                 f'<path d="{rr(-80,-112,84,26,13)}" fill="{S["light"]}" opacity="0.0"/>'
                 f'<path d="{rr(-60,-93,46,7,3.5)}" fill="#FFE2CF"/>'
                 f'<rect x="-9" y="-93" width="7" height="7" rx="1.5" fill="#FFE2CF"/>'
                 f'<rect x="3" y="-93" width="3.5" height="7" rx="1.2" fill="#FFE2CF"/>'
                 f'</g>')
        o.append(f'<path d="{body_d}" fill="none" stroke="{S["outline"]}" stroke-width="{S["ow"]}"/>')
    else:
        bd = wobbly(-75, -100, 150, 100, S["r"], 99, 0.9, 90)
        o.append(f'<path d="{bd}" fill="{S["base"]}"/>')
        rnd = random.Random(7)
        dots = "".join(f'<circle cx="{rnd.uniform(-74,74):.1f}" cy="{rnd.uniform(-99,-1):.1f}" r="{rnd.uniform(0.4,1.1):.2f}" fill="{rnd.choice(["#FFE6D6","#9E4A2F"])}"/>' for _ in range(220))
        o.append(f'<g clip-path="url(#{cid})" opacity="0.22">{dots}</g>')
        # torn lighter paper layer on top-left with its own soft shadow
        tear = "M-74,-99 H40 L44,-92 L38,-86 L42,-79 L33,-73 Q-10,-60 -74,-66 Z"
        o.append(f'<g clip-path="url(#{cid})">'
                 f'<path d="{tear}" transform="translate(1.5,2.5)" fill="#6E2E1C" opacity="0.35" filter="url(#blur2)"/>'
                 f'<path d="{tear}" fill="{S["light"]}"/>'
                 f'<path d="M-60,-89 L-30,-90" stroke="#FCD3BC" stroke-width="3" stroke-linecap="round" opacity="0.8"/>'
                 f'</g>')
        # lower fold line
        o.append(f'<path d="M-72,-20 Q0,-16 72,-20" stroke="#A84F33" stroke-width="1" fill="none" opacity="0.5" stroke-dasharray="3 3"/>')

    # cheeks
    if pose != "focused":
        a = 0.85 if pose == "happy" else 0.55
        if style == "vinyl":
            for sd in (-1, 1):
                o.append(f'<ellipse cx="{sd*52}" cy="-36" rx="10" ry="5.5" fill="{S["cheek"]}" opacity="{a}" filter="url(#blur2)"/>')
        elif style == "cel":
            for sd in (-1, 1):
                o.append(f'<ellipse cx="{sd*52}" cy="-36" rx="10" ry="5" fill="{S["cheek"]}" opacity="{a}"/>')
                for k in range(3):
                    x0 = sd * 52 - 6 + k * 5
                    o.append(f'<path d="M{x0},-33 L{x0+3},-39" stroke="#C93E3A" stroke-width="1.4" stroke-linecap="round"/>')
        else:
            for sd in (-1, 1):
                o.append(f'<circle cx="{sd*52}" cy="-35" r="7" fill="{S["cheek"]}" opacity="{0.9 if pose=="happy" else 0.75}"/>')

    o.append(eyes(style, ek, S, dx=4 if pose == "focused" else (6 if pose == "worried" else 0)))

    # tiny mouth for happy (open smile)
    if pose == "happy":
        mc = S["eye"]
        o.append(f'<path d="M-6,-40 Q0,-31 6,-40 Z" fill="{mc}"/>'
                 f'<path d="M-3,-35.5 Q0,-33 3,-35.5" stroke="#E0675A" stroke-width="2" fill="none" stroke-linecap="round"/>')
    if pose == "focused":
        mc = S["eye"]
        o.append(f'<path d="M-2,-38 Q6,-35 12,-39" stroke="{mc}" stroke-width="2.6" fill="none" stroke-linecap="round"/>'
                 f'<path d="M6,-36.6 Q9,-29 12.5,-33 Q12,-36 11,-38 Z" fill="#E86A60" stroke="{mc}" stroke-width="1.6" stroke-linejoin="round"/>')
    o.append("</g>")  # body group

    # ---------------- props / fx (in character space)
    if extras:
        if pose == "happy":
            sc = S["sparkstroke"]
            o.append(spark(0, -168, 15, S["spark"], stroke=S["outline"] if style == "cel" else sc, sw=2 if style == "cel" else 2.5, rot=8))
            for (x, y, r) in ((-100, -150, 9), (105, -140, 7), (-120, -95, 5), (118, -100, 5)):
                o.append(star4(x, y, r, "#FFC56E" if style != "paper" else "#FFE8B0",
                               f'stroke="{S["outline"] if style=="cel" else "none"}" stroke-width="2"'))
        elif pose == "neutral":
            o.append(spark(0, -152, 9, S["spark"], stroke=S["outline"] if style == "cel" else S["sparkstroke"], sw=1.8, rot=0, opacity=0.95))
        elif pose == "sleepy":
            o.append(spark(-46, -110, 6, S["spark"], stroke=S["outline"] if style == "cel" else S["sparkstroke"], sw=1.2, rot=20, opacity=0.6))
            zc = S["outline"] if style == "cel" else ("#8A4A36" if style == "vinyl" else "#FFF6E6")
            for i, (x, y, fs) in enumerate(((40, -120, 18), (60, -146, 24), (86, -178, 31))):
                o.append(f'<text x="{x}" y="{y}" font-family="Helvetica" font-weight="bold" font-size="{fs}" fill="{zc}" opacity="{0.55+0.15*i}">z</text>')
        elif pose == "focused":
            o.append(spark(-20, -150, 9, S["spark"], stroke=S["outline"] if style == "cel" else S["sparkstroke"], sw=1.8, rot=22))
            # motion arcs around spark (spinning)
            col = S["outline"] if style == "cel" else ("#B0563A" if style == "vinyl" else "#FFF6E6")
            o.append(f'<path d="M-36,-160 A18,18 0 0 1 -14,-170" stroke="{col}" stroke-width="2" fill="none" stroke-linecap="round" opacity="0.7"/>')
            o.append(f'<path d="M-4,-140 A18,18 0 0 1 -26,-131" stroke="{col}" stroke-width="2" fill="none" stroke-linecap="round" opacity="0.7"/>')
            o.append(file_prop(style, S, 96, -128, prop or "auth.ts"))
    o.append("</g>")
    return "".join(o)


def file_prop(style, S, x, y, name):
    """A floating document with a filename tab, held up next to the right nub."""
    w, h = 62, 78
    oc = S["outline"] if style == "cel" else ("#7A321E" if style == "vinyl" else "#FFFDF7")
    ow = 3 if style == "cel" else (1.6 if style == "vinyl" else 0)
    g = [f'<g transform="rotate(7 {x} {y})">']
    if style == "paper":
        g.append(f'<path d="{rr(x-4,y-4,w+8,h+8,6)}" fill="#FFFDF7" transform="translate(2,4)" opacity="0.3" filter="url(#blur2)"/>')
    if style == "vinyl":
        g.append(f'<path d="{rr(x,y,w,h,5)}" fill="#3A1A10" opacity="0.18" transform="translate(3,5)" filter="url(#blur2)"/>')
    # glow behind for magic
    if style != "paper":
        g.append(f'<ellipse cx="{x+w/2}" cy="{y+h/2}" rx="{w*0.75}" ry="{h*0.65}" fill="#FFE9A8" opacity="0.35" filter="url(#blur8)"/>')
    g.append(f'<path d="M{x},{y} H{x+w-14} L{x+w},{y+14} V{y+h} H{x} Z" fill="#FFFCF5" stroke="{oc}" stroke-width="{ow}" stroke-linejoin="round"/>')
    g.append(f'<path d="M{x+w-14},{y} V{y+14} H{x+w}" fill="#EADFD0" stroke="{oc}" stroke-width="{ow}" stroke-linejoin="round"/>')
    cols = ["#D97757", "#6A8CAF", "#9A9A9A", "#7FA36B", "#6A8CAF", "#9A9A9A", "#D97757"]
    widths = [30, 40, 22, 36, 28, 40, 18]
    for i, (c, ww) in enumerate(zip(cols, widths)):
        ind = 6 if i in (2, 3, 4) else 0
        g.append(f'<rect x="{x+7+ind}" y="{y+22+i*7.5}" width="{ww-ind}" height="3.2" rx="1.6" fill="{c}"/>')
    # filename tag
    tw = len(name) * 6.4 + 12
    g.append(f'<path d="{rr(x-2,y-17,tw,15,7.5)}" fill="#2B1D18"/>')
    g.append(f'<text x="{x+4}" y="{y-6.3}" font-family="Menlo" font-size="10" fill="#FFF3E6">{name}</text>')
    g.append("</g>")
    return "".join(g)


# ---------------------------------------------------------------- sheet
def desktop_strip(style, y0, x0=60, w=1480, h=480):
    o = []
    cid = uid("dclip")
    o.append(f'<clipPath id="{cid}"><path d="{rr(x0,y0,w,h,20)}"/></clipPath>')
    o.append(f'<linearGradient id="wall{cid}" x1="0" y1="0" x2="1" y2="1">'
             f'<stop offset="0" stop-color="#233159"/><stop offset="0.55" stop-color="#6C4E86"/><stop offset="1" stop-color="#E59A72"/></linearGradient>')
    o.append(f'<g clip-path="url(#{cid})">')
    o.append(f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" fill="url(#wall{cid})"/>')
    o.append(f'<path d="M{x0},{y0+h} L{x0},{y0+330} Q{x0+300},{y0+250} {x0+620},{y0+340} T{x0+1200},{y0+300} T{x0+w},{y0+280} V{y0+h} Z" fill="#1A2242" opacity="0.55"/>')
    o.append(f'<rect x="{x0}" y="{y0}" width="{w}" height="24" fill="#FFFFFF" opacity="0.28"/>')
    o.append(f'<text x="{x0+40}" y="{y0+17}" font-family="Helvetica" font-weight="bold" font-size="13" fill="#fff">Terminal     File     Edit     View     Window</text>')
    o.append(spark(x0 + w - 150, y0 + 12, 6, "#D97757", stroke="#fff", sw=1))
    o.append(f'<text x="{x0+w-130}" y="{y0+17}" font-family="Helvetica" font-size="13" fill="#fff">Fri 20 Nov  14:02</text>')
    # terminal window
    tx, ty, tw, th = x0 + 60, y0 + 220, 600, 300
    def win(x, y, ww, hh, body, bar):
        r = [f'<path d="{rr(x+4,y+10,ww,hh,12)}" fill="#0A0A14" opacity="0.35" filter="url(#blur8)"/>',
             f'<path d="{rr(x,y,ww,hh,12)}" fill="{body}"/>',
             f'<path d="{rr(x,y,ww,28,12)}" fill="{bar}"/><rect x="{x}" y="{y+16}" width="{ww}" height="12" fill="{bar}"/>']
        for i, c in enumerate(("#FF5F57", "#FEBC2E", "#28C840")):
            r.append(f'<circle cx="{x+18+i*18}" cy="{y+14}" r="5.5" fill="{c}"/>')
        return "".join(r)
    o.append(win(tx, ty, tw, th, "#1E1B22", "#2C2832"))
    lines = [("#D97757", 160), ("#8FA9C8", 300), ("#9E9AA6", 240), ("#A6C48A", 200), ("#9E9AA6", 340), ("#8FA9C8", 120)]
    for i, (c, lw) in enumerate(lines):
        o.append(f'<rect x="{tx+20}" y="{ty+46+i*20}" width="{lw}" height="7" rx="3.5" fill="{c}" opacity="0.85"/>')
    ex, ey, ew, eh = x0 + 780, y0 + 250, 480, 270
    o.append(win(ex, ey, ew, eh, "#F6F4F1", "#E4E0DB"))
    for i in range(8):
        o.append(f'<rect x="{ex+24+(i%3)*14}" y="{ey+48+i*20}" width="{120+(i*53)%260}" height="7" rx="3.5" fill="{["#C26B4E","#4F6E96","#8A8A8A","#5E8A52"][i%4]}" opacity="0.75"/>')
    # desktop icons
    for i in range(3):
        o.append(f'<path d="{rr(x0+w-70,y0+50+i*62,38,44,5)}" fill="#EAF0FA" opacity="0.9"/>')
        o.append(f'<rect x="{x0+w-76}" y="{y0+99+i*62}" width="50" height="6" rx="3" fill="#fff" opacity="0.6"/>')
    # dock
    dx, dw = x0 + 300, 560
    o.append(f'<path d="{rr(dx,y0+h-62,dw,56,16)}" fill="#FFFFFF" opacity="0.3"/>')
    cols = ["#4C8DF6", "#F25C54", "#2E2E3A", "#D97757", "#59C36A", "#F2B93B", "#9B6CF0", "#7A8A99"]
    for i, c in enumerate(cols):
        o.append(f'<path d="{rr(dx+16+i*67,y0+h-54,42,42,10)}" fill="{c}"/>')
    o.append("</g>")
    o.append(character(style, "neutral", tx + 440, ty, 128, extras=False))
    o.append(character(style, "focused", ex + 150, ey, 160, extras=True))
    o.append(character(style, "sleepy", x0 + w - 120, y0 + h - 12, 96, extras=False))
    for (x, y, t) in ((tx + 440, ty - 150, "128 pt"), (ex - 20, ey - 110, "160 pt"), (x0 + w - 120, y0 + h - 100, "96 pt")):
        o.append(f'<text x="{x}" y="{y}" text-anchor="middle" font-family="Helvetica" font-weight="bold" font-size="13" fill="#fff" opacity="0.9">{t}</text>')
    return "".join(o)


SHEET = {
    "vinyl": dict(title="A  ·  Soft Vinyl", sub="Designer-toy Claudette: glossy key light, peach rim light, blurred contact shadow, warm-brown keyline for desktop legibility.",
                  bg="#FBF1E6", bg2="#F3DCC8", ink="#3A1F16"),
    "cel": dict(title="B  ·  Ink &amp; Cel", sub="Anime-chibi cel shade: hard two-tone shadow, chunky ink outline, tall glossy eyes with warm lower reflection. Maps 1:1 to a 3D toon shader.",
                bg="#EEF0F7", bg2="#D9DDEE", ink="#22202E"),
    "paper": dict(title="C  ·  Paper Sticker", sub="Hand-cut paper on a cutting mat: die-cut white border, torn top layer, grain. The white edge pops on any wallpaper.",
                  bg="#2F5A53", bg2="#244741", ink="#FFF6E6"),
}


def sheet(style):
    T = SHEET[style]
    W, Hh = 1600, 1200
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{Hh}" viewBox="0 0 {W} {Hh}">',
         "<defs>" + defs_common() + "</defs>"]
    o.append(f'<rect width="{W}" height="{Hh}" fill="{T["bg"]}"/>')
    if style == "paper":
        for gx in range(0, W, 40):
            o.append(f'<line x1="{gx}" y1="0" x2="{gx}" y2="{Hh}" stroke="#4E7C73" stroke-width="{1.2 if gx%200==0 else 0.6}" opacity="0.6"/>')
        for gy in range(0, Hh, 40):
            o.append(f'<line x1="0" y1="{gy}" x2="{W}" y2="{gy}" stroke="#4E7C73" stroke-width="{1.2 if gy%200==0 else 0.6}" opacity="0.6"/>')
    else:
        o.append(f'<ellipse cx="800" cy="420" rx="760" ry="260" fill="{T["bg2"]}" opacity="0.7" filter="url(#blur8)"/>')
        if style == "cel":
            for i in range(-6, 30):
                o.append(f'<path d="M{i*60},0 L{i*60+300},1000" stroke="#FFFFFF" stroke-width="14" opacity="0.35"/>')
    o.append(f'<text x="60" y="78" font-family="Helvetica" font-weight="bold" font-size="40" fill="{T["ink"]}">{T["title"]}</text>')
    o.append(f'<text x="62" y="110" font-family="Helvetica" font-size="17" fill="{T["ink"]}" opacity="0.75">{T["sub"]}</text>')
    xs = (200, 580, 980, 1385)
    for x, pose, lab in zip(xs, ("neutral", "happy", "focused", "sleepy"),
                            ("neutral / idle", "happy (task done)", "focused (Read auth.ts)", "sleepy (session idle)")):
        o.append(character(style, pose, x, 530, 185))
        o.append(f'<text x="{x}" y="580" text-anchor="middle" font-family="Helvetica" font-size="17" fill="{T["ink"]}" opacity="0.8">{lab}</text>')
    o.append(f'<text x="60" y="650" font-family="Helvetica" font-weight="bold" font-size="15" fill="{T["ink"]}" opacity="0.7">ACTUAL SIZE ON A BUSY DESKTOP (1 pt = 2 px on Retina)</text>')
    o.append(desktop_strip(style, 670))
    o.append("</svg>")
    return "\n".join(o)


if __name__ == "__main__":
    for st in sys.argv[2:] or STYLES:
        p = f"{OUT}/{st}.svg"
        with open(p, "w") as f:
            f.write(sheet(st))
        print(p)
