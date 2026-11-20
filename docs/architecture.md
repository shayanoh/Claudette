# Architecture

Claudette is a Swift package with two targets.

```
Claude Code  ──hooks (http)──────────────┐
             ──status line wrapper───────┤        127.0.0.1:47631
                                         ▼
 ClaudetteCore (pure, unit tested)            ClaudetteApp (AppKit/SpriteKit/SwiftUI)
  FeedServer  POST /hook, /status              AppModel     wires everything, 1 s tick
  HookEvent / StatusPayload  decoding          Stage        per-session characters, layout,
  SessionStore  per-session state machines                    pointer behaviour, dragging
  LimitsModel   5-hour / weekly windows        OverlayController  one transparent panel per display
  SceneMapper   tool call -> ToolScene         PuppetNode / PuppetStatus / Props  placeholder art
  Geometry      placement, dodge, fade, drag   LimitsHUD    jar, moon, night tint, confetti
  Settings      clamped + persisted            SettingsView window; menubar menu in AppDelegate
  PluginInstaller / StatusLineInstaller        PointerTracker  global + local mouse monitors
```

## Data flow

1. The generated Claude Code plugin registers `command` hooks for the events in
   `PluginInstaller.events`, all running `hooks/post.sh`: it reads the event, POSTs it to `/hook` with
   a detached background `curl`, prints nothing and always exits 0, so Claude Code is never held up
   and a closed app produces no hook error. (Older installs used `http` hooks; `isLegacy` detects them
   and Settings offers the update.) The server answers with an empty 2xx immediately.
2. The status line wrapper script (written by `StatusLineInstaller`) forwards the status line JSON
   to `/status` in the background, then runs the user's original status line command unchanged.
3. `AppModel` decodes each message on the main thread and feeds `SessionStore` (sessions, tools,
   sub-agents, approvals, errors) and `LimitsModel` (usage windows). The resulting
   `SessionChange` values drive `Stage`; limit transitions drive `LimitsHUD`.

## The world (items, walking, perching)

Items are objects of the stage, not props of a puppet. `ClaudetteCore` holds the rules, unit tested:
`WorldModel` (items keyed by identity: a file is its absolute normalised path, so every session and
sub-agent shares one item; a terminal is its `tool_use_id`; a skill is its name; owners, hard cap,
eviction), `Scatter` (where a new item lands: near the actor, spacing, wider when crowded, always on a
screen), `Brain` (events in, a short queue of `Intent`s out: walk, face, pick up, play, toss, put
down, sit, fall), and `PerchPlanner` (which window top edge is free; when the window was pulled away).
`ClaudetteApp` only animates: `World` owns the model, the `ItemNode`s and runs the intents (walking is
a per-frame `customAction`), `Stage` positions actors (`feet(of:)`/`setFeet`), `WindowTracker` reads
window bounds (no titles, no Screen Recording permission). Items materialise next to whoever
touched them, stay until cleanup or the cap, and can be dragged (`ItemNode` is `Draggable`); she
walks to wherever they are. Sub-agents are small `Actor`s tethered to their parent (`leash`).
`SessionStore` supplies `isThinking` (she paces with a thought bubble) and `ToolResult`s (terminal
hover text). Z order: with `ignoresSiblingOrder` SpriteKit sorts by global z, so each Claudette
gets her own z band (`Stage.bringToFront`, 200 apart, sub-agents +100); drags, tooltips and
confetti sit at `Stage.overlayZ`.

## Overlay targets

`Draggable` (app) is the hit-test contract for anything on the overlay besides the avatars: `hitRect`
in global coordinates, hover enter/exit, and a drag. `Stage.draggables` holds them (avatars win when
both are under the pointer); today that is the weekly moon (`MoonHandle`, position stored as a fraction
of the main display in settings). Item labels are drawn once per text by `LabelTexture` (one soft
`NSShadow`, cached), not by live effect nodes.

## Rules worth knowing

- The server binds loopback only, caps bodies at 1 MiB and never throws on bad input.
- `SessionStore` ignores late events for 60 s after `SessionEnd` (a resume `SessionStart` is allowed),
  sleeps idle sessions after 15 min and removes silent ones after 60 min.
