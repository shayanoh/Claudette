"""Claudette tool props, style B: bold ink, hard two-tone cel, one soft highlight.

Same contract as parts.py: points, y DOWN, pivot at (0, 0); each function returns
(svg_fragment, box). Centred props are drawn around their visual centre.
"""
import math

from parts import C, INK as BODY_INK, rr  # BODY_INK: rig-scale props (jar, bag, bin)

INK = 3.0  # prop ink: bold but lighter than her 4.6 body line
H = INK / 2
INK_C = C["outline"]
PAPER, PAPER_D = "#FFF8F0", "#EADFD0"
GREY, GREY_D, METAL = "#E8E8E8", "#B4B4B4", "#C9C9D1"
LINES = ["#E07C56", "#7FA3D6", "#8FBF7F", "#B0B0B0"]
GREEN = "#8FBF7F"
_ids = [0]


def _id(p):
    _ids[0] += 1
    return f"{p}{_ids[0]}"


def cel(d, base, shade, off=(-4, -4), inner="", ink=INK, rule="nonzero"):
    """Shade fill, base shifted up-left (uncovers an L cel shadow), extras clipped, ink on top."""
    cid = _id("c")
    return (f'<defs><clipPath id="{cid}"><path d="{d}" clip-rule="{rule}"/></clipPath></defs>'
            f'<path d="{d}" fill="{shade}" fill-rule="{rule}"/>'
            f'<g clip-path="url(#{cid})"><path d="{d}" transform="translate({off[0]},{off[1]})" '
            f'fill="{base}" fill-rule="{rule}"/>{inner}</g>'
            f'<path d="{d}" fill="none" stroke="{INK_C}" stroke-width="{ink}" stroke-linejoin="round"/>')


def gloss(x, y, w, h, opacity=0.7):
    """The soft highlight: a blurred white streak."""
    fid = _id("g")
    return (f'<filter id="{fid}" x="-50%" y="-50%" width="200%" height="200%">'
            f'<feGaussianBlur stdDeviation="0.6"/></filter>'
            f'<path d="{rr(x, y, w, h, h/2)}" fill="#fff" opacity="{opacity}" filter="url(#{fid})"/>')


def bar(x, y, w, col, h=2.6):
    return f'<path d="{rr(x, y - h/2, w, h, h/2)}" fill="{col}"/>'


def star4(x, y, r, fill):
    k = r * 0.28
    return (f'<path d="M{x},{y-r} Q{x+k},{y-k} {x+r},{y} Q{x+k},{y+k} {x},{y+r} '
            f'Q{x-k},{y+k} {x-r},{y} Q{x-k},{y-k} {x},{y-r} Z" fill="{fill}" '
            f'stroke="{INK_C}" stroke-width="1.6" stroke-linejoin="round"/>')


PW, PH = 30, 38  # page


def _page_box():
    return (-PW / 2 - H, -PH / 2 - H, PW / 2 + H, PH / 2 + H)


def prop_read():
    d = rr(-PW / 2, -PH / 2, PW, PH, 2.5)
    rows = [(-10, 18, 0), (-4, 14, 1), (2, 20, 2), (8, 11, 3), (14, 16, 0)]
    inner = gloss(-12, -16, 9, 2.4) + "".join(bar(-10, y, w, LINES[c]) for y, w, c in rows)
    return cel(d, PAPER, PAPER_D, inner=inner), _page_box()


def prop_edit():
    """Diff page: grey context lines, one removed (orange) and one added (green) with gutter marks."""
    d = rr(-PW / 2, -PH / 2, PW, PH, 2.5)
    inner = (gloss(-12, -16, 9, 2.4)
             + bar(-10, -10, 16, LINES[3]) + bar(-10, -3, 12, LINES[3])
             + f'<rect x="-13" y="2" width="26" height="6" fill="#F7D3C4"/>'
             + f'<rect x="-13" y="9" width="26" height="6" fill="#DDEFD6"/>'
             + bar(-10, 5, 18, LINES[0]) + bar(-10, 12, 15, GREEN))
    return cel(d, PAPER, PAPER_D, inner=inner), _page_box()


