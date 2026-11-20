# Claudette Art Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder shape art with Opus-drawn Ink & Cel art loaded from a part-named @2x PNG export plus JSON manifest, with the placeholder as fallback.

**Architecture:** An Opus-authored generator (`art/generate.py`, extending `design/concepts/opus/src/claudette.py`) writes part SVGs, rasterises them to @2x PNGs with `rsvg-convert`, and emits `art/export/manifest.json` in one command. `ClaudetteCore` owns the manifest schema, validator and pure mappers (tool scene, error kind, model, project to asset or colour). `ClaudetteApp` owns `ArtLibrary` (texture loading) and builds `PuppetNode`, `PropNode`, status and HUD nodes from it, falling back per the rules below.

**Tech Stack:** Swift 6.2 (language mode 5), SwiftPM, SpriteKit, Swift Testing, Python 3 generator, `rsvg-convert` (/usr/local/bin).

**Spec:** `docs/superpowers/specs/2026-11-20-claudette-art-design.md` (read it first, plus `design/concepts/opus/DESIGN-NOTES.md`).

## Global Constraints

- All character and visual design is made by an Opus 5.5 subagent (Agent tool, `model: "opus"`), briefed per "Opus brief" below. The main session writes code, docs, verification only.
- Style B "Ink & Cel" + A's soft contact shadow and top gloss; silhouette locked: body 150x100, nubs 27x22, legs 14x23 at x = ±22, ±51; ink 4.6 units per 123 tall, never below 3 pt on screen; palette from DESIGN-NOTES.
- Export is @2x (`scale: 2` in the manifest, a single generator parameter). PNGs and manifest are committed; runtime needs no Python or rsvg.
- Fallback: the character is all-or-nothing (valid manifest with every required character asset, else whole placeholder); props, status, outfits, accent and weekly-sleep pieces fall back per asset.
- Runtime text (file names, MCP initials, privacy dots, "back at HH:MM") is never baked into art; art leaves a text slot. Scarf and cartridge body are neutral grey art tinted at runtime.
- Colour/hash from a project path or server must be stable across launches (no `hashValue`).
- Idle CPU must stay near ~3% with 3 sessions (`ps -o %cpu,rss`, Intel i7).
- Avatar scale 0.5 to 2.0 (default 1.0 about 128 pt); minis 0.55x; macOS 14+; non-sandboxed; `swift format -i` on Swift; validate all external input (manifest is bounded and sanitised).
- Commits in this repo are pre-approved.

## Review Focus

- Manifest missing, empty, truncated, wrong `version`, or huge: app starts on placeholders, no crash (Task 1, 4).
- Manifest file names with `..`, `/`, absolute paths or non-PNG extensions; sizes/anchors NaN or out of range; parent cycles: rejected by the validator (Task 1).
- PNG listed but missing or corrupt on disk: that asset falls back, the character falls back as a whole (Task 4, 6).
- Unknown MCP server, empty server name, server names with odd characters: generic cartridge, never crashes (Task 2, 6).
- Model name `nil`, empty, or not Opus/Sonnet/Haiku: no outfit, no crash; cwd empty or `/`: a valid accent anyway (Task 2, 9).
- Weekly window in limit while the 5-hour window is not (and vice versa, and both): deep sleep beats nap, lifted returns to idle with no stuck art (Task 2, 8).

## Opus brief (used by Tasks 3, 5, 6, 7, 8, 9)

Dispatch with the Agent tool, `subagent_type` general-purpose, `model: "opus"`. Each brief contains: the locked style files (`design/concepts/opus/DESIGN-NOTES.md`, `src/claudette.py`), the manifest contract (Task 1 "Produces"), the exact asset list and pivots for that task, the output paths, and "draw only what is listed; no text baked into art; neutral grey for tinted layers". Opus may preview SVGs with the Vectorcraft MCP (`open_file` + `render_preview`) and must finish with `scripts/art.sh` exiting 0 (it runs the validator) and a contact sheet at `art/export/sheet.png` the main session can inspect. The main session reads the sheet, checks it against the style (outline weight, palette, silhouette, readability at 96 pt), and sends fixes back to the same Opus agent with SendMessage.

