#!/usr/bin/env python3
"""Export Claudette's rig parts as PNGs + manifest.json + a review sheet.

Run from anywhere: python3 art/generate.py
Writes art/build/<name>.svg (scratch), art/export/<name>.png, manifest.json, sheet.png.
Positions/parents/z mirror PuppetNode.build() (points, y up, origin = centre of her feet).
"""
import base64, json, math, os, shutil, struct, subprocess, sys

SCALE = 2  # pixels per point

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True  # keep art/src free of __pycache__
sys.path.insert(0, os.path.join(HERE, "src"))
import parts as P  # noqa: E402
import props as R  # noqa: E402
import status as St  # noqa: E402
import sleep as Sl  # noqa: E402
import outfits as O  # noqa: E402

BUILD = os.path.join(HERE, "build")
EXPORT = os.path.join(HERE, "export")
# PATH first, then the usual Homebrew prefixes (Apple Silicon /opt/homebrew, Intel /usr/local).
RSVG = shutil.which("rsvg-convert") or next(
    (p for p in ("/opt/homebrew/bin/rsvg-convert", "/usr/local/bin/rsvg-convert") if os.path.exists(p)),
    None,
)
if RSVG is None:
    raise SystemExit("rsvg-convert not found (brew install librsvg)")
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
    "bag_fill": (P.bag_fill, "bag", (0, P.BAG_FILL_Y), -1),  # behind the bag, seen through its window
    "jar_glass": (P.jar_glass, None, None, 1),
    "jar_fill": (P.jar_fill, "jar_glass", (0, 2), -1),  # behind the glass so sheen stays on top
    "jar_lid": (P.jar_lid, "jar_glass", (0, 33), 2),  # 1 pt overlap seats it on the rim
    "moon_dark": (P.moon_dark, None, None, 0),
    "moon_lit": (P.moon_lit, None, None, 1),
    "menubar": (P.menubar, None, None, 0),  # template image for the status item, not a rig part
    # Sleep scenes. Blankets sit above the body (1) and below the face (4).
    "blanket": (Sl.blanket, "bodyPivot", (0, -2), 3),
    "blanket_deep": (Sl.blanket_deep, "bodyPivot", (0, -2), 3),
    "night_patch": (Sl.night_patch, "root", (0, -24), -50),
    # Per-model outfits: hats sit on the body top at z 5 (above the face); body pieces at z 2,
    # except Opus's cape, which hangs behind the body and the arms.
    "outfit_opus_head": (O.outfit_opus_head, "bodyPivot", (-26, 97), 5),
    "outfit_sonnet_head": (O.outfit_sonnet_head, "bodyPivot", (24, 97), 5),
    "outfit_haiku_head": (O.outfit_haiku_head, "bodyPivot", (20, 97), 5),
    "outfit_opus_body": (O.outfit_opus_body, "bodyPivot", (0, 0), -0.5),  # behind arms too
    "outfit_sonnet_body": (O.outfit_sonnet_body, "bodyPivot", (0, 0), 2),
    "outfit_haiku_body": (O.outfit_haiku_body, "bodyPivot", (0, 0), 2),
    # Per-project scarf (tinted at runtime); the tail is separate so code can sway it.
    "scarf": (O.scarf, "bodyPivot", O.SCARF_PIVOT, 2),
    "scarf_tail": (O.scarf_tail, "bodyPivot", O.TAIL_AT, 2.5),
}
TINTED = {"scarf", "scarf_tail"}
# Props whose anchor is [0.5, 0]: canvas bottom is the pivot, no margin below.
FLUSH_BOTTOM = {"bag", "bag_fill", "jar_glass", "jar_fill", "jar_lid", "blanket", "blanket_deep", "night_patch"}

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


