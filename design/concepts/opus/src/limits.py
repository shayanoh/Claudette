"""Usage-limit treatment sheet: Spark Jar (5h window) + Moon (weekly window)."""
import math, random, sys
import claudette as C
from claudette import rr, spark, star4, character, defs_common

OUT = sys.argv[1]
INK = "#3A1A12"

C.POSES["worried"] = (1.0, 1.0, 0, 23, -6, -20, "open", 0)
C.POSES["nap"] = (1.08, 0.88, 0, 6, -18, 18, "closed", 0)
C.POSES["cheer"] = (0.93, 1.09, -26, 22, 60, -60, "happy", 0)


def jar(x, yb, w, h, frac, label, sub, dim=False, burst=False, seed=1, tag=True):
    """Glass jar of sparks. x = centre, yb = bottom."""
    cid = C.uid("jar")
    top = yb - h
    o = []
    body = rr(x - w / 2, top + 16, w, h - 16, 16)
    o.append(f'<clipPath id="{cid}"><path d="{body}"/></clipPath>')
    o.append(f'<ellipse cx="{x}" cy="{yb+2}" rx="{w*0.55}" ry="5" fill="#000" opacity="0.15"/>')
    if burst:
        o.append(f'<circle cx="{x}" cy="{top+h*0.4}" r="{w*0.95}" fill="#FFE59A" opacity="0.55" filter="url(#blur8)"/>')
    elif frac > 0 and not dim:
        o.append(f'<ellipse cx="{x}" cy="{yb-h*frac/2}" rx="{w*0.8}" ry="{h*frac*0.7+8}" fill="#FFD27A" opacity="0.35" filter="url(#blur8)"/>')
    # glass back
    o.append(f'<path d="{body}" fill="#FFFFFF" opacity="{0.10 if dim else 0.35}"/>')
    # sparks content
    lvl = yb - (h - 22) * frac - 4
    g = [f'<g clip-path="url(#{cid})">']
    if frac > 0:
        g.append(f'<rect x="{x-w/2}" y="{lvl}" width="{w}" height="{yb-lvl}" fill="url(#sparkFill)"/>')
        g.append(f'<path d="M{x-w/2},{lvl} Q{x-w/4},{lvl-4} {x},{lvl} T{x+w/2},{lvl}" fill="#FFF0B8" stroke="#FFF7D6" stroke-width="2"/>')
        rnd = random.Random(seed)
        for _ in range(int(10 * frac * w / 60) + 2):
            sx = rnd.uniform(x - w / 2 + 8, x + w / 2 - 8)
            sy = rnd.uniform(lvl + 6, yb - 8)
            g.append(spark(round(sx, 1), round(sy, 1), rnd.uniform(3, 5.5), "#FFFBEA", rot=rnd.uniform(0, 45)))
    g.append("</g>")
    o += g
    # outline + glass shine
    o.append(f'<path d="{body}" fill="none" stroke="{INK}" stroke-width="3"/>')
    o.append(f'<path d="M{x-w/2+8},{top+30} V{yb-18}" stroke="#fff" stroke-width="4" stroke-linecap="round" opacity="0.7"/>')
    # neck + cloth lid with string
    o.append(f'<path d="{rr(x-w/2+8,top+6,w-16,14,4)}" fill="#F6EEDF" stroke="{INK}" stroke-width="3"/>')
    o.append(f'<path d="M{x-w/2+4},{top+8} Q{x},{top-10} {x+w/2-4},{top+8} L{x+w/2-1},{top+16} Q{x},{top+8} {x-w/2+1},{top+16} Z" '
             f'fill="#D97757" stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>')
    for k in range(3):
        o.append(f'<circle cx="{x-w/4+k*w/4}" cy="{top+6}" r="2" fill="#FFF1E6"/>')
    if not tag:
        return "".join(o)
    # paper tag on string
    tx, ty = x + w / 2 + 6, top + 26
    o.append(f'<path d="M{x+w/2-6},{top+14} Q{tx+4},{top+16} {tx+10},{ty}" stroke="{INK}" stroke-width="1.6" fill="none"/>')
    tw = max(len(label), len(sub)) * 5.9 + 20
    o.append(f'<g transform="rotate(8 {tx} {ty})"><path d="M{tx},{ty+8} L{tx+8},{ty} H{tx+tw} V{ty+38} H{tx+8} L{tx},{ty+30} Z" fill="#FFF8EC" stroke="{INK}" stroke-width="2.4" stroke-linejoin="round"/>'
             f'<circle cx="{tx+9}" cy="{ty+19}" r="2.5" fill="{INK}"/>'
             f'<text x="{tx+16}" y="{ty+16}" font-family="Helvetica" font-weight="bold" font-size="12" fill="{INK}">{label}</text>'
             f'<text x="{tx+16}" y="{ty+31}" font-family="Helvetica" font-size="10.5" fill="#7A4A3A">{sub}</text></g>')
    return "".join(o)