- `LimitsModel`: low from 80%, in limit at 100% or after a rate-limit `StopFailure`; a stale high
  reading after a rejection never counts as "lifted".
- Both installers refuse to touch what is not theirs (foreign plugin directory, invalid settings
  JSON) and uninstall restores the original bytes when the file is unchanged since install.
- Heavy-session check (2026-11-20, debug build, Intel i7): 80 items around one Claudette idle at
  about 2.5% CPU and 51 MB.
- Rendering pauses when nothing is on screen (0% CPU) and in Focus mode.

## Art pipeline

All character art is drawn by an Opus subagent (project rule) as code: `art/generate.py` (+ `art/src/`)
draws every part as SVG, `rsvg-convert` rasterises each to an @2x PNG, and the same script writes
`art/export/manifest.json` (anchor, size, position, z, parent, label slot, tint flag per asset).
`scripts/art.sh` regenerates and validates (`Claudette --validate-art <dir>`: manifest rules plus every
PNG's pixel size). The PNGs and manifest are committed, so building the app needs neither Python nor rsvg.

- `ClaudetteCore`: `ArtManifest` (schema, bounds, safe file names, parent cycles) and `ArtNames`
  (tool scene, error kind, model family, project path to asset or colour; `Accent.hue` uses FNV-1a so
  colours are the same on every launch; `SleepDepth` = weekly limit beats 5-hour nap).
- `ClaudetteApp`: `ArtLibrary` (lookup order `CLAUDETTE_ART`, `Claudette.app/Contents/Resources/art`,
  `./art/export`) feeds `PuppetNode`, `PropNode`, status badges, `LimitsHUD`.
- Fallback: the character is all-or-nothing (valid manifest and every required part loads, else the whole
  shape placeholder); props, badges, signs, outfits and scarf fall back one asset at a time.
- Runtime text (file names, MCP initials, privacy dots, sign times, pill text) is never baked into art;
  assets only mark a `label` slot. Scarf and MCP cartridges are neutral grey art tinted at runtime.
- Assets are named `<base>.<variant>` for texture swaps (`eye_L.happy`, `mouth.blep`, `body.sleep_curl`,
  `leg_0.tuck`); a variant has the same canvas and anchor as its base.

## Developer switches (environment variables)

| Variable | Effect |
|---|---|
| `CLAUDETTE_DEBUG=1` | adds Debug menus (add/end session, simulate scene, simulate limits) |
| `CLAUDETTE_DEBUG_SPAWN=N` | starts with N fake sessions |
| `CLAUDETTE_DEBUG_SCENES=a,b,c` | acts out scenes (see `AppModel.scenes`) one per 0.8 s |
| `CLAUDETTE_DEBUG_LIMITS=fresh,low,limit,weeklimit,lifted` | steps through limit states every 4 s |
| `CLAUDETTE_DEBUG_MODELS=opus,sonnet,haiku` | gives spawned sessions those models in turn (outfits) |
| `CLAUDETTE_ART=dir` | art export to use first; `CLAUDETTE_DEBUG_ART=off` forces the shape placeholders |
| `APP_OUT=dir scripts/bundle.sh` | builds the app bundle somewhere other than `build/Claudette.app` |
| `CLAUDETTE_DEBUG_MOONDRAG=1` | drags the moon (first `Draggable`) to the screen centre through the real code path |
| `Claudette --render-props <png>` | draws every prop kind on a light and a dark backdrop (label legibility), then exits |
| `CLAUDETTE_DEBUG_CLUTTER=N` | (with `CLAUDETTE_DEBUG_SPAWN=1`) leaves N files and terminals around the first Claudette |
| `Claudette --render-overlap <png>` | two overlapping Claudettes (same z vs a band each), a thought bubble and a sub-agent |
| `CLAUDETTE_DEBUG_DRAGTEST=1` | drags the first character across the screen using the real code path |
| `CLAUDETTE_LOG_EVENTS=1` | logs raw payloads to `~/Library/Logs/Claudette/events.jsonl` (off by default: prompts) |
| `CLAUDETTE_HOME=dir` | redirects every `~/.claude` and Application Support path (sandbox for testing) |
| `Claudette --write-plugin DIR` | writes the Claude Code plugin to DIR and exits |
