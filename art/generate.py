#!/usr/bin/env python3
"""Export Claudette's rig parts as PNGs + manifest.json + a review sheet.

Run from anywhere: python3 art/generate.py
Writes art/build/<name>.svg (scratch), art/export/<name>.png, manifest.json, sheet.png.
Positions/parents/z mirror PuppetNode.build() (points, y up, origin = centre of her feet).
"""
import base64, json, math, os, struct, subprocess, sys

SCALE = 2  # pixels per point

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "src"))
import parts as P  # noqa: E402

BUILD = os.path.join(HERE, "build")
EXPORT = os.path.join(HERE, "export")
RSVG = "/usr/local/bin/rsvg-convert"
MARGIN = 1.0  # extra transparent points around every drawn extent, for antialiasing

# Rig constants from PuppetNode.build().
LEG_Y = P.LEG_LEN  # bodyPivot and hips sit at the top of the legs
BUILTIN = {"root": (None, (0, 0), 0), "bodyPivot": ("root", (0, LEG_Y), 0), "face": ("bodyPivot", (0, 0), 4)}

# name: (draw, parent, position (y up), z)
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
}


def canvas(box):
    """Snap the drawn extent outward to whole points so pixel sizes are exact."""
    x0, y0, x1, y1 = box
    x0, y0 = math.floor(x0 - MARGIN), math.floor(y0 - MARGIN)
    x1, y1 = math.ceil(x1 + MARGIN), math.ceil(y1 + MARGIN)
    return x0, y0, x1 - x0, y1 - y0


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


def export():
    os.makedirs(BUILD, exist_ok=True)
    os.makedirs(EXPORT, exist_ok=True)
    assets = {}
    for name, (draw, parent, pos, z) in PARTS.items():
        frag, box = draw()
        x0, y0, w, h = canvas(box)
        svg = os.path.join(BUILD, f"{name}.svg")
        write(svg, svg_doc(frag, x0, y0, w, h))
        rasterise(svg, os.path.join(EXPORT, f"{name}.png"), w * SCALE, h * SCALE)
        # Pivot is (0,0) in the y-down drawing space; SpriteKit anchor is from bottom-left, y up.
        anchor = [round(-x0 / w, 6), round((y0 + h) / h, 6)]
        assert all(0 <= a <= 1 for a in anchor), (name, anchor)
        assets[name] = dict(file=f"{name}.png", size=[w, h], anchor=anchor,
                            position=list(pos), z=z, parent=parent)
    manifest = {"version": 1, "scale": SCALE, "assets": assets}
    write(os.path.join(EXPORT, "manifest.json"), json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return manifest


# ---------------------------------------------------------------- review sheet
def data_uri(path):
    with open(path, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()


def world(name, assets):
    """World position and z of a node (translation only; no rotation/scale at rest)."""
    a = assets.get(name)
    if a:
        parent, pos, z = a["parent"], a["position"], a["z"]
    else:
        parent, pos, z = BUILTIN[name]
    if parent is None:
        return pos[0], pos[1], z
    px, py, pz = world(parent, assets)
    return px + pos[0], py + pos[1], pz + z


def image(a, uri, left, top, k=1):
    w, h = a["size"]
    return f'<image x="{left}" y="{top}" width="{w*k}" height="{h*k}" href="{uri}"/>'


def figure(assets, uris, cx, ground, k):
    """Place every sprite by the manifest: k = display zoom of the figure."""
    placed = []
    for name, a in assets.items():
        x, y, z = world(name, assets)
        w, h = a["size"]
        left = cx + (x - a["anchor"][0] * w) * k
        top = ground - (y + (1 - a["anchor"][1]) * h) * k
        placed.append((z, name, image(a, uris[name], left, top, k)))
    return "".join(s for _, _, s in sorted(placed))


def sheet(manifest):
    assets = manifest["assets"]
    uris = {n: data_uri(os.path.join(EXPORT, a["file"])) for n, a in assets.items()}
    cell, cols, pad = 220, 4, 20
    names = list(PARTS)
    rows = math.ceil(len(names) / cols)
    W = cols * cell + 2 * pad
    fig_h = 360
    H = pad + fig_h + pad + rows * (cell // 2 + 40) + pad
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
         '<defs>'
         '<pattern id="lc" width="16" height="16" patternUnits="userSpaceOnUse">'
         '<rect width="16" height="16" fill="#F4F4F6"/><rect width="8" height="8" fill="#DCDDE3"/>'
         '<rect x="8" y="8" width="8" height="8" fill="#DCDDE3"/></pattern>'
         '<pattern id="dc" width="16" height="16" patternUnits="userSpaceOnUse">'
         '<rect width="16" height="16" fill="#23232B"/><rect width="8" height="8" fill="#34343E"/>'
         '<rect x="8" y="8" width="8" height="8" fill="#34343E"/></pattern></defs>',
         f'<rect width="{W}" height="{H}" fill="#EEF0F7"/>']
    # Assembled figure, 1.6x zoom, on light and dark halves.
    half = (W - 2 * pad) / 2
    o.append(f'<rect x="{pad}" y="{pad}" width="{half}" height="{fig_h}" fill="#EEF0F7" stroke="#C9CCD8"/>')
    o.append(f'<rect x="{pad+half}" y="{pad}" width="{half}" height="{fig_h}" fill="#2A2F45"/>')
    for i in (0, 1):
        o.append(figure(assets, uris, pad + half * i + half / 2, pad + fig_h - 40, 1.6))
    y = pad + fig_h + pad
    ch = cell // 2
    for i, name in enumerate(names):
        cx0 = pad + (i % cols) * cell
        cy0 = y + (i // cols) * (ch + 40)
        a = assets[name]
        w, h = a["size"]
        k = min(1.0, (ch / 2 - 8) / w, (ch - 8) / h)
        for j, pat in enumerate(("lc", "dc")):
            bx = cx0 + j * ch
            o.append(f'<rect x="{bx}" y="{cy0}" width="{ch}" height="{ch}" fill="url(#{pat})"/>')
            o.append(image(a, uris[name], bx + (ch - w * k) / 2, cy0 + (ch - h * k) / 2, k))
            # Pivot marker.
            px = bx + (ch - w * k) / 2 + a["anchor"][0] * w * k
            py = cy0 + (ch - h * k) / 2 + (1 - a["anchor"][1]) * h * k
            o.append(f'<circle cx="{px:.2f}" cy="{py:.2f}" r="2.5" fill="#2EC4FF" stroke="#fff" stroke-width="1"/>')
        o.append(f'<text x="{cx0+4}" y="{cy0+ch+16}" font-family="Helvetica" font-size="13" fill="#22202E">'
                 f'{name}  {w}x{h} pt  z{a["z"]}</text>')
    o.append("</svg>\n")
    svg = os.path.join(BUILD, "sheet.svg")
    write(svg, "".join(o))
    rasterise(svg, os.path.join(EXPORT, "sheet.png"), W * SCALE, H * SCALE)


if __name__ == "__main__":
    if not os.access(RSVG, os.X_OK):
        raise SystemExit(f"missing {RSVG}")
    m = export()
    sheet(m)
    print(f"wrote {len(m['assets'])} parts + manifest.json + sheet.png to {EXPORT}")