def moon(x, y, r, phase, label, sub, night=False):
    """phase: 1 = full (fresh week), 0 = new moon (weekly limit hit)."""
    cid = C.uid("moon")
    o = [f'<clipPath id="{cid}"><circle cx="{x}" cy="{y}" r="{r}"/></clipPath>']
    o.append(f'<circle cx="{x}" cy="{y}" r="{r*1.7}" fill="#FFF1C2" opacity="{0.35*phase+0.05}" filter="url(#blur8)"/>')
    o.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#FFF0C4"/>')
    o.append(f'<g clip-path="url(#{cid})">'
             f'<circle cx="{x-r*0.3}" cy="{y-r*0.2}" r="{r*0.18}" fill="#F1DA9C"/>'
             f'<circle cx="{x+r*0.35}" cy="{y+r*0.3}" r="{r*0.12}" fill="#F1DA9C"/>'
             f'<circle cx="{x+r*0.1}" cy="{y-r*0.5}" r="{r*0.08}" fill="#F1DA9C"/>')
    if phase < 1:
        off = r * 2 * phase
        o.append(f'<circle cx="{x-off}" cy="{y}" r="{r*1.02}" fill="{"#2A3150" if night else "#7C6A86"}" opacity="0.88"/>')
    o.append("</g>")
    o.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="none" stroke="{INK}" stroke-width="2.6"/>')
    # tag
    tcol = "#FFF8EC" if not night else "#FFF8EC"
    o.append(f'<text x="{x+r+10}" y="{y-2}" font-family="Helvetica" font-weight="bold" font-size="12" fill="{"#FFF3DE" if night else INK}">{label}</text>')
    o.append(f'<text x="{x+r+10}" y="{y+13}" font-family="Helvetica" font-size="11" fill="{"#D9D2EA" if night else "#6E4A3E"}">{sub}</text>')
    return "".join(o)


def confetti(x0, y0, w, h, n, seed):
    rnd = random.Random(seed)
    cols = ["#FFC94D", "#F27D9B", "#7FC8F8", "#9BE38B", "#FFFFFF", "#D97757", "#B793F5"]
    o = []
    for _ in range(n):
        x, y = rnd.uniform(x0, x0 + w), rnd.uniform(y0, y0 + h)
        c = rnd.choice(cols)
        a = rnd.uniform(0, 180)
        if rnd.random() < 0.6:
            o.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{rnd.uniform(5,9):.1f}" height="{rnd.uniform(3,4):.1f}" rx="1" fill="{c}" transform="rotate({a:.0f} {x:.1f} {y:.1f})"/>')
        else:
            o.append(f'<path d="M{x:.1f},{y:.1f} q4,-6 8,0 t8,0" stroke="{c}" stroke-width="2.6" fill="none" stroke-linecap="round" transform="rotate({a:.0f} {x:.1f} {y:.1f})"/>')
    return "".join(o)