def canvas(box, flush_bottom=False, flush_left=False):
    """Snap the drawn extent outward to whole points so pixel sizes are exact."""
    x0, y0, x1, y1 = box
    # Symmetric about the pivot in x where the art is, so anchors stay exactly 0.5.
    y0, x1 = math.floor(y0 - MARGIN), math.ceil(x1 + MARGIN)
    if flush_left:
        assert x0 >= 0, box
        x0 = 0
    else:
        x0 = math.floor(x0 - MARGIN)
    if flush_bottom:
        assert y1 <= 0, box
        y1 = 0
    else:
        y1 = math.ceil(y1 + MARGIN)
    return x0, y0, x1 - x0, y1 - y0


# Tool props: top-level, no parent/position/z. kind: "centre" = anchor [0.5,0.5] on the
# visual centre, "tip" = [0.5,0] (pencil tip), "plug" = [0,0.5] (cable end).
LABEL = True
PROPS = {
    "prop_read": (R.prop_read, "centre", LABEL, False),
    "prop_search": (R.prop_search, "centre", False, False),
    "prop_edit": (R.prop_edit, "centre", LABEL, False),
    "prop_edit_pencil": (R.prop_edit_pencil, "tip", False, False),
    "prop_write": (R.prop_write, "centre", LABEL, False),
    "prop_shell": (R.prop_shell, "centre", LABEL, False),
    "prop_shell_long": (R.prop_shell_long, "centre", LABEL, False),
    "prop_shell_bg": (R.prop_shell_bg, "centre", LABEL, False),
    "prop_web": (R.prop_web, "centre", LABEL, False),
    "prop_skill": (R.prop_skill, "centre", LABEL, False),
    "prop_todo": (R.prop_todo, "centre", LABEL, False),
    "prop_plan": (R.prop_plan, "centre", LABEL, False),
    "prop_other": (R.prop_other, "centre", LABEL, False),
    **{f"prop_mcp_{n}": (getattr(R, f"prop_mcp_{n}"), "centre", LABEL, True)
       for n in ("generic", "github", "playwright", "figma", "context7")},
    "prop_mcp_cable": (R.prop_mcp_cable, "plug", False, True),
}
# Status art: same contract. Bubbles anchor on the tail tip ("tip"); pills/relief carry an
# explicit label point (y up, from the anchor) for runtime text.
STATUS = {
    "status_bang": (St.status_bang, "tip", False, False),
    "status_question": (St.status_question, "tip", False, False),
    **{f"status_err_{n}": (getattr(St, f"status_err_{n}"), "centre", St.PILL_LABEL, False)
       for n in ("api", "auth", "billing", "ratelimit", "offline", "unknown")},
    "status_relief": (St.status_relief, "centre", St.RELIEF_LABEL, False),
}
SLEEP = {
    "sign_nap": (Sl.sign_nap, "centre", [Sl.sign_layout(Sl.NAP_W)[2], 0], False),
    "sign_deep": (Sl.sign_deep, "centre", [Sl.sign_layout(Sl.DEEP_W)[2], 0], False),
    "moon_new": (Sl.moon_new, "centre", False, False),
    "star_twinkle": (Sl.star_twinkle, "centre", False, False),
}
TOP = {**PROPS, **STATUS, **SLEEP}


def symmetric(box, kind):
    """Make the extent symmetric about the pivot on every centred axis."""
    x0, y0, x1, y1 = box
    if kind != "plug":
        m = max(-x0, x1)
        x0, x1 = -m, m
    if kind != "tip":
        m = max(-y0, y1)
        y0, y1 = -m, m
    return x0, y0, x1, y1


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
            if name in TINTED:
                a["tint"] = True
            if parent:
                a.update(parent=parent, position=list(pos))
        assets[name] = a
    for name, (draw, kind, label, tint) in TOP.items():
        frag, box = draw()
        x0, y0, w, h = canvas(symmetric(box, kind), kind == "tip", kind == "plug")
        svg = os.path.join(BUILD, f"{name}.svg")
        write(svg, svg_doc(frag, x0, y0, w, h))
        rasterise(svg, os.path.join(EXPORT, file_name(name)), w * SCALE, h * SCALE)
        anchor = [round(-x0 / w, 6), round((y0 + h) / h, 6)]
        assert anchor == {"centre": [0.5, 0.5], "tip": [0.5, 0.0], "plug": [0.0, 0.5]}[kind], (name, anchor)
        a = dict(file=file_name(name), size=[w, h], anchor=anchor)
        if label is True:  # caption centred under the prop
            a["label"] = [0, -(h / 2 + 5)]
        elif label:
            a["label"] = list(label)
        if tint:
            a["tint"] = True
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


