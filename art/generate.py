#!/usr/bin/env python3
"""Export Claudette's rig parts as PNGs + manifest.json + a review sheet.

Run from anywhere: python3 art/generate.py
Writes art/build/<name>.svg (scratch), art/export/<name>.png, manifest.json, sheet.png.
Positions/parents/z mirror PuppetNode.build() (points, y up, origin = centre of her feet).
"""
import base64, json, math, os, struct, subprocess, sys

SCALE = 2  # pixels per point

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True  # keep art/src free of __pycache__
sys.path.insert(0, os.path.join(HERE, "src"))
import parts as P  # noqa: E402

BUILD = os.path.join(HERE, "build")
EXPORT = os.path.join(HERE, "export")
RSVG = "/usr/local/bin/rsvg-convert"
MARGIN = 1.0  # extra transparent points around every drawn extent, for antialiasing

# Rig constants from PuppetNode.build().
LEG_Y = P.LEG_LEN  # bodyPivot and hips sit at the top of the legs
BUILTIN = {"root": (None, (0, 0), 0), "bodyPivot": ("root", (0, LEG_Y), 0), "face": ("bodyPivot", (0, 0), 4)}

# name: (draw, parent, position (y up), z). parent None = top-level node placed by code.
PARTS = {
    "shadow": (lambda: P.shadow(150), "root", (0, -2), -10),
    **{f"leg_{i}": (P.leg, "root", (x, LEG_Y), -1) for i, x in enumerate((-51, -22, 22, 51))},
    "arm_L": (lambda: P.arm(-1), "bodyPivot", (-70, 52), 0),
    "arm_R": (lambda: P.arm(1), "bodyPivot", (70, 52), 0),
    "body": (P.body, "bodyPivot", (0, 0), 1),
    "blush_L": (P.blush, "face", (-52, 32), 0),
    "blush_R": (P.blush, "face", (52, 32), 0),
    "eye_L": (P.eye, "face", (-30, 48), 1),
    "eye_R": (P.eye, "face", (30, 48), 1),
    "mouth": (P.mouth, "face", (0, 35), 1),
    "spark": (P.spark, "root", (0, LEG_Y + P.BODY_H + 30), 5),
    "bag": (P.bag, "bodyPivot", (-82, 96), -1),
    "bag_fill": (P.bag_fill, "bag", (0, 2), 0),
    "jar_glass": (P.jar_glass, None, None, 1),
    "jar_fill": (P.jar_fill, "jar_glass", (0, 2), 0),
    "jar_lid": (P.jar_lid, "jar_glass", (0, 34), 2),
    "moon_dark": (P.moon_dark, None, None, 0),
    "moon_lit": (P.moon_lit, None, None, 1),
}
# Props whose anchor is [0.5, 0]: canvas bottom is the pivot, no margin below.
FLUSH_BOTTOM = {"bag", "bag_fill", "jar_glass", "jar_fill", "jar_lid"}

# Texture variants "<base>.<variant>": same canvas and anchor as the base (the union of all).
VARIANTS = {
    **{f"eye_{s}.{v}": (f"eye_{s}", f) for s in "LR" for v, f in (
        ("happy", P.eye_happy), ("sleep", P.eye_sleep), ("focus", P.eye_focus), ("half", P.eye_half))},
    "mouth.blep": ("mouth", P.mouth_blep),
    "mouth.o": ("mouth", P.mouth_o),
    "mouth.wobble": ("mouth", P.mouth_wobble),
    "body.sleep_curl": ("body", P.body_sleep_curl),
    "body.sit": ("body", P.body_sit),
    **{f"leg_{i}.tuck": (f"leg_{i}", P.leg_tuck) for i in range(4)},
}


def canvas(box, flush_bottom=False):
    """Snap the drawn extent outward to whole points so pixel sizes are exact."""
    x0, y0, x1, y1 = box
    # Symmetric about the pivot in x where the art is, so anchors stay exactly 0.5.
    x0, y0, x1 = math.floor(x0 - MARGIN), math.floor(y0 - MARGIN), math.ceil(x1 + MARGIN)
    if flush_bottom:
        assert y1 <= 0, box
        y1 = 0
    else:
        y1 = math.ceil(y1 + MARGIN)
    return x0, y0, x1 - x0, y1 - y0


def union(a, b):
    return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))


def svg_doc(frag, x0, y0, w, h):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="{x0} {y0} {w} {h}">{frag}</svg>\n')


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"not a PNG: {path}")
    return struct.unpack(">II", head[16:24])


def rasterise(svg_path, png_path, w_px, h_px):
    r = subprocess.run([RSVG, "-w", str(w_px), "-h", str(h_px), "-o", png_path, svg_path],
                       capture_output=True, text=True)
    if r.returncode != 0 or r.stderr.strip():
        raise SystemExit(f"rsvg-convert failed on {svg_path}: {r.stderr.strip() or r.returncode}")
    if png_size(png_path) != (w_px, h_px):
        raise SystemExit(f"{png_path}: got {png_size(png_path)}, want {(w_px, h_px)}")


