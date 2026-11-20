# Claudette: visual direction (Opus pass)

Sheets: `A-soft-vinyl.png`, `B-ink-cel.png`, `C-paper-sticker.png`, `D-usage-limits.png` (plus SVGs).
Sources: `src/claudette.py` (parametric character, one function, all styles/poses) and `src/limits.py`.
Regenerate with `python3 src/claudette.py <outdir>`.

## Recommendation: B "Ink & Cel", plus A's soft shadow

Ship **B (Ink & Cel)** as the main look. Borrow two things from A: the blurred contact shadow and the glossy top sheen.

- **It reads at 96 pt.** The chunky warm-ink outline (#3A1A12) separates her from any wallpaper, light or dark. A's gradients turn to mush at small sizes, and C's white sticker border competes with white windows.
- **It is cheap and crisp in SpriteKit.** Every part is a flat fill with one hard shadow shape and one highlight shape. That is a handful of `SKShapeNode`s or pre-rasterised `SKSpriteNode`s per part, with no gradients to re-render when parts squash.
- **It maps 1:1 to 3D later.** A two-tone hard terminator plus an inverted-hull outline is the standard toon shader, so a Blender or SceneKit version will look like the same character.
- **It fits the user's taste.** It is the "animated-anime" option without drifting off the mascot silhouette.

The other two sheets are not wasted:

- **C (Paper Sticker)** makes a great alternate skin, such as a "Cozy" theme toggle or a seasonal skin.
- **A (Soft Vinyl)** is the reference for a future premium 3D render.

## Palette (B)

| Role | Hex |
|---|---|
| Body base (Claude orange, warmed) | `#E07C56` |
| Body cel shadow | `#B0503A` |
| Legs | `#C9643F`, leg shadow `#9C4430` |
| Highlight streak | `#FFE2CF` |
| Ink outline / eyes | `#3A1A12` / `#26100B` |
| Eye lower reflection | gradient to `#B4482C` |
| Cheek blush | `#F0827A`, hatch `#C93E3A` |
| Spark (status asterisk) | `#FFB48F`, stroke = ink |
| Magic/glow accent | `#FFD978` → `#F08A4B` (spark jar), `#FFE9A8` glow |
| Night (in-limit) | `#1D2440` → `#3B3F66`, blanket `#7B8FD1` |
| Status: question | `#7FC8F8` |
| Status: approval | `#FFC94D` |
| Status: error | `#E5484D` |
| Status: success | `#9BE38B` |

The brand orange `#D97757` stays the "true" colour. It appears on the C skin and in the menubar glyph. On B the body is pushed slightly warmer and lighter so the cel shadow still looks orange rather than brown.

## Shape language and proportions

- **Shape.** She is a brick, softened just enough: the body is a rounded rect with a 16/150 corner radius on B (26 on A, 12 on C). Everything else is a capsule or rounded rect. There are no circles except blush and the moon.
- **Silhouette is locked.** These units are shared by all styles:
  - body 150 × 100, wider than tall (1.5:1)
  - side nubs 27 × 22, centred at 52% of body height
  - four legs 14 wide × 23 long, at x = ±22 and ±51
- **Eyes** are the soul. They are dark, tall rounded rectangles:
  - size 17 × 34 on B (15 × 31 on A), placed slightly *below* the canonical mascot's eye line for baby-schema cuteness
  - one big square catchlight top-left, one tiny one bottom-right
  - on B, a warm reflection in the lower half
- **No mouth at rest** (true to the mascot). A tiny mouth appears only for emotion beats: an open smile when happy, a tongue-out "blep" when focused.
- **The Spark.** Claude's asterisk floats above her head. It is the main glanceable status channel, recoloured or swapped per status: `?` question, `!` approval, a spinning spark for a long shell, a red crack for an error.
- **Line weight.** The ink line is 4.6 units at 123 units tall, about 6 pt at 160 pt and 3.6 pt at 96 pt. Never go below 3 pt on screen.
- **Squash and stretch** happens about the feet. Happy is sx 0.95 / sy 1.07; sleepy is sx 1.07 / sy 0.90. Keep volume roughly constant.

## Rig breakdown (SpriteKit node tree)

```
root (position = feet centre on the ground line)
├─ shadow            ellipse; scales with jump height
├─ legs[0..3]        anchor top-centre; rotate ±12° for walk, scaleY for sit/tuck
├─ bodyPivot         anchor bottom-centre; ALL squash/stretch/lean goes here
│  ├─ arm_L, arm_R   anchor at shoulder (±70, -48); rotate -70°..+60°
│  ├─ body           fill + cel-shadow + highlight (bake as one sprite per style)
│  ├─ blush_L/R      alpha only
│  ├─ face (group, offset x/y for look direction ±6)
│  │  ├─ eye_L/R     anchor centre; scaleY for blink, swap texture for ^ ^ / ‿ / focus
│  │  ├─ lid_L/R     optional flat top-lid sprite for focus/sleepy-half
│  │  └─ mouth       hidden by default; textures: smile, blep, o, wobble
│  └─ prop_socket    attach point beside right nub (file, pencil, scroll, jar)
├─ spark             separate node above head; own bob/spin/recolour
└─ fx layer          z's, sparkles, confetti, sweat, speed lines (SKEmitterNode)
```

`src/claudette.py` already draws the parts in this z-order, with these pivots. Its groups carry no ids yet, and the exported SVGs are flattened sheets. Add ids per part (`leg_0..3`, `arm_L/R`, `bodyPivot`, `eye_L/R`, `spark`, `shadow`) when the parts are split out into textures.

## The first 8 animations/scenes to prototype

1. **Idle breathe + blink.** A 2.4 s sy 1.00↔1.02 loop, blinks every 3–6 s (sometimes doubled), and the spark bobs. Every other scene sits on top of this.
2. **Wake up.** The session starts: she pops in squashed flat, with ‿ eyes, then a yawn (mouth "o", arms up, big stretch to sy 1.12), shakes, and lands in idle.
3. **Read file.** A document with a filename tag poofs in at the prop socket. Her eyes go to focus and look at it, the blep appears, and the lines on the page highlight top to bottom. On completion it folds into a paper plane and flies off.
4. **Edit/Write.** A pencil scribbles on the page, sending small ink-dot particles and the diff lines in orange and green. The typing beat is fast alternating arm nub taps.
5. **Run shell (long-running).** She sits on a tiny terminal box with a spinning spark and dots, peeks every few seconds, then a bounce "ding" on exit 0. A non-zero exit triggers the error beat.
6. **Needs you (approval/question).** She turns to face the screen and the spark becomes a `!` (amber) or `?` (blue) speech bubble. One arm nub raises and waves; it repeats a hop every 8 s until you answer. This is the highest-priority glance state.
7. **Task done → happy.** An anticipation squash, then a jump with ^ ^ eyes, arms up, and the sparkle burst seen in the sheets.
8. **Limit cycle.** The Spark Jar drains, she peeks at it and gets a sweat drop. In limit she naps under a blanket with a "back at HH:MM" sign and the scene tints to night. When the limit lifts the jar bursts, confetti flies, and she jumps.

Sub-agents are 0.55× scale minis with no props of their own. They hand files back to the parent.

## Usage-limit treatment (sheet D)

- **5-hour window = Spark Jar.** She carries a glass jar of sparks on her back (glanceable at 96 pt). Its fill level is the remaining budget, and a paper tag shows `5h 88% · in 47m`. Above 80% the sparks flicker and she peeks at it.
- **Weekly window = the Moon.** It hangs in her little sky (or the menubar glyph): full on reset day, waning as the week is spent, with the tag `new moon Mon 09:00`.
- **In limit.** The whole scene goes night-blue, she naps under a blanket, and a "gone napping · back at 16:40" sign stands next to her. Nothing else looks like this, so it cannot be missed.
- **Lifted.** A one-shot celebration: the jar bursts, sparks fly back in, confetti, and a big cheer jump. Then she goes back to idle.
- **Weekly in limit** (not drawn yet). This is the same nap scene, deeper: a fully dark new moon, a sign reading "back Mon 09:00", and a longer curled-up sleep pose with slower breathing. The jar stays full but untouchable.
- **Menubar.** A moon-phase plus jar-level glyph pair mirrors the state for when she is hidden.
