# Claudette: art plan design

Status: draft for approval. Date: 2026-11-20. Parent spec: `2026-11-20-claudette-design.md`.

## Intent

Replace the placeholder shape art (`PuppetNode`, `Props`, `PuppetStatus`, parts of `HUD`) with the
final art in the locked style B "Ink & Cel" plus A's soft contact shadow and top gloss. Charm
comes first: the user keeps her running all day because she is delightful; glanceable status is
second. All character and visual design is produced by an Opus 5.5 subagent (user rule); the
main session writes code, docs and verification only.

## Goals

1. A rig-ready export: one @2x PNG per named part plus a JSON manifest (anchor, z-order, size),
   produced by one command, and a loader that builds `PuppetNode` from it. The current
   placeholder stays as the fallback when the export is missing or invalid.
2. Props for every `ToolScene`: read, search, edit, write, shell (short / long / background),
   web, skill, mcp (cartridge + cable), todo, plan, other. (`subagent` has no prop; the mini is
   the visual.)
3. Status art: `!` and `?` bubbles; error pills for api / auth / billing / rateLimit /
   disconnect (+ unknown); the weekly-limit deep-sleep scene; backpack (`bag`) and jar parts.
4. Per-model outfits (Opus / Sonnet / Haiku) and a per-project accent colour or scarf.
5. Unit-testable logic lives in `ClaudetteCore`; UI stays out of it; `swift test` stays green.

## Non-goals

- 3D / alternate skins (C Paper Sticker), new animations beyond what the art needs
  (that is the scene-polish plan), new hook data.
- The menubar glyph (`MenuBarGlyph`): stays code-drawn as a template image.
- Runtime text: file names, MCP initials, privacy dots and "back at HH:MM" tags stay runtime
  `SKLabelNode` text drawn into empty slots; they are never baked into art.

## Anti-goals

- Off-model art: anything not matching the locked style, palette and silhouette.
- A texture set that can only be changed by hand-editing sprites (every asset must be
  regenerable by one command).
- A broken or missing export crashing the app or leaving her invisible.
- Heavier rendering: idle CPU must stay near the ~3% measured with 3 sessions
  (measure with `ps -o %cpu,rss` before and after; Intel i7).

## Constraints

- Style and palette: `design/concepts/opus/DESIGN-NOTES.md` and `src/claudette.py`.
  Silhouette locked: body 150x100, nubs 27x22, legs 14x23 at x = ±22, ±51, ink 4.6/123 units,
  never below 3 pt on screen.
- Rig tree (DESIGN-NOTES): root > shadow, legs[0..3], bodyPivot > arm_L/R, body, blush_L/R,
  face > eye_L/R (+lid), mouth, prop_socket; spark and fx above.
- Hash-based colour must be stable across launches (current `server.hashValue` is randomised
  per process: a bug, fixed here with a stable hash in Core).
- macOS 14+, SwiftPM executable; assets ship inside `Claudette.app` via `scripts/bundle.sh`.
- Swift formatted with `swift format`; Python generator formatted per repo habit; validate all
  external input (manifest is untrusted-ish: sizes, paths, counts bounded).

## Approaches considered

| | Approach | Verdict |
|---|---|---|
| A | Opus extends `claudette.py` into an exporter: every part drawn from the locked parametric shapes; the same script writes part SVGs, @2x PNGs and the manifest | **Chosen by the user** |
| B | Opus hand-writes standalone SVG per part, separate slicing/manifest step | Rejected: style and pivots drift, manifest hand-maintained |
| C | Opus paints whole sheets, main session slices | Rejected: overlapping outlines cannot be cut into clean rig parts |

Chosen pose strategy (user pick, option 2): **rig plus a few swap-in textures**. Poses come
from transforming parts, plus whole-part texture swaps for what rotation cannot make:
`body_sleep_curl`, `body_sit`, a tucked-legs set, eye variants (`^ ^`, `‿`, focus, half-lid)
and mouth variants (`smile`, `blep`, `o`, `wobble`).

## Design

### Pipeline

```
art/generate.py (Opus-authored, extends design/concepts/opus/src/claudette.py)
  -> design/art/parts/*.svg     one SVG per part, own pivot, transparent
  -> Sources/ClaudetteApp/Resources/art/*.png   @2x, via rsvg-convert -z 2 (installed)
  -> Sources/ClaudetteApp/Resources/art/manifest.json
```

- Rasteriser: `rsvg-convert` (present at /usr/local/bin). No Python dependency needed.
- Vectorcraft MCP: optional QA for Opus (open the SVG sheet, `render_preview`) and a way to
  eyeball parts; AniCraft optional for previewing motion; neither is on the build path.
- PNGs and manifest are committed (build from source must work without Python or rsvg).
- A one-command `scripts/art.sh` regenerates all and runs the manifest validator.

### Manifest contract (`ClaudetteCore`, pure, tested)