def write(path, text):
    with open(path, "w") as f:
        f.write(text)


def file_name(name):
    return name.replace(".", "_") + ".png"


def export():
    os.makedirs(BUILD, exist_ok=True)
    os.makedirs(EXPORT, exist_ok=True)
    drawn = {n: d() for n, (d, *_rest) in PARTS.items()}
    drawn.update({n: d() for n, (_b, d) in VARIANTS.items()})
    boxes = {n: drawn[n][1] for n in PARTS}
    for _n, (base, _d) in VARIANTS.items():
        boxes[base] = union(boxes[base], drawn[_n][1])
    assets = {}
    for name in [*PARTS, *VARIANTS]:
        base = VARIANTS[name][0] if name in VARIANTS else name
        x0, y0, w, h = canvas(boxes[base], base in FLUSH_BOTTOM)
        svg = os.path.join(BUILD, f"{name}.svg")
        write(svg, svg_doc(drawn[name][0], x0, y0, w, h))
        rasterise(svg, os.path.join(EXPORT, file_name(name)), w * SCALE, h * SCALE)
        # Pivot is (0,0) in the y-down drawing space; SpriteKit anchor is from bottom-left, y up.
        anchor = [round(-x0 / w, 6), round((y0 + h) / h, 6)]
        assert all(0 <= a <= 1 for a in anchor), (name, anchor)
        a = dict(file=file_name(name), size=[w, h], anchor=anchor)
        if name in VARIANTS:
            a["variantOf"] = base
        else:
            _d, parent, pos, z = PARTS[name]
            a["z"] = z
            if parent:
                a.update(parent=parent, position=list(pos))
        assets[name] = a
    for name, (base, _d) in VARIANTS.items():
        assert (assets[name]["size"], assets[name]["anchor"]) == (assets[base]["size"], assets[base]["anchor"]), name
    manifest = {"version": 1, "scale": SCALE, "assets": assets}
    write(os.path.join(EXPORT, "manifest.json"), json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return manifest


# ---------------------------------------------------------------- review sheet
def data_uri(path):
    with open(path, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()


def world(name, assets):
    """World position, z and tree depth of a node (translation only, at rest)."""
    a = assets.get(name)
    if a:
        parent, pos, z = a.get("parent"), a.get("position", (0, 0)), a.get("z", 0)
    else:
        parent, pos, z = BUILTIN[name]
    if parent is None:
        return pos[0], pos[1], z, 0
    px, py, pz, depth = world(parent, assets)
    return px + pos[0], py + pos[1], pz + z, depth + 1


def image(a, uri, left, top, k=1, sy=1):
    w, h = a["size"]
    return (f'<image x="{left}" y="{top}" width="{w*k}" height="{h*k*sy}" '
            f'preserveAspectRatio="none" href="{uri}"/>')


def figure(assets, uris, names, cx, ground, k, swap=None):
    """Place sprites by the manifest (k = zoom). swap: base name -> variant texture."""
    swap = swap or {}
    placed = []
    for name in names:
        a = assets[name]
        x, y, z, depth = world(name, assets)
        w, h = a["size"]
        left = cx + (x - a["anchor"][0] * w) * k
        sy = LEVEL.get(name, 1)  # fills are yScaled about their bottom anchor
        top = ground - (y + (1 - a["anchor"][1]) * h * sy) * k
        # SpriteKit: higher global z on top; on ties a child draws after its parent.
        placed.append((z, depth, name, image(a, uris[swap.get(name, name)], left, top, k, sy)))
    return "".join(s for *_k, s in sorted(placed))


LEVEL = {"bag_fill": 0.55, "jar_fill": 0.6}  # sheet preview of the fill levels
CHARACTER = [n for n in PARTS if n not in ("jar_glass", "jar_fill", "jar_lid", "moon_dark", "moon_lit")]
POSES = [  # (hidden parts, swaps)
    ({"mouth", "bag", "bag_fill"}, {}),
    (set(), {"eye_L": "eye_L.happy", "eye_R": "eye_R.happy"}),
    ({"blush_L", "blush_R"}, {"eye_L": "eye_L.focus", "eye_R": "eye_R.focus", "mouth": "mouth.blep"}),
    ({"spark"}, {"body": "body.sleep_curl", "eye_L": "eye_L.sleep", "eye_R": "eye_R.sleep",
                 **{f"leg_{i}": f"leg_{i}.tuck" for i in range(4)}, "mouth": "mouth.o"}),
    ({"mouth"}, {"body": "body.sit", "eye_L": "eye_L.half", "eye_R": "eye_R.half",
                 **{f"leg_{i}": f"leg_{i}.tuck" for i in range(4)}}),
    ({"spark"}, {"eye_L": "eye_L.half", "eye_R": "eye_R.half", "mouth": "mouth.wobble"}),
]


def sheet(manifest):
    assets = manifest["assets"]
    uris = {n: data_uri(os.path.join(EXPORT, a["file"])) for n, a in assets.items()}
    cell, cols, pad = 220, 4, 20
    names = list(assets)
    rows = math.ceil(len(names) / cols)
    W = cols * cell + 2 * pad
    fig_h, pose_h = 360, 200
    ch = cell // 2
    H = pad + fig_h + pad + pose_h + pad + rows * (ch + 40) + pad
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
         '<defs>'
         '<pattern id="lc" width="16" height="16" patternUnits="userSpaceOnUse">'
         '<rect width="16" height="16" fill="#F4F4F6"/><rect width="8" height="8" fill="#DCDDE3"/>'
         '<rect x="8" y="8" width="8" height="8" fill="#DCDDE3"/></pattern>'
         '<pattern id="dc" width="16" height="16" patternUnits="userSpaceOnUse">'
         '<rect width="16" height="16" fill="#23232B"/><rect width="8" height="8" fill="#34343E"/>'
         '<rect x="8" y="8" width="8" height="8" fill="#34343E"/></pattern></defs>',
         f'<rect width="{W}" height="{H}" fill="#EEF0F7"/>']
    # Rest pose (mouth hidden, as in code) at 1.6x on light and dark, with the props beside it.
    half = (W - 2 * pad) / 2
    o.append(f'<rect x="{pad}" y="{pad}" width="{half}" height="{fig_h}" fill="#EEF0F7" stroke="#C9CCD8"/>')
    o.append(f'<rect x="{pad+half}" y="{pad}" width="{half}" height="{fig_h}" fill="#2A2F45"/>')
    rest = [n for n in CHARACTER if n != "mouth"]
    props = ["jar_glass", "jar_fill", "jar_lid"]
    for i in (0, 1):
        x0 = pad + half * i
        o.append(figure(assets, uris, rest, x0 + half * 0.42, pad + fig_h - 40, 1.6))
        o.append(figure(assets, uris, props, x0 + half * 0.9, pad + fig_h - 40, 1.6))
        o.append(figure(assets, uris, ["moon_dark"], x0 + half * 0.88, pad + 70, 1.6))
        o.append(figure(assets, uris, ["moon_lit"], x0 + half * 0.88 - 70, pad + 70, 1.6))
    # Pose strip at 0.9x: rest+bag, happy, focus, deep sleep, sit, worried.
    y = pad + fig_h + pad
    o.append(f'<rect x="{pad}" y="{y}" width="{W-2*pad}" height="{pose_h}" fill="#E3E6F0"/>')
    step = (W - 2 * pad) / len(POSES)
    for i, (hide, swap) in enumerate(POSES):
        o.append(figure(assets, uris, [n for n in CHARACTER if n not in hide],
                        pad + step * (i + 0.5), y + pose_h - 25, 0.9, swap))
    y += pose_h + pad
    for i, name in enumerate(names):
        cx0 = pad + (i % cols) * cell
        cy0 = y + (i // cols) * (ch + 40)
        a = assets[name]
        w, h = a["size"]
        k = min(1.0, (ch - 8) / w, (ch - 8) / h)
        for j, pat in enumerate(("lc", "dc")):
            bx = cx0 + j * ch
            o.append(f'<rect x="{bx}" y="{cy0}" width="{ch}" height="{ch}" fill="url(#{pat})"/>')
            o.append(image(a, uris[name], bx + (ch - w * k) / 2, cy0 + (ch - h * k) / 2, k))
            px = bx + (ch - w * k) / 2 + a["anchor"][0] * w * k
            py = cy0 + (ch - h * k) / 2 + (1 - a["anchor"][1]) * h * k
            o.append(f'<circle cx="{px:.2f}" cy="{py:.2f}" r="2.5" fill="#2EC4FF" stroke="#fff" stroke-width="1"/>')
        o.append(f'<text x="{cx0+4}" y="{cy0+ch+16}" font-family="Helvetica" font-size="13" fill="#22202E">'
                 f'{name}  {w}x{h}</text>')
    o.append("</svg>\n")
    svg = os.path.join(BUILD, "sheet.svg")
    write(svg, "".join(o))
    rasterise(svg, os.path.join(EXPORT, "sheet.png"), W * SCALE, H * SCALE)


if __name__ == "__main__":
    if not os.access(RSVG, os.X_OK):
        raise SystemExit(f"missing {RSVG}")
    m = export()
    sheet(m)
    print(f"wrote {len(m['assets'])} assets + manifest.json + sheet.png to {EXPORT}")