## File Structure

```
art/generate.py                 Opus-authored exporter (parts -> SVG -> PNG -> manifest)
art/src/                        Opus helpers copied/adapted from design/concepts/opus/src
art/export/*.png, manifest.json committed output (+ sheet.png contact sheet)
scripts/art.sh                  regenerate + validate (runs `ClaudetteApp --validate-art`, see Task 3)
Sources/ClaudetteCore/ArtManifest.swift   schema + validate()
Sources/ClaudetteCore/ArtNames.swift      ToolScene/ErrorKind/model/project -> asset or colour; SleepDepth
Sources/ClaudetteApp/ArtLibrary.swift     locate dir, decode, load textures, nil on failure
Sources/ClaudetteApp/PuppetNode*.swift    build from art (new file PuppetNode+Art.swift), fallback intact
Tests/ClaudetteCoreTests/ArtManifestTests.swift, ArtNamesTests.swift
```

Art directory lookup order (App): `CLAUDETTE_ART` env, `Bundle.main.resourceURL/art`, `./art/export` (for `swift run`). `CLAUDETTE_DEBUG_ART=off` forces placeholders for side-by-side screenshots.

---

### Task 1: Manifest schema and validator (Core)

**Files:**
- Create: `Sources/ClaudetteCore/ArtManifest.swift`, `Tests/ClaudetteCoreTests/ArtManifestTests.swift`

**Interfaces:**
- Produces:
  - `public struct ArtAsset: Codable, Equatable, Sendable { file: String; size: [Double]; anchor: [Double]; position: [Double]?; z: Double?; parent: String?; variantOf: String?; label: [Double]?; tint: Bool? }` (points, SpriteKit coordinates: origin bottom-left, y up, `anchor` is the `anchorPoint`, `position` is in the parent's space, `label` is a runtime-text slot in the asset's own space).
  - `public struct ArtManifest: Codable, Equatable, Sendable { version: Int; scale: Int; assets: [String: ArtAsset] }`
  - `public enum ArtManifestError: Error, Equatable { case unsupportedVersion(Int), badScale(Int), tooManyAssets(Int), badFile(String), badGeometry(String), unknownParent(String), parentCycle(String), unknownVariantBase(String) }`
  - `public static func ArtManifest.decode(_ data: Data) throws -> ArtManifest` (size cap 512 KiB, validates), `public func validate() throws`, `public static let requiredCharacter: [String]`, `public func hasCompleteCharacter() -> Bool`.
- `requiredCharacter` is exactly: `shadow, leg_0, leg_1, leg_2, leg_3, arm_L, arm_R, body, blush_L, blush_R, eye_L, eye_R, mouth, spark`. Parent names allowed: another asset, or `root`, `bodyPivot`, `face`. Variants are named `<base>.<variant>` (e.g. `eye_L.happy`, `mouth.blep`, `body.sleep_curl`, `leg_0.tuck`), have `variantOf` set and no `position`/`parent`/`z`.
- Limits: version 1, scale 1...4, at most 400 assets, `file` matches `^[A-Za-z0-9_]+\.png$`, size components in (0, 2048], anchor components in 0...1.

- [ ] **Step 1: Write failing tests** in `ArtManifestTests.swift`: `validManifestDecodes`; `rejectsVersion2`; `rejectsTraversalFile` (`"../x.png"`, `"a/b.png"`, `"x.jpg"`); `rejectsNaNAndOutOfRangeAnchor` (JSON cannot carry NaN, so build the struct and call `validate()`); `rejectsParentCycle` (a to b to a) and `rejectsUnknownParent`; `variantNeedsExistingBase`; `rejectsOversizedData` (600 KiB blob); `incompleteCharacterIsDetected` (valid manifest missing `spark` gives `hasCompleteCharacter() == false`, still validates).
- [ ] **Step 2: Run** `swift test --filter ArtManifestTests`. Expected: FAIL (types undefined).
- [ ] **Step 3: Implement** `ArtManifest.swift` per Interfaces. Cycle check by walking `parent` chains with a visited set.
- [ ] **Step 4: Run** `swift test`. Expected: all PASS.
- [ ] **Step 5: Format and commit.** `swift format -i Sources/ClaudetteCore/ArtManifest.swift Tests/ClaudetteCoreTests/ArtManifestTests.swift`; commit `feat: art manifest schema and validator`.