def panel(px, py, pw, ph, bg, title, desc, inner, night=False):
    cid = C.uid("panel")
    tcol = "#FFF3DE" if night else INK
    return (f'<clipPath id="{cid}"><path d="{rr(px,py,pw,ph,22)}"/></clipPath>'
            f'<path d="{rr(px+3,py+8,pw,ph,22)}" fill="#2B1810" opacity="0.18" filter="url(#blur8)"/>'
            f'<g clip-path="url(#{cid})"><rect x="{px}" y="{py}" width="{pw}" height="{ph}" fill="{bg}"/>{inner}</g>'
            f'<path d="{rr(px,py,pw,ph,22)}" fill="none" stroke="{INK}" stroke-width="3"/>'
            f'<text x="{px+22}" y="{py+ph-56}" font-family="Helvetica" font-weight="bold" font-size="19" fill="{tcol}">{title}</text>'
            f'<text x="{px+22}" y="{py+ph-32}" font-family="Helvetica" font-size="13.5" fill="{tcol}" opacity="0.85">{desc[0]}</text>'
            f'<text x="{px+22}" y="{py+ph-14}" font-family="Helvetica" font-size="13.5" fill="{tcol}" opacity="0.85">{desc[1]}</text>')


def build():
    W, H = 1600, 1150
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
         "<defs>" + defs_common() +
         '<linearGradient id="sparkFill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFD978"/><stop offset="1" stop-color="#F08A4B"/></linearGradient>'
         '<linearGradient id="dayBg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#CFE3F5"/><stop offset="1" stop-color="#FBEFE2"/></linearGradient>'
         '<linearGradient id="duskBg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F4B183"/><stop offset="1" stop-color="#FBE3CF"/></linearGradient>'
         '<linearGradient id="nightBg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1D2440"/><stop offset="1" stop-color="#3B3F66"/></linearGradient>'
         '<linearGradient id="partyBg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFD9E4"/><stop offset="1" stop-color="#FFF1CF"/></linearGradient>'
         "</defs>"]
    o.append(f'<rect width="{W}" height="{H}" fill="#F3EEE8"/>')
    o.append(f'<text x="60" y="76" font-family="Helvetica" font-weight="bold" font-size="38" fill="{INK}">Usage limits, told as a little world</text>')
    o.append(f'<text x="62" y="108" font-family="Helvetica" font-size="17" fill="{INK}" opacity="0.75">'
             f'5-hour window = the Spark Jar Claudette carries (each turn spends sparks). Weekly window = the Moon (full on reset day, wanes all week).</text>')

    pw, ph, py = 350, 640, 140
    xs = [60, 440, 820, 1200]
    ground = py + 490

    # 1 fresh
    inner = (f'<path d="M{xs[0]},{ground} H{xs[0]+pw}" stroke="{INK}" stroke-width="3"/>'
             f'<rect x="{xs[0]}" y="{ground}" width="{pw}" height="200" fill="#EBD8C3"/>'
             + moon(xs[0] + 70, py + 80, 30, 1.0, "Week  18%", "new moon Mon 09:00")
             + character("cel", "neutral", xs[0] + 122, ground, 148, extras=False)
             + jar(xs[0] + 238, ground, 66, 100, 0.9, "5h  12%", "in 3h 41m", seed=2))
    o.append(panel(xs[0], py, pw, ph, "url(#dayBg)", "1 · Fresh", ("Jar brimming, moon full. Spark on her head", "is bright; she idles happily."), inner))

    # 2 running low
    inner = (f'<rect x="{xs[1]}" y="{ground}" width="{pw}" height="200" fill="#E7C7A8"/>'
             f'<path d="M{xs[1]},{ground} H{xs[1]+pw}" stroke="{INK}" stroke-width="3"/>'
             + moon(xs[1] + 70, py + 80, 30, 0.45, "Week  71%", "new moon Mon 09:00")
             + character("cel", "worried", xs[1] + 117, ground, 148, extras=False)
             # sweat drop
             + f'<path d="M{xs[1]+195},{ground-172} q7,11 0,15 q-7,-4 0,-15 Z" fill="#8FD0F5" stroke="{INK}" stroke-width="2"/>'
             + jar(xs[1] + 238, ground, 66, 100, 0.18, "5h  88%", "in 47m", seed=3)
             # flicker marks
             + f'<path d="M{xs[1]+214},{ground-118} l-6,-8 M{xs[1]+238},{ground-124} v-10 M{xs[1]+262},{ground-118} l6,-8" stroke="{INK}" stroke-width="2.4" stroke-linecap="round"/>')
    o.append(panel(xs[1], py, pw, ph, "url(#duskBg)", "2 · Running low (80%+)", ("Sparks flicker, she peeks into the jar and", "works a bit slower. Tag shows refill time."), inner))

    # 3 in limit
    stars = "".join(star4(xs[2] + x, py + y, r, "#FFF3C4") for x, y, r in ((40, 160, 4), (300, 60, 5), (250, 180, 3), (120, 40, 3), (320, 230, 3)))
    inner = (stars
             + f'<rect x="{xs[2]}" y="{ground}" width="{pw}" height="200" fill="#2A2C4A"/>'
             + f'<path d="M{xs[2]},{ground} H{xs[2]+pw}" stroke="#0E0F1F" stroke-width="3"/>'
             + moon(xs[2] + 70, py + 80, 30, 0.45, "Week  71%", "fine: only 5h is out", night=True)
             + jar(xs[2] + 238, ground, 66, 100, 0.0, "5h  100%", "at 16:40", dim=True, seed=4)
             # blanket over the napper
             + character("cel", "nap", xs[2] + 145, ground, 120, extras=False)
             + f'<path d="M{xs[2]+68},{ground-4} Q{xs[2]+88},{ground-56} {xs[2]+145},{ground-52} Q{xs[2]+202},{ground-56} {xs[2]+222},{ground-4} Z" fill="#7B8FD1" stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>'
             + "".join(f'<circle cx="{xs[2]+95+k*25}" cy="{ground-30+(k%2)*12}" r="4" fill="#C9D4F5"/>' for k in range(5))
             # hanging sign
             + f'<rect x="{xs[2]+24}" y="{ground-150}" width="7" height="150" rx="3" fill="#A7754F" stroke="{INK}" stroke-width="2.4"/>'
             + f'<g transform="rotate(-4 {xs[2]+73} {ground-178})"><path d="{rr(xs[2]+14,ground-200,118,44,8)}" fill="#FFF3DE" stroke="{INK}" stroke-width="3"/>'
             + f'<text x="{xs[2]+73}" y="{ground-182}" text-anchor="middle" font-family="Helvetica" font-weight="bold" font-size="13" fill="{INK}">gone napping</text>'
             + f'<text x="{xs[2]+73}" y="{ground-165}" text-anchor="middle" font-family="Helvetica" font-size="12" fill="#B0503A">back at 16:40</text></g>'
             + f'<text x="{xs[2]+178}" y="{ground-118}" font-family="Helvetica" font-weight="bold" font-size="22" fill="#C9D4F5">z</text>'
             + f'<text x="{xs[2]+196}" y="{ground-142}" font-family="Helvetica" font-weight="bold" font-size="28" fill="#C9D4F5">z</text>')
    o.append(panel(xs[2], py, pw, ph, "url(#nightBg)", "3 · In limit", ("Scene goes to night. She naps under a", "blanket with a 'back at' sign. Unmissable."), inner, night=True))

    # 4 lifted
    inner = (confetti(xs[3], py, pw, 380, 70, 9)
             + f'<rect x="{xs[3]}" y="{ground}" width="{pw}" height="200" fill="#F4D7B8"/>'
             + f'<path d="M{xs[3]},{ground} H{xs[3]+pw}" stroke="{INK}" stroke-width="3"/>'
             + moon(xs[3] + 70, py + 80, 30, 1.0, "Week  0%", "fresh week!")
             + jar(xs[3] + 238, ground, 66, 100, 1.0, "5h  0%", "full again", burst=True, seed=5)
             + "".join(spark(xs[3] + 238 + dx, ground - 120 + dy, r, "#FFE07A", stroke=INK, sw=1.5, rot=dx)
                       for dx, dy, r in ((-22, -20, 7), (6, -44, 9), (30, -14, 6)))
             + character("cel", "cheer", xs[3] + 117, ground, 148, extras=True))
    o.append(panel(xs[3], py, pw, ph, "url(#partyBg)", "4 · Limits lifted", ("Jar bursts open, sparks fly back in, confetti,", "big jump. Plays once, then back to work."), inner))

    # bottom: glance strip at real size
    y0 = 820
    o.append(f'<text x="60" y="{y0}" font-family="Helvetica" font-weight="bold" font-size="15" fill="{INK}" opacity="0.7">AT A GLANCE · REAL SIZE (96 pt character, jar rides on her back; menubar shows moon + jar glyph)</text>')
    sx0, sy0, sw_, sh_ = 60, y0 + 20, 1480, 280
    cid = C.uid("strip")
    o.append(f'<clipPath id="{cid}"><path d="{rr(sx0,sy0,sw_,sh_,18)}"/></clipPath>')
    o.append(f'<linearGradient id="w2" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#233159"/><stop offset="0.55" stop-color="#6C4E86"/><stop offset="1" stop-color="#E59A72"/></linearGradient>')
    o.append(f'<g clip-path="url(#{cid})"><rect x="{sx0}" y="{sy0}" width="{sw_}" height="{sh_}" fill="url(#w2)"/>'
             f'<rect x="{sx0}" y="{sy0}" width="{sw_}" height="26" fill="#fff" opacity="0.28"/>')
    # menubar glyph states
    gx = sx0 + sw_ - 380
    for i, (ph_, fr) in enumerate(((1, 0.9), (0.45, 0.18), (0.45, 0), (1, 1))):
        cx = gx + i * 90
        o.append(moon(cx, sy0 + 13, 7, ph_, "", ""))
        # tiny jar glyph (simplified)
        o.append(f'<path d="{rr(cx+14,sy0+5,11,15,3)}" fill="#fff" opacity="0.35" stroke="#fff" stroke-width="1.4"/>')
        if fr:
            o.append(f'<rect x="{cx+15}" y="{sy0+19-13*fr:.1f}" width="9" height="{13*fr:.1f}" fill="#FFD27A"/>')
    o.append("</g>")
    labels = ("fresh", "running low", "in limit", "lifted")
    poses = ("neutral", "worried", "nap", "cheer")
    fr_ = (0.9, 0.18, 0.0, 1.0)
    for i in range(4):
        cx = sx0 + 170 + i * 300
        gy = sy0 + sh_ - 40
        if i == 2:
            o.append(f'<path d="{rr(cx-110,gy-150,220,170,14)}" fill="#141833" opacity="0.55"/>')
        o.append(character("cel", poses[i], cx, gy, 96, extras=False))
        if i == 2:
            o.append(f'<path d="M{cx-46},{gy-2} Q{cx-30},{gy-40} {cx},{gy-38} Q{cx+34},{gy-40} {cx+50},{gy-2} Z" fill="#7B8FD1" stroke="{INK}" stroke-width="2.4"/>'
                     f'<text x="{cx+52}" y="{gy-70}" font-family="Helvetica" font-weight="bold" font-size="18" fill="#C9D4F5">z</text>')
        # mini jar riding on her back (upper right)
        o.append(jar(cx + 62, gy - 70, 26, 38, fr_[i], "", "", dim=fr_[i] == 0, burst=(i == 3), seed=10 + i, tag=False))
        if i == 3:
            o.append(confetti(cx - 100, gy - 160, 200, 120, 26, 4))
        o.append(f'<text x="{cx}" y="{gy+28}" text-anchor="middle" font-family="Helvetica" font-weight="bold" font-size="13" fill="#fff">{labels[i]}</text>')
    o.append("</svg>")
    return "\n".join(o)


open(f"{OUT}/limits.svg", "w").write(build())
print("ok")