def figure(assets, uris, names, cx, ground, k, swap=None, levels=None, filters=None):
    """Place sprites by the manifest (k = zoom). swap: base name -> variant texture.
    filters: name -> SVG filter id (used to simulate runtime tint)."""
    swap = swap or {}
    filters = filters or {}
    levels = LEVEL if levels is None else levels
    placed = []
    for name in names:
        a = assets[name]
        x, y, z, depth = world(name, assets)
        w, h = a["size"]
        left = cx + (x - a["anchor"][0] * w) * k
        sy = levels.get(name, 1)  # fills are yScaled about their bottom anchor
        top = ground - (y + (1 - a["anchor"][1]) * h * sy) * k
        # SpriteKit: higher global z on top; on ties a child draws after its parent.
        img = image(a, uris[swap.get(name, name)], left, top, k, sy)
        if name in filters:
            img = img.replace("<image ", f'<image filter="url(#{filters[name]})" ', 1)
        placed.append((z, depth, name, img))
    return "".join(s for *_k, s in sorted(placed))


TINTS = ["#7FC8F8", "#FFC94D", "#E5484D"]  # sample runtime tints for the cartridge check
SCARF_TINTS = ["#7FC8F8", "#9BE38B", "#F29BC0", "#B9A6E8", "#FFC94D"]  # sample project hues
LEVEL = {"bag_fill": 0.55, "jar_fill": 0.6}  # sheet preview of the fill levels
CHARACTER = [n for n in PARTS if n not in ("jar_glass", "jar_fill", "jar_lid", "moon_dark", "moon_lit", "menubar",
                                             "blanket", "blanket_deep", "night_patch", "scarf", "scarf_tail")
             and not n.startswith("outfit_")]
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
    prop_cols, prop_cell, pk = 7, (W - 2 * pad) // 7, 2.0
    groups = [list(PROPS), list(STATUS)]
    prop_rows = sum(math.ceil(len(g) / prop_cols) for g in groups)
    fills = [("bag", 0), ("bag", 0.4), ("bag", 1), ("jar_glass", 0.4), ("jar_glass", 1)]
    tints = [n for n in PROPS if PROPS[n][3]]
    tint_cols, tint_cell = 9, (W - 2 * pad) // 9
    tint_rows = math.ceil(len(tints) * len(TINTS) / tint_cols)
    props_h = (prop_rows + 1) * 2 * prop_cell + tint_rows * tint_cell
    scene_h = 340
    outfit_rows = (230, 230, 190, 230)
    H = (pad + fig_h + pad + pose_h + pad + 2 * scene_h + pad + sum(outfit_rows) + pad + props_h) + pad + rows * (ch + 40) + pad
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
    # Sleep scenes at 1.1x: weekly deep sleep (left) and 5-hour nap (right), on light then dark.
    def at(name, wx, wy, cx, ground, k):
        a = assets[name]
        w, h = a["size"]
        return image(a, uris[name], cx + wx * k - a["anchor"][0] * w * k,
                     ground - wy * k - (1 - a["anchor"][1]) * h * k, k)
    sleepy = {"eye_L": "eye_L.sleep", "eye_R": "eye_R.sleep"}
    awake_off = {"mouth", "spark", "bag", "bag_fill"}
    deep = ([n for n in CHARACTER if n not in awake_off] + ["blanket_deep", "night_patch"],
            {**sleepy, "body": "body.sleep_curl", **{f"leg_{i}": f"leg_{i}.tuck" for i in range(4)}})
    nap = ([n for n in CHARACTER if n not in awake_off] + ["blanket"], sleepy)
    sk = 1.1
    for j, bg in enumerate(("#EEF0F7", "#2A2F45")):
        ry = y + j * scene_h
        o.append(f'<rect x="{pad}" y="{ry}" width="{W-2*pad}" height="{scene_h}" fill="{bg}"/>')
        ground = ry + scene_h - 75
        cx = pad + half / 2
        o.append(figure(assets, uris, deep[0], cx, ground, sk, deep[1]))
        o.append(at("moon_new", 95, 185, cx, ground, sk))
        for wx, wy in ((-115, 150), (122, 110), (-60, 205)):
            o.append(at("star_twinkle", wx, wy, cx, ground, sk))
        o.append(at("sign_deep", 0, -45, cx, ground, sk))
        cx = pad + half * 1.5
        o.append(figure(assets, uris, nap[0], cx, ground, sk, nap[1]))
        o.append(at("sign_nap", 0, -45, cx, ground, sk))
        for name, wx in (("sign_deep", -half / 2), ("sign_nap", half / 2)):
            a = assets[name]
            lx, ly = pad + half * (1 if wx > 0 else 0) + half / 2 + a["label"][0] * sk, ground + 45 * sk - a["label"][1] * sk
            o.append(f'<rect x="{lx-40}" y="{ly-4}" width="80" height="8" rx="4" fill="#8A8FA3"/>')
    y += 2 * scene_h + pad
    # Outfits: each model on light and dark, the scarf in 5 tints, then each outfit + scarf.
    def mult(fid, c):
        r, g, b = (int(c[i:i + 2], 16) / 255 for i in (1, 3, 5))
        return (f'<filter id="{fid}" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" '
                f'values="{r:.3f} 0 0 0 0 0 {g:.3f} 0 0 0 0 0 {b:.3f} 0 0 0 0 0 1 0"/></filter>')
    o.append("<defs>" + "".join(mult(f"sc{i}", c) for i, c in enumerate(SCARF_TINTS)) + "</defs>")
    base = [n for n in CHARACTER if n not in ("mouth", "bag", "bag_fill")]
    models = ("opus", "sonnet", "haiku")
    scarf = ["scarf", "scarf_tail"]
    rows = [(bg, [(base + [f"outfit_{m}_head", f"outfit_{m}_body"], {}) for m in models], 1.0)
            for bg in ("#EEF0F7", "#2A2F45")]
    rows.append(("#E3E6F0", [(base + scarf, {n: f"sc{i}" for n in scarf}) for i in range(len(SCARF_TINTS))], 0.75))
    rows.append(("#EEF0F7", [(base + [f"outfit_{m}_head", f"outfit_{m}_body"] + scarf,
                              {n: f"sc{i}" for n in scarf}) for i, m in zip((0, 2, 3), models)], 1.0))
    for (bg, figs, k), rh in zip(rows, outfit_rows):
        o.append(f'<rect x="{pad}" y="{y}" width="{W-2*pad}" height="{rh}" fill="{bg}"/>')
        step = (W - 2 * pad) / len(figs)
        for i, (names_, filt) in enumerate(figs):
            o.append(figure(assets, uris, names_, pad + step * (i + 0.5), y + rh - 30, k, filters=filt))
        y += rh
    y += pad
    # Props at 2x, each row on light then dark, with the label slot shown as a grey bar.
    def put(name, cx, cy, k, extra=""):
        a = assets[name]
        w, h = a["size"]
        left, top = cx - a["anchor"][0] * w * k, cy - (1 - a["anchor"][1]) * h * k
        return image(a, uris[name], left, top, k).replace("<image ", f"<image {extra} ")
    prop_grid = [g[i:i + prop_cols] for g in groups for i in range(0, len(g), prop_cols)]
    for r, row in enumerate(prop_grid):
        for j, bg in enumerate(("#F4F4F6", "#2A2F45")):
            ry = y + (2 * r + j) * prop_cell
            o.append(f'<rect x="{pad}" y="{ry}" width="{W-2*pad}" height="{prop_cell}" fill="{bg}"/>')
            for i, name in enumerate(row):
                a = assets[name]
                cx = pad + (i + 0.5) * prop_cell
                cy = ry + prop_cell / 2 - (8 if a.get("label") else 0)
                w, h = a["size"]
                kk = min(pk, (prop_cell - 8) / w)  # wide pills shrink to fit the cell
                if TOP[name][1] != "centre":  # tip/plug pivots: centre the sprite in the cell
                    cx += (a["anchor"][0] - 0.5) * w * kk
                    cy += (0.5 - a["anchor"][1]) * h * kk
                o.append(put(name, cx, cy, kk))
                if a.get("label"):
                    lx, ly = cx + a["label"][0] * kk, cy - a["label"][1] * kk
                    o.append(f'<rect x="{lx-18}" y="{ly-4}" width="36" height="8" rx="4" fill="#8A8FA3"/>')
    y += prop_rows * 2 * prop_cell
    # Fill-level check at 2.5x: bag 0/40/100% through its window, jar 40/100% under the glass.
    kids = {"bag": ["bag", "bag_fill"], "jar_glass": ["jar_glass", "jar_fill", "jar_lid"]}
    for j, bg in enumerate(("#F4F4F6", "#2A2F45")):
        ry = y + j * prop_cell
        o.append(f'<rect x="{pad}" y="{ry}" width="{W-2*pad}" height="{prop_cell}" fill="{bg}"/>')
        for i, (base, lvl) in enumerate(fills):
            wx, wy = world(base, assets)[:2]
            cx, ground, k = pad + (i + 0.5) * prop_cell, ry + prop_cell - 22, 2.5
            o.append(figure(assets, uris, kids[base], cx - wx * k, ground + wy * k, k,
                            levels={kids[base][1]: lvl}))
    y += 2 * prop_cell
    # Tint check: SpriteKit colorBlendFactor 1 multiplies the texture by the colour.
    o.append("<defs>" + "".join(
        f'<filter id="t{i}" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="'
        f'{int(c[1:3],16)/255:.3f} 0 0 0 0 0 {int(c[3:5],16)/255:.3f} 0 0 0 0 0 {int(c[5:7],16)/255:.3f} 0 0 0 0 0 1 0"/></filter>'
        for i, c in enumerate(TINTS)) + "</defs>")
    o.append(f'<rect x="{pad}" y="{y}" width="{W-2*pad}" height="{tint_rows*tint_cell}" fill="#E3E6F0"/>')
    for i, (name, t) in enumerate((n, t) for n in tints for t in range(len(TINTS))):
        cx = pad + (i % tint_cols + 0.5) * tint_cell
        cy = y + (i // tint_cols + 0.5) * tint_cell
        if PROPS[name][1] == "plug":
            cx -= assets[name]["size"][0] * pk / 2
        o.append(put(name, cx, cy, pk, f'filter="url(#t{t})"'))
    y += tint_rows * tint_cell + pad
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
    rasterise(svg, os.path.join(EXPORT, "sheet.png"), int(W * SCALE), int(H * SCALE))


if __name__ == "__main__":
    if not os.access(RSVG, os.X_OK):
        raise SystemExit(f"missing {RSVG}")
    m = export()
    sheet(m)
    print(f"wrote {len(m['assets'])} assets + manifest.json + sheet.png to {EXPORT}")