### Task 2: Asset-name mappers, stable hash, sleep depth (Core)

**Files:**
- Create: `Sources/ClaudetteCore/ArtNames.swift`, `Tests/ClaudetteCoreTests/ArtNamesTests.swift`

**Interfaces:**
- Consumes: `ToolScene`, `ErrorKind`, `LimitStatus` (existing).
- Produces:
  - `public enum ArtNames { static func prop(for: ToolScene) -> String?; static func errorPill(_: ErrorKind) -> String; static let bangBubble = "status_bang"; static let questionBubble = "status_question"; static func knownServer(_ server: String) -> String? }`
  - Prop names: read `prop_read`, search `prop_search`, edit `prop_edit`, write `prop_write`, shell `prop_shell` / `prop_shell_long` / `prop_shell_bg`, web `prop_web`, skill `prop_skill`, mcp `prop_mcp_<github|playwright|figma|context7>` else `prop_mcp_generic`, todo `prop_todo`, plan `prop_plan`, other `prop_other`, subagent `nil`. Cable asset `prop_mcp_cable`. Error pills `status_err_api|auth|billing|ratelimit|offline|unknown`.
  - `knownServer`: lowercase, split on non-alphanumerics, first token equal to `github`, `playwright`, `figma` or `context7` (so `plugin_github_github` is `github`, `claude-in-chrome` is nil).
  - `public enum StableHash { static func fnv1a64(_ s: String) -> UInt64 }`; `public enum Accent { static func hue(forProject path: String) -> Double }` = `Double(fnv1a64(path.trimmed) % 360) / 360`, empty path gives hue of `"/"`.
  - `public enum ModelFamily: Equatable, Sendable { case opus, sonnet, haiku, other; static func from(displayName: String?) -> ModelFamily }` (case-insensitive substring).
  - `public enum SleepDepth: Equatable, Sendable { case awake, nap, deep; static func from(five: LimitStatus, seven: LimitStatus) -> SleepDepth }`: seven `inLimit` is `.deep`, else five `inLimit` is `.nap`, else `.awake`.

- [ ] **Step 1: Write failing tests:** `fnvMatchesKnownVector` (`fnv1a64("a") == 0xaf63dc4c8601ec8c`, `fnv1a64("") == 0xcbf29ce484222325`); `accentIsStableAndInRange` (hue in 0..<1, same twice, empty path equals `"/"`); `propNamesCoverEveryScene` (one `#expect` per `ToolScene` case incl. all three shell flavours); `mcpKnownVsGeneric` (`plugin_github_github`, `context7` known; `claude-in-chrome`, `""` generic); `errorPillsDistinct` (all six kinds, six distinct names); `modelFamily` (`"Opus 4.7"`, `"claude-sonnet-5-5"`, `"Haiku"`, `nil`, `""`, `"Fable"`); `sleepDepthPrecedence` (all 4x4 combinations with deep beating nap).
- [ ] **Step 2: Run** `swift test --filter ArtNamesTests`. Expected: FAIL.
- [ ] **Step 3: Implement** `ArtNames.swift` per Interfaces.
- [ ] **Step 4: Run** `swift test`. Expected: PASS.
- [ ] **Step 5: Format and commit** `feat: art asset-name mappers, stable accent hash, sleep depth`.

### Task 3: Exporter skeleton and pilot parts (Opus + main)

**Files:**
- Create: `art/generate.py`, `art/src/*`, `scripts/art.sh`, `art/export/*` (generated)
- Modify: `.gitignore` only if `art/build/` scratch is added