```
{ "version": 1, "scale": 2, "parts": {
    "body":   { "file": "body.png", "size": [150,100], "anchor": [0.5,0.0],
                "position": [0,23], "z": 1, "parent": "bodyPivot" },
    ... },
  "variants": { "eye": ["open","happy","sleep","focus","half"], "mouth": [...] },
  "props":    { "read": {...}, "mcp_cartridge": {...} },
  "outfits":  { "opus": [...], "sonnet": [...], "haiku": [...] },
  "tint": ["scarf", "cartridge_body"] }
```

- Core: `ArtManifest` (Codable) + `validate()` (known parts present, files named safely with no
  path separators, sizes/anchors in range, parent exists, no cycles, count and size caps).
- Core: mapping helpers, all pure: `ToolScene -> propAsset`, `ErrorKind -> pillAsset`,
  model display name -> `ModelFamily` (opus/sonnet/haiku/other), project path -> accent hue
  (stable FNV-1a, not `hashValue`), `Phase`/limit state -> which weekly/5h asset.
- App: `ArtLibrary` loads the manifest and textures (Bundle resource dir, or
  `CLAUDETTE_ART=<dir>` for dev), returns nil on any failure; `PuppetNode` builds from the
  library when present, else the existing shape build. Same public API (`idle`, `wake`, `sleep`,
  `setStatus`, `setContext`, ...), so `Stage` and tests do not change.

### Runtime tint

Accent scarf, MCP cartridge body and any per-project colour are drawn as neutral
(white/grey, ink outline kept) layers and tinted at runtime (`SKSpriteNode.color` +
`colorBlendFactor`). Outfits are separate part sets chosen by `ModelFamily`.

### Art inventory for Opus

1. **Character parts**: shadow, leg_0..3 (+ tucked set), arm_L/R, body (+ `body_sleep_curl`,
   `body_sit`), blush_L/R, eye_L/R variants (+ lid), mouth_*, spark, bag, jar (empty/filled
   layers so fill height is code-clipped), moon phases or lit/shadow layers.
2. **Props** (label-free, with text slots): file page, magnifier, pencil + page, terminal box
   (+ spinner), paper plane/telescope, spellbook, cartridge + cable (+ generic plug),
   clipboard, blueprint, gear, plus `known-server icons` for GitHub, Playwright, Figma,
   Context7 (others use generic plug + runtime initials).
3. **Status**: `!` and `?` bubbles, five error pills + unknown (text slot or iconic glyph),
   cracked spark, unplugged-cable-with-no-signal cloud, locked-door sign, "gone napping" sign
   board, weekly deep-sleep scene pieces (dark new moon, blanket, sign "back Mon HH:MM").
4. **Outfits**: Opus / Sonnet / Haiku, readable at 96 pt, plus scarf layer.

### Order of work (vertical slice first)

1. Main session: schema, Core validator and mappers (TDD), App `ArtLibrary` + `PuppetNode`
   loader behind the fallback, `scripts/art.sh`, bundle.sh copies resources. Pilot export
   (body, legs, arms, eyes, spark) from Opus; verify on screen.
2. Opus: full character incl. pose swaps and variants.
3. Opus: props, then status/limit/weekly-sleep art; main session wires `PropNode`,
   `PuppetStatus`, `HUD` to the library (placeholders remain fallback per asset).
4. Opus: outfits + scarf; wire model change (`modelChanged`) and accent.

Each Opus task gets a written brief: locked style files, the manifest contract, the exact part
list and pivots for that stage, and the rule "draw only what is listed".

### Verification

- Core: `swift test` for validator, mappers, stable hash (same value across processes).
- App: screenshots via the existing debug switches (`CLAUDETTE_DEBUG_*`), side-by-side
  placeholder vs art, every scene and every `ErrorKind`, all three outfits, 5 accent colours,
  at scale 0.5 / 1.0 / 2.0 and over light and dark wallpaper. The user judges the look.
- `ps -o %cpu,rss` idle (3 sessions) before/after; texture atlas memory noted.
- Fallback test: delete the art dir / corrupt the manifest, app still runs on placeholders.

## Calls made after the builder check (my calls, not the user's; flag if wrong)

- **Raster scale:** ships at @2x as the user specified (256 px per 128 pt at scale 1.0). The scale
  is a single generator parameter recorded in the manifest. Verification checks softness at
  avatar scale 2.0 on this Retina display; if it is soft, switch to @4x (one-line change,
  textures are small).
- **Fallback granularity:** the character is all-or-nothing (a valid manifest with every required
  character part means the whole puppet comes from art; otherwise the whole placeholder).
  Props, status badges, outfits and accent fall back per asset, since those are independent
  nodes. This replaces the looser wording under "Order of work, step 3".

## Left to the builder

Exact filenames, atlas packing (single SKTextureAtlas vs loose PNGs), animation timing for new
swap-ins, anchor numbers per part, how many known-server icons beyond the four, the final
outfit designs (Opus decides; the user reviews).
