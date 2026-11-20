#!/usr/bin/env python3
"""Compose the app icon from the rig parts: happy, front-facing Claudette on a macOS tile.

Run from anywhere: python3 art/icon.py
Writes art/build/icon.svg (scratch) and art/icon/icon_1024.png (the committed master).
Parts and their placement come from art/generate.py (PARTS, BUILTIN), so the icon follows the rig.
Tile follows Apple's macOS icon grid: 824 px squircle centred in 1024, with a soft drop shadow.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
import generate as G  # noqa: E402  (also puts art/src on the path and checks rsvg-convert)

P = G.P
OUT = os.path.join(HERE, "icon", "icon_1024.png")
SIZE, TILE = 1024, 824  # canvas and tile (Apple grid: 100 px gutter each side)
K = 3.25  # pixels per rig point
GROUND = 760  # canvas y of her feet (the rig root)

# Happy pose: the rig at rest plus the emotion-beat mouth, ^ ^ eyes and the spark.
POSE = ["shadow", "leg_0", "leg_1", "leg_2", "leg_3", "arm_L", "arm_R", "body",
        "blush_L", "blush_R", "eye_L", "eye_R", "mouth", "spark"]
SWAP = {"eye_L": P.eye_happy, "eye_R": P.eye_happy, "spark": lambda: P.spark(r=12)}  # spark a touch bigger to read small


def place(name):
    """World position (y up) and global z of a rig node, at rest."""
    if name in G.PARTS:
        _d, parent, pos, z = G.PARTS[name]
    else:
        parent, pos, z = G.BUILTIN[name]
    if parent is None:
        return pos[0], pos[1], z
    px, py, pz = place(parent)
    return px + pos[0], py + pos[1], pz + z


def character():
    """Rig parts in a y-down group whose origin is her feet, sorted by global z like SpriteKit."""
    placed = []
    for i, name in enumerate(POSE):
        frag, _box = SWAP.get(name, G.PARTS[name][0])()
        x, y, z = place(name)
        placed.append((z, i, f'<g transform="translate({x},{-y})">{frag}</g>'))
    return "".join(s for *_k, s in sorted(placed))


def squircle(cx, cy, size, n=5.0, steps=256):
    """Superellipse |x|^n + |y|^n = r^n: close to Apple's continuous-corner tile."""
    r = size / 2
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        pts.append((cx + r * math.copysign(abs(c) ** (2 / n), c), cy + r * math.copysign(abs(s) ** (2 / n), s)))
    return "M" + " L".join(f"{x:.2f},{y:.2f}" for x, y in pts) + " Z"


def icon_svg():
    c = SIZE / 2
    tile = squircle(c, c, TILE)
    t0 = c - TILE / 2
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">'
        "<defs>"
        # Night palette from DESIGN-NOTES (#3B3F66 -> #1D2440): her orange and ink read on it at any size.
        f'<linearGradient id="bg" x1="0" y1="{t0}" x2="0" y2="{t0 + TILE}" gradientUnits="userSpaceOnUse">'
        '<stop offset="0" stop-color="#4A4F80"/><stop offset="1" stop-color="#1D2440"/></linearGradient>'
        # Warm glow behind her, the spark-jar accent (#FFE9A8 -> #F08A4B), so she sits in light.
        f'<radialGradient id="glow" cx="{c}" cy="{GROUND - 70 * K}" r="{TILE * 0.46}" gradientUnits="userSpaceOnUse">'
        '<stop offset="0" stop-color="#FFE9A8" stop-opacity="0.7"/>'
        '<stop offset="0.55" stop-color="#F08A4B" stop-opacity="0.25"/>'
        '<stop offset="1" stop-color="#F08A4B" stop-opacity="0"/></radialGradient>'
        # Top gloss: soft white falling off over the upper third of the tile.
        f'<linearGradient id="gloss" x1="0" y1="{t0}" x2="0" y2="{t0 + TILE * 0.42}" gradientUnits="userSpaceOnUse">'
        '<stop offset="0" stop-color="#fff" stop-opacity="0.16"/><stop offset="1" stop-color="#fff" stop-opacity="0"/>'
        "</linearGradient>"
        f'<clipPath id="tileClip"><path d="{tile}"/></clipPath>'
        '<filter id="drop" x="-20%" y="-20%" width="140%" height="140%">'
        '<feGaussianBlur stdDeviation="14"/></filter>'
        "</defs>"
        f'<path d="{tile}" transform="translate(0,12)" fill="#000" opacity="0.32" filter="url(#drop)"/>'
        f'<path d="{tile}" fill="url(#bg)"/>'
        f'<g clip-path="url(#tileClip)">'
        f'<rect x="{t0}" y="{t0}" width="{TILE}" height="{TILE}" fill="url(#glow)"/>'
        f'<g transform="translate({c},{GROUND}) scale({K})">{character()}</g>'
        f'<rect x="{t0}" y="{t0}" width="{TILE}" height="{TILE}" fill="url(#gloss)"/>'
        "</g>"
        # Hairline rim so the tile edge holds on dark Docks and backgrounds.
        f'<path d="{tile}" fill="none" stroke="#fff" stroke-opacity="0.12" stroke-width="2"/>'
        "</svg>\n"
    )


if __name__ == "__main__":
    os.makedirs(G.BUILD, exist_ok=True)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    svg = os.path.join(G.BUILD, "icon.svg")
    G.write(svg, icon_svg())
    G.rasterise(svg, OUT, SIZE, SIZE)
    print(f"wrote {OUT}")