**Interfaces:**
- Consumes: manifest contract from Task 1.
- Produces: `scripts/art.sh` (regenerates `art/export`, runs the validator, exits non-zero on failure); `art/export/manifest.json` with the pilot assets `shadow, leg_0..3, arm_L, arm_R, body, blush_L, blush_R, eye_L, eye_R, mouth, spark`; validation is a script step: `scripts/art.sh` runs `swift run ClaudetteApp --validate-art <dir>` (add a tiny early-exit flag in `main.swift` that decodes via `ArtManifest.decode`, checks every PNG exists and its pixel size equals `size * scale`, and prints OK or the error).

- [ ] **Step 1: Dispatch Opus** with the brief: extend `claudette.py` into `art/generate.py`; each part drawn alone on a transparent canvas, pivot positions per DESIGN-NOTES rig (body anchor bottom-centre `[0.5, 0]` at `position [0, 23]` in `bodyPivot`'s parent; legs anchor top-centre `[0.5, 1]` at `(x, 23)`, arms anchor at shoulder, eyes centred, blush alpha-ready), SVG to `art/build/*.svg`, `rsvg-convert -z 2 -w <2*size>` to `art/export/*.png`, manifest written by the same script from the same geometry numbers. Required parts list = `ArtManifest.requiredCharacter`; plus a contact sheet.
- [ ] **Step 2: Implement `--validate-art <dir>` in `main.swift`** (run before any AppKit start, `exit(0)`/`exit(1)`) and `scripts/art.sh` (`set -euo pipefail`, `python3 art/generate.py`, then the validate command).
- [ ] **Step 3: Run** `scripts/art.sh`. Expected: prints OK; exit 0. Inspect `art/export/sheet.png`; send style fixes back to Opus until it matches DESIGN-NOTES (outline, palette, cel shadow, gloss, silhouette).
- [ ] **Step 4: Commit** `feat: art exporter and pilot character parts`.

### Task 4: ArtLibrary and the art-built puppet, with fallback (App)

**Files:**
- Create: `Sources/ClaudetteApp/ArtLibrary.swift`, `Sources/ClaudetteApp/PuppetNode+Art.swift`
- Modify: `Sources/ClaudetteApp/PuppetNode.swift` (keep the placeholder `build()` as the fallback; `init` tries art first)

**Interfaces:**
- Produces: `final class ArtLibrary { static let shared: ArtLibrary?; func texture(_ name: String) -> SKTexture?; func asset(_ name: String) -> ArtAsset?; var scale: Int }` (lazy, loads once; `nil` if the dir, manifest, any required character PNG is missing/invalid, or `CLAUDETTE_DEBUG_ART=off`). `PuppetNode` keeps its public API (`legs`, `arms`, `eyes`, `bodyPivot`, `face`, `spark`, `shadow`, `idle/wake/sleep/grab/carry/drop/hop/happy`, `hitBounds`), but `legs/arms/eyes/spark/shadow` become `SKNode` typed where they were `SKShapeNode` (fix call sites; `PuppetStatus` only needs `position`, `run`, `zRotation`, `isHidden`).
- Rule: asset `position`/`anchor`/`z`/`parent` from the manifest place each `SKSpriteNode` (size = asset size, texture filtering `.linear`); node names equal asset names (`leg_0`, `eye_L`...), so existing `childNode(withName:)` lookups keep working.

- [ ] **Step 1: Implement `ArtLibrary`:** directory lookup order from "File Structure", `ArtManifest.decode`, `hasCompleteCharacter()`, `NSImage`/`SKTexture(imageNamed:)` from file URL; log one line via `NSLog` on failure and return nil.
- [ ] **Step 2: Implement `PuppetNode+Art.swift`:** `buildFromArt(_ lib: ArtLibrary) -> Bool` creating the same node tree as `build()`; `init` calls it, and on `false` runs `build()`.
- [ ] **Step 3: Build:** `swift build`. Expected: compiles; `swift test` stays green.
- [ ] **Step 4: Verify on screen:** `swift build -c release`, then `CLAUDETTE_DEBUG_SPAWN=1 .build/release/ClaudetteApp` with `screencapture -x` of her area; repeat with `CLAUDETTE_DEBUG_ART=off`; and with `CLAUDETTE_ART=/nonexistent` and with a corrupted manifest copy. Expected: art, placeholder, placeholder, placeholder; no crash, one log line each.
- [ ] **Step 5: Commit** `feat: load puppet from art export with placeholder fallback`.

### Task 5: Full character: poses, eye and mouth variants (Opus + main)

**Files:**
- Modify: `art/generate.py`, `art/export/*`, `Sources/ClaudetteApp/PuppetNode.swift`, `PuppetNode+Art.swift`

**Interfaces:**
- Consumes: `ArtLibrary.texture(_:)`.
- Produces: new assets `eye_L.happy|sleep|focus|half`, `eye_R.*` (same), `mouth.blep|o|wobble` (base `mouth` = smile, hidden by default), `body.sleep_curl`, `body.sit`, `leg_0..3.tuck`, `bag` (+ `bag_fill` layer, neutral), `jar_glass`, `jar_fill`, `jar_lid`, `moon_dark`, `moon_lit`. New `PuppetNode` methods: `setEyes(_ v: EyeVariant)`, `setMouth(_ v: MouthVariant?)`, `setPose(_ p: BodyPose)` with `enum EyeVariant { open, happy, sleep, focus, half }`, `enum MouthVariant { smile, blep, o, wobble }`, `enum BodyPose { stand, sit, sleepCurl }`; each is a texture swap that is a no-op in placeholder mode.

- [ ] **Step 1: Dispatch Opus** for the asset list above (spec-locked silhouettes; `body.sit` and `body.sleep_curl` keep the 150x100 footprint and the same anchor so they swap in place; tucked legs are shorter variants with the same top anchor).
- [ ] **Step 2: Wire** `happy()` to `happy` eyes plus `smile` mouth, `sleep()` to `sleep` eyes (replacing the `yScale 0.12` placeholder trick when art is present), focus (`focus` eyes + `blep`) exposed for read/edit scenes, `wake()` yawn using `o`.
- [ ] **Step 3: Run** `scripts/art.sh`, `swift build`, `swift test`. Expected: OK, build, PASS.
- [ ] **Step 4: Verify on screen** idle, happy (pet her), sleep (`CLAUDETTE_DEBUG_LIMITS=limit`), grab/drop. Compare with placeholder via `CLAUDETTE_DEBUG_ART=off`.
- [ ] **Step 5: Commit** `feat: full character art with pose and face variants`.

### Task 6: Tool props (Opus + main)

**Files:**
- Modify: `art/generate.py`, `art/export/*`, `Sources/ClaudetteApp/Props.swift`

**Interfaces:**
- Consumes: `ArtNames.prop(for:)`, `ArtNames.knownServer`, `ArtLibrary`.
- Produces: assets `prop_read, prop_search, prop_edit, prop_write, prop_shell, prop_shell_long, prop_shell_bg, prop_web, prop_skill, prop_mcp_generic, prop_mcp_github, prop_mcp_playwright, prop_mcp_figma, prop_mcp_context7, prop_mcp_cable, prop_todo, prop_plan, prop_other`; each has a `label` slot (text under the prop) and the MCP bodies `tint: true` (grey, tinted at runtime). `PropNode.build` uses the art sprite when `ArtNames.prop(for:)` and the library have it, otherwise the existing placeholder case; labels, privacy dots and `shorten`/`initials` stay runtime `SKLabelNode`s placed at `label`.
- Fix: replace `server.hashValue` with `Accent.hue(forProject: server)`.

- [ ] **Step 1: Dispatch Opus** for the prop list (props stand beside her at about 34x44 pt, read at 96 pt, spinner and plane motion are runtime so art is static; cable is a separate tintable tube sprite).
- [ ] **Step 2: Wire `PropNode`:** art path first, per-asset fallback; keep `setCableEnd`; keep animations (pencil scribble, spinner, plane bob) on the sprite nodes.
- [ ] **Step 3: Run** `scripts/art.sh`, `swift build`, `swift test`. Expected: OK, build, PASS.
- [ ] **Step 4: Verify on screen:** `CLAUDETTE_DEBUG_SPAWN=1 CLAUDETTE_DEBUG_SCENES=read,search,edit,write,shell,web,skill,mcp,todo,plan,other` (confirm the scene names in `AppModel.scenes`; add any missing, plus github/figma server samples), screenshot each; check privacy mode shows `•••`; restart twice and confirm the generic cartridge colour is the same each launch.
- [ ] **Step 5: Commit** `feat: tool prop art and stable cartridge colour`.

### Task 7: Status art (Opus + main)

**Files:**
- Modify: `art/generate.py`, `art/export/*`, `Sources/ClaudetteApp/PuppetStatus.swift`

**Interfaces:**
- Consumes: `ArtNames.bangBubble|questionBubble|errorPill(_:)`.
- Produces: assets `status_bang`, `status_question` (round bubbles with glyph), `status_err_api|auth|billing|ratelimit|offline|unknown` (iconic pills, no text: cracked spark, padlock/door sign, coin, hourglass, unplugged cable with no-signal cloud, `?` crack), `status_relief` (sigh puff). `setStatus` and `relief` use art with per-asset placeholder fallback; the waving arm and 8 s hop logic is unchanged.

- [ ] **Step 1: Dispatch Opus** for the list (colours from the status palette: `!` `#FFC94D`, `?` `#7FC8F8`, error `#E5484D`).
- [ ] **Step 2: Wire `PuppetStatus.swift`** badge creation to the art sprites; keep the `errorText` strings as an accessibility/label fallback only for placeholder pills.
- [ ] **Step 3: Run** `scripts/art.sh`, `swift build`, `swift test`. Expected: OK, build, PASS.
- [ ] **Step 4: Verify on screen:** needs-approval, question, and each `ErrorKind` (use the debug scene/phase menu; add debug entries for the missing kinds if absent), screenshot all eight states.
- [ ] **Step 5: Commit** `feat: status bubble and error pill art`.

### Task 8: HUD art and the weekly deep-sleep scene

**Files:**
- Modify: `art/generate.py`, `art/export/*`, `Sources/ClaudetteApp/HUD.swift`, `PuppetNode+Art.swift`, `AppDelegate.swift` (debug step `weeklimit`)

**Interfaces:**
- Consumes: `SleepDepth.from(five:seven:)`, `ArtLibrary`.
- Produces: assets `sign_nap`, `sign_deep` (label slots), `blanket`, `night_patch` (soft sky card), `moon_phase_*` optional; `PuppetNode.setSleepDepth(_ d: SleepDepth)`: `.nap` is the current nap plus blanket, `.deep` uses `body.sleep_curl`, slower breathing (4 s), dark new moon above her and the `sign_deep` text `back <Weekday HH:MM>` from the weekly `resetsAt` via `LimitText`. `JarNode` and `MoonNode` use `jar_*` and `moon_*` art when present (fill and lit-shape clipping stay in code). `HUD.setNight` becomes `HUD.applySleep(_ depth: SleepDepth)` computed from `limits.state(.fiveHour).status` and `limits.state(.sevenDay).status`; lifted goes back to `idle()` and removes the sign, blanket and patch for every actor.

- [ ] **Step 1: Dispatch Opus** for the assets (night palette `#1D2440` to `#3B3F66`, blanket `#7B8FD1`).
- [ ] **Step 2: Implement** `setSleepDepth` and `applySleep` per Interfaces; remove the old `anyLimit`-only path.
- [ ] **Step 3: Run** `swift build`, `swift test`. Expected: build, PASS.
- [ ] **Step 4: Verify on screen** with `CLAUDETTE_DEBUG_LIMITS=fresh,limit,lifted,weeklimit,lifted`: 5 h in limit shows the nap, weekly in limit shows the deep scene, lifted clears all pieces, both limits at once shows deep. Screenshot each.
- [ ] **Step 5: Commit** `feat: HUD art and weekly deep-sleep scene`.

### Task 9: Outfits and per-project accent

**Files:**
- Modify: `art/generate.py`, `art/export/*`, `Sources/ClaudetteApp/Stage.swift`, `PuppetNode+Art.swift`

**Interfaces:**
- Consumes: `ModelFamily.from(displayName:)`, `Accent.hue(forProject:)`, `SessionState.model`, `SessionState.cwd`, `SessionChange.modelChanged`.
- Produces: assets `outfit_opus`, `outfit_sonnet`, `outfit_haiku` (each a layer set on top of the body: names `outfit_<family>_head`, `outfit_<family>_body`; readable at 96 pt, distinct silhouettes) and `scarf` (neutral grey, `tint: true`). `PuppetNode.setOutfit(_ f: ModelFamily)` (`.other` removes the outfit; swaps with a small poof) and `PuppetNode.setAccent(hue: Double)` (tints `scarf` with `NSColor(hue:, saturation: 0.55, brightness: 0.95)`). `Stage.apply` sets both from `sessions[id]` each tick, idempotently (skip when unchanged).

- [ ] **Step 1: Dispatch Opus** for outfits and scarf. Opus decides the designs; the user reviews them.
- [ ] **Step 2: Wire** `Stage.apply`: `actors[id]?.puppet.setOutfit(ModelFamily.from(displayName: state.model))` and `setAccent(hue: Accent.hue(forProject: state.cwd ?? ""))`; minis copy their parent's outfit and accent.
- [ ] **Step 3: Run** `swift build`, `swift test`. Expected: build, PASS.
- [ ] **Step 4: Verify on screen:** spawn 3 sessions with different cwd and models (add `CLAUDETTE_DEBUG_MODELS=opus,sonnet,haiku` to `runDebugHooks` that sets models on spawned sessions if no equivalent exists), screenshot: three outfits, three distinct scarf colours, same colours after a relaunch.
- [ ] **Step 5: Commit** `feat: per-model outfits and per-project accent`.

### Task 10: Packaging, fallback proof, performance, docs

**Files:**
- Modify: `scripts/bundle.sh`, `docs/architecture.md`, `README.md`, `CLAUDE.md`, `docs/spikes/payloads.md` (no), memory

- [ ] **Step 1: `bundle.sh`:** after the `cp`, `mkdir -p "$APP/Contents/Resources" && cp -R art/export "$APP/Contents/Resources/art"` and fail if `art/export/manifest.json` is missing; remove `sheet.png` from the bundle. Run `scripts/bundle.sh`; launch `build/Claudette.app/Contents/MacOS/Claudette` and confirm art loads from the bundle.
- [ ] **Step 2: Fallback proof:** from a copy of the bundle, delete `Resources/art`, then corrupt one PNG, then corrupt the manifest; each launch shows a working placeholder puppet (screenshot), logs one line, no crash.
- [ ] **Step 3: Performance:** `CLAUDETTE_DEBUG_SPAWN=3` idle for 60 s, `ps -o %cpu,rss -p <pid>` sampled 5 times, art vs `CLAUDETTE_DEBUG_ART=off`; expected art within about 1 percentage point of placeholder and near 3% idle. Also screenshot at avatar scale 2.0 and check softness; if soft, set the generator `SCALE = 4` and regenerate.
- [ ] **Step 4: Docs:** describe the pipeline, manifest, fallback rules, `CLAUDETTE_ART` and `CLAUDETTE_DEBUG_ART`, and `scripts/art.sh` in `docs/architecture.md`; README art section; update CLAUDE.md "Layout" and "Decisions" (art is now real, export contract, who draws it). Save a memory note: art pipeline route and the Opus brief rule.
- [ ] **Step 5: Final:** `swift test`, `swift build -c release`, `scripts/art.sh`; commit `docs: art pipeline, fallback and perf results`. The user reviews the look on real hardware and approves or requests changes (their call, not claimed here).