def prop_write():
    """Fresh page: folded top-right corner, one short line, a sparkle."""
    x0, y0, x1, y1, f = -PW / 2, -PH / 2, PW / 2, PH / 2, 9
    d = f"M{x0+2},{y0} H{x1-f} L{x1},{y0+f} V{y1-2} Q{x1},{y1} {x1-2},{y1} H{x0+2} Q{x0},{y1} {x0},{y1-2} V{y0+2} Q{x0},{y0} {x0+2},{y0} Z"
    fold = f'<path d="M{x1-f},{y0} V{y0+f} H{x1} Z" fill="{PAPER_D}" stroke="{INK_C}" stroke-width="2" stroke-linejoin="round"/>'
    inner = gloss(-12, -16, 8, 2.4) + bar(-10, 12, 12, LINES[0])
    svg = cel(d, PAPER, PAPER_D, inner=inner) + fold + star4(-1, -2, 7, "#FFC94D")
    return svg, _page_box()


def prop_search():
    cx, cy, r = -4, -5, 11
    a = math.radians(45)
    hx, hy = cx + math.cos(a) * (r + 3), cy + math.sin(a) * (r + 3)
    handle = (f'<g transform="translate({hx:.2f},{hy:.2f}) rotate(-45)">'
              + cel(rr(-3.5, 0, 7, 15, 3), C["leg"], C["legd"], off=(-2, 0)) + "</g>")
    lens = (f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="#7FC8F8" opacity="0.4"/>'
            f'<path d="M{cx-7},{cy-2} A7,7 0 0 1 {cx-2},{cy-7}" stroke="#fff" stroke-width="2.4" '
            f'fill="none" stroke-linecap="round" opacity="0.85"/>'
            f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{INK_C}" stroke-width="7"/>'
            f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{METAL}" stroke-width="2.2"/>')
    end = (r + 3 + 15) * math.cos(a) + 4
    return handle + lens, (cx - r - 3.5, cy - r - 3.5, cx + end, cy + end)


def prop_edit_pencil():
    """Tip at the pivot (bottom), body rising 34 pt; code scribbles it about the tip."""
    w = 4
    clip_d = f"M0,-1.5 L{-w},-10 V-32 Q{-w},-34 {-w+2},-34 H{w-2} Q{w},-34 {w},-32 V-10 Z"
    inner = (f'<rect x="-5" y="-29" width="10" height="19" fill="#FFC94D"/>'
             f'<rect x="1.5" y="-29" width="3" height="19" fill="#E0A030"/>'
             f'<path d="M0,-1.5 L-5,-10 H5 Z" fill="#F3D2A8"/>'
             f'<path d="M0,-1.5 L-1.8,-5 H1.8 Z" fill="{INK_C}"/>'
             f'<rect x="-5" y="-32" width="10" height="3" fill="{METAL}"/>'
             f'<rect x="-5" y="-35" width="10" height="3" fill="{C["cheek"]}"/>'
             + gloss(-3.2, -27, 1.8, 14, 0.6))
    cid = _id("p")
    svg = (f'<defs><clipPath id="{cid}"><path d="{clip_d}"/></clipPath></defs>'
           f'<g clip-path="url(#{cid})">{inner}</g>'
           f'<path d="M-4,-10 H4" stroke="{INK_C}" stroke-width="1.4"/>'
           f'<path d="{clip_d}" fill="none" stroke="{INK_C}" stroke-width="{INK}" stroke-linejoin="round"/>')
    return svg, (-w - H, -34 - H, w + H, 0)


# ---------------------------------------------------------------- terminals
TERM, TERM_D, TERM_BAR = "#1F1B18", "#120F0D", "#3A332E"


def _terminal(w, h, cy=0):
    x0, y0 = -w / 2 + H, cy - h / 2 + H
    iw, ih = w - INK, h - INK
    d = rr(x0, y0, iw, ih, 4)
    inner = (f'<rect x="{x0}" y="{y0}" width="{iw}" height="6" fill="{TERM_BAR}"/>'
             + gloss(x0 + 3, y0 + 1.6, iw * 0.35, 2, 0.35)
             + f'<path d="M{x0+5},{cy-1} L{x0+10},{cy+3} L{x0+5},{cy+7}" stroke="#9BE38B" '
               f'stroke-width="2.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'
             + f'<rect x="{x0+13}" y="{cy+5}" width="7" height="3" fill="#9BE38B"/>')
    return cel(d, TERM, TERM_D, off=(-3, -3), inner=inner)


def prop_shell():
    return _terminal(46, 32), (-23, -16, 23, 16)


SOCKET = (0, -15, 7.5)  # spinner socket centre/radius in prop_shell_long's y-down space


def prop_shell_long():
    """Chunkier terminal with a recessed spinner socket on a mount above it."""
    sx, sy, sr = SOCKET
    mount = cel(rr(-11, -12, 22, 9, 3), TERM_BAR, TERM_D, off=(-2, -2))
    socket = (f'<circle cx="{sx}" cy="{sy}" r="{sr}" fill="{TERM_BAR}" stroke="{INK_C}" stroke-width="{INK}"/>'
              f'<circle cx="{sx}" cy="{sy}" r="{sr-2.6}" fill="#0B0908"/>'
              f'<path d="M{sx-sr+2.2},{sy+1} A{sr-2.2},{sr-2.2} 0 0 0 {sx+sr-2.2},{sy+1}" '
              f'stroke="#5A4E46" stroke-width="1.4" fill="none"/>')
    return mount + _terminal(48, 30, cy=8) + socket, (-24, sy - sr - H, 24, 23)


def gear(cx, cy, ro, ri, teeth, hole, base, shade, ink=INK):
    pts = []
    n = teeth * 4
    for k in range(n):
        a = 2 * math.pi * (k - 0.5) / n
        r = ro if k % 4 in (1, 2) else ri
        pts.append(f"{cx+math.cos(a)*r:.2f},{cy+math.sin(a)*r:.2f}")
    d = "M" + " L".join(pts) + " Z"
    d += (f" M{cx+hole},{cy} A{hole},{hole} 0 1 0 {cx-hole},{cy} A{hole},{hole} 0 1 0 {cx+hole},{cy} Z")
    off = (-ro * 0.18, -ro * 0.18)
    return cel(d, base, shade, off=off, ink=ink, rule="evenodd")


def prop_shell_bg():
    """Terminal with a small gear badge: running in the background."""
    return _terminal(46, 32) + gear(16, -11, 8, 6, 6, 2.4, METAL, "#9A9AA6", ink=2.4), (-23, -20.5, 25.5, 16)


def prop_other():
    return gear(0, 0, 17, 13, 8, 5, GREY, "#A8A8B2") + gloss(-10, -9, 6, 2.2, 0.6), (-18.5, -18.5, 18.5, 18.5)


def prop_web():
    """Paper plane flying right."""
    A, B, Cc, D = (19, -8), (-19, -13), (-5, 1), (-13, 14)
    p = lambda *q: "M" + " L".join(f"{x},{y}" for x, y in q) + " Z"
    svg = (f'<path d="{p(A, Cc, D)}" fill="{PAPER_D}"/>'
           f'<path d="{p(A, B, Cc)}" fill="{PAPER}"/>'
           + gloss(-12, -10.5, 10, 2, 0.8)
           + f'<path d="M{Cc[0]},{Cc[1]} L{A[0]},{A[1]}" stroke="{INK_C}" stroke-width="1.8" stroke-linecap="round"/>'
           f'<path d="{p(A, B, Cc, D)}" fill="none" stroke="{INK_C}" stroke-width="{INK}" stroke-linejoin="round"/>')
    return svg, (-21, -15, 21, 16)


def prop_skill():
    """Spellbook with a gold gem and a soft warm rim glow."""
    fid = _id("glow")
    glow = (f'<filter id="{fid}" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="2.5"/></filter>'
            f'<path d="{rr(-17, -21, 34, 42, 5)}" fill="#FFD978" opacity="0.75" filter="url(#{fid})"/>')
    d = rr(-15, -19, 30, 38, 3)
    inner = (f'<rect x="12" y="-17" width="3" height="34" fill="{PAPER}"/>'
             f'<rect x="-15" y="-19" width="6" height="38" fill="#5A6CB0"/>'
             f'<path d="M-9,-19 V19" stroke="{INK_C}" stroke-width="1.6"/>'
             + gloss(-6, -16, 12, 2.4, 0.55))
    gem = (f'<path d="M3,-7 L9,0 L3,7 L-3,0 Z" fill="#FFC94D" stroke="{INK_C}" stroke-width="2" stroke-linejoin="round"/>'
           f'<path d="M3,-7 L9,0 H-3 Z" fill="#FFE29A"/>'
           f'<path d="M3,-7 L9,0 L3,7 L-3,0 Z" fill="none" stroke="{INK_C}" stroke-width="2" stroke-linejoin="round"/>')
    return glow + cel(d, "#7B8FD1", "#6375BE", off=(-3, -3), inner=inner) + gem, (-25, -29, 25, 29)


def prop_todo():
    """Clipboard: three checkbox rows, two ticked."""
    board = cel(rr(-15, -17, 30, 37, 3), "#D8B98A", "#B8956A", off=(-3, -3))
    paper = f'<path d="{rr(-11, -11, 22, 27, 1.5)}" fill="{PAPER}" stroke="{INK_C}" stroke-width="1.6"/>'
    rows = ""
    for i, done in enumerate((True, True, False)):
        y = -6 + i * 8
        rows += (f'<path d="{rr(-8, y-2.5, 5, 5, 1)}" fill="{"#9BE38B" if done else "#fff"}" '
                 f'stroke="{INK_C}" stroke-width="1.4"/>' + bar(-1, y, 8 if i == 1 else 9, LINES[3], 2.2))
        if done:
            rows += (f'<path d="M-7,{y} L-5.6,{y+1.4} L-3.2,{y-2}" stroke="{INK_C}" stroke-width="1.4" '
                     f'fill="none" stroke-linecap="round" stroke-linejoin="round"/>')
    clip = cel(rr(-7, -21, 14, 7, 2), METAL, "#9A9AA6", off=(-1.5, -1.5), ink=2.4)
    return board + paper + rows + clip, (-16.5, -22.2, 16.5, 21.5)


def prop_plan():
    """Blueprint sheet with white floor-plan line work."""
    d = rr(-19, -15, 38, 30, 2)
    w = 'stroke="#fff" fill="none" stroke-linecap="round"'
    inner = (f'<rect x="-15" y="-11" width="30" height="22" {w} stroke-width="1" opacity="0.6"/>'
             f'<path d="M-11,-7 H11 V8 H-11 Z" {w} stroke-width="1.6"/>'
             f'<path d="M1,-7 V2 M-11,1 H-4" {w} stroke-width="1.6"/>'
             f'<path d="M-4,1 A5,5 0 0 1 1,-4" {w} stroke-width="1.1"/>'
             f'<circle cx="6" cy="3" r="2.2" {w} stroke-width="1.2"/>'
             + gloss(-16, -13, 10, 1.8, 0.5))
    return cel(d, "#3A6EA5", "#2D5A8A", off=(-3, -3), inner=inner), (-20.5, -16.5, 20.5, 16.5)


# ---------------------------------------------------------------- MCP cartridges
WIN = "#FAFAFA"
CART = (-16, -19, 16, 19)


def _cartridge(glyph=""):
    """Tintable cartridge: light neutral body, empty pale label window centred on the anchor."""
    x0, y0, x1, y1 = CART
    d = f"M{x0+3},{y0} H{x1-7} L{x1},{y0+7} V{y1-3} Q{x1},{y1} {x1-3},{y1} H{x0+3} Q{x0},{y1} {x0},{y1-3} V{y0+3} Q{x0},{y0} {x0+3},{y0} Z"
    ridges = "".join(f'<path d="M-10,{y} H5" stroke="{GREY_D}" stroke-width="1.3" stroke-linecap="round"/>'
                     for y in (-16, -13.5))
    inner = ridges + gloss(-14, -9, 2, 12, 0.6)
    window = (f'<path d="{rr(-11, -8, 22, 16, 2.5)}" fill="{WIN}" stroke="{INK_C}" stroke-width="2"/>'
              f'<path d="M-9.5,-6.4 H9.5" stroke="#D6D6D6" stroke-width="1.6" stroke-linecap="round"/>')
    pins = "".join(f'<rect x="{x}" y="12.5" width="2.6" height="5" rx="0.6" fill="{METAL}" '
                   f'stroke="{INK_C}" stroke-width="1"/>' for x in (-10.3, -5.3, -0.3, 4.7, 9.7))
    return cel(d, GREY, GREY_D, off=(-3, -3), inner=inner) + window + pins + glyph, (x0 - H, y0 - H, x1 + H, y1 + H)


def prop_mcp_generic():
    return _cartridge()


def prop_mcp_github():
    """Round cat-blob head with ears; eyes cut out."""
    g = (f'<path d="M-5,-1 L-4.6,-6 L-1.8,-3.6 Q0,-4.2 1.8,-3.6 L4.6,-6 L5,-1 Q6,4.6 0,5 Q-6,4.6 -5,-1 Z '
         f'M-2.6,0 a1,1.3 0 1 0 0.01,0 Z M2.6,0 a1,1.3 0 1 0 0.01,0 Z" fill="{INK_C}" fill-rule="evenodd"/>')
    return _cartridge(g)


def prop_mcp_playwright():
    """Two overlapping theatre masks."""
    mask = "M-4.2,-4 H4.2 V0 Q4.2,5 0,6 Q-4.2,5 -4.2,0 Z"
    g = (f'<g transform="translate(-2.6,-0.6) rotate(-12)"><path d="{mask} M-2.2,-1.6 h1.6 v0.9 h-1.6 Z M0.6,-1.6 h1.6 v0.9 h-1.6 Z" '
         f'fill="{INK_C}" fill-rule="evenodd"/></g>'
         f'<g transform="translate(3,1) rotate(12)"><path d="{mask}" fill="{WIN}" stroke="{INK_C}" stroke-width="1.4" stroke-linejoin="round"/>'
         f'<path d="M-2,2.8 Q0,1.4 2,2.8" stroke="{INK_C}" stroke-width="1.1" fill="none" stroke-linecap="round"/></g>')
    return _cartridge(g)


def prop_mcp_figma():
    """Five rounded blocks: two columns, the right middle one a dot."""
    u, gap = 4, 0.5
    blocks = [(-1, -1.5), (0, -1.5), (-1, -0.5), (-1, 0.5)]
    g = "".join(f'<path d="{rr(c*u+gap/2, r*u+gap/2, u-gap, u-gap, 1.6)}" fill="{INK_C}"/>' for c, r in blocks)
    g += f'<circle cx="{u/2}" cy="0" r="{(u-gap)/2}" fill="{INK_C}"/>'
    return _cartridge(g)


def prop_mcp_context7():
    """Small open book with a 7-like fold on the right page."""
    g = (f'<path d="M0,-3.5 Q-3.5,-5.5 -7,-4.5 V4.5 Q-3.5,3.5 0,5.5 Q3.5,3.5 7,4.5 V-4.5 Q3.5,-5.5 0,-3.5 Z M0,-3.5 V5.5" '
         f'fill="none" stroke="{INK_C}" stroke-width="1.5" stroke-linejoin="round"/>'
         f'<path d="M1.8,-1.6 H5.2 L3,3" stroke="{INK_C}" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>')
    return _cartridge(g)


def prop_mcp_cable():
    """Connector plug head pointing +x; pivot at the cable end (x = 0, centre height)."""
    body = cel(rr(H, -5.5, 11.5, 11, 2.5), GREY, GREY_D, off=(-2, -2))
    pins = "".join(f'<rect x="{H+11.5}" y="{y}" width="4.5" height="2" rx="0.5" fill="{METAL}" '
                   f'stroke="{INK_C}" stroke-width="1"/>' for y in (-3.6, 1.6))
    return body + pins, (0, -7, H + 16.5, 7)


# ---------------------------------------------------------------- cleanup scene
# Pivot = bottom centre of the base (anchor [0.5, 0]). Can and lid share one canvas so the lid
# sits on the can at (0, 0); the lid swings about TRASH_HINGE (y down here, so y up = (34, 77)).
TRASH_HINGE = (34, -77)
TRASH_BOX = (-42, -96, 42, 0)  # union of can and lid, both report it so the canvases match
TIN, TIN_D, TIN_L, HOLE = "#C9C9D1", "#9A9AA6", "#E4E4EA", "#2B2530"


def trash_can():
    """Slightly dented metal bin, open on top: tapered body with two rings, a dent on the right,
    rolled rim around a dark opening and the hinge knuckle at the back right of the rim."""
    d = ("M-33,-72 H33 L31.6,-46 Q27.6,-39 30.6,-31 L29,-6 Q28.6,0 22.6,0 "
         "H-22.6 Q-28.6,0 -29,-6 Z")
    rings = "".join(f'<path d="M-36,{y} H36" stroke="{INK_C}" stroke-width="2"/>'
                    f'<path d="M-36,{y+2.2} H36" stroke="{TIN_L}" stroke-width="1.6"/>' for y in (-52, -20))
    inner = (rings + gloss(-27, -66, 4, 18, 0.7) + gloss(-27, -44, 4, 12, 0.55)
             + f'<path d="M26.4,-44 Q23.4,-38.5 26,-32" stroke="{TIN_D}" stroke-width="3" fill="none" '
               f'stroke-linecap="round"/>'
             + f'<path d="M24.6,-43 Q21.8,-38.5 24.2,-33.5" stroke="{TIN_L}" stroke-width="1.4" fill="none" '
               f'stroke-linecap="round"/>')
    body = cel(d, TIN, TIN_D, off=(-5, -3), inner=inner, ink=BODY_INK)
    rim_d = rr(-37, -79, 74, 9, 4.5)
    rim = cel(rim_d, TIN_L, TIN, off=(-2, -2), ink=INK)
    hole = (f'<ellipse cx="0" cy="-76.5" rx="31" ry="3.6" fill="{HOLE}"/>'
            f'<path d="M-29,-75.6 Q0,-72.8 29,-75.6" stroke="#4A4250" stroke-width="1.4" fill="none"/>')
    hx, hy = TRASH_HINGE
    knuckle = f'<path d="{rr(hx-3, hy-4.5, 7, 9, 2.5)}" fill="{TIN_D}" stroke="{INK_C}" stroke-width="2"/>'
    return body + rim + hole + knuckle, TRASH_BOX


def trash_lid():
    """Domed lid with a loop handle; closed it covers the opening, its hinge leaf over the knuckle.
    Reads swung open too: the underside rim shows as the dark band along its bottom edge."""
    d = "M-38,-76 Q-38,-82 -31,-83.5 Q0,-91 31,-83.5 Q38,-82 38,-76 Q38,-73 35,-73 H-35 Q-38,-73 -38,-76 Z"
    inner = (f'<path d="M-38,-75.6 H38 V-72 H-38 Z" fill="{TIN_D}"/>'
             + gloss(-28, -84.5, 20, 2.4, 0.8))
    lid = cel(d, TIN, TIN_D, off=(-4, -2.5), inner=inner, ink=BODY_INK)
    handle = (f'<path d="M-9,-87.6 V-91 Q-9,-94 -6,-94 H6 Q9,-94 9,-91 V-87.6" fill="none" '
              f'stroke="{INK_C}" stroke-width="{BODY_INK + 3.4}" stroke-linejoin="round" stroke-linecap="round"/>'
              f'<path d="M-9,-87.6 V-91 Q-9,-94 -6,-94 H6 Q9,-94 9,-91 V-87.6" fill="none" '
              f'stroke="{TIN_D}" stroke-width="3.4" stroke-linejoin="round" stroke-linecap="round"/>')
    hx, hy = TRASH_HINGE
    leaf = f'<path d="{rr(hx-5, hy-2.5, 9, 5, 2)}" fill="{TIN_D}" stroke="{INK_C}" stroke-width="2"/>'
    return handle + lid + leaf, TRASH_BOX
