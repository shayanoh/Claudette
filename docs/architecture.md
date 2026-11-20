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

1. The generated Claude Code plugin registers `http` hooks for the events in
   `PluginInstaller.events`. Each hook POSTs the event JSON to `/hook`; the server answers with an
   empty 2xx immediately, so Claude Code is never held up (a closed app is a non-blocking error).
2. The status line wrapper script (written by `StatusLineInstaller`) forwards the status line JSON
   to `/status` in the background, then runs the user's original status line command unchanged.
3. `AppModel` decodes each message on the main thread and feeds `SessionStore` (sessions, tools,
   sub-agents, approvals, errors) and `LimitsModel` (usage windows). The resulting
   `SessionChange` values drive `Stage`; limit transitions drive `LimitsHUD`.

## Rules worth knowing

- The server binds loopback only, caps bodies at 1 MiB and never throws on bad input.
- `SessionStore` ignores late events for 60 s after `SessionEnd` (a resume `SessionStart` is allowed),
  sleeps idle sessions after 15 min and removes silent ones after 60 min.
- `LimitsModel`: low from 80%, in limit at 100% or after a rate-limit `StopFailure`; a stale high
  reading after a rejection never counts as "lifted".
- Both installers refuse to touch what is not theirs (foreign plugin directory, invalid settings
  JSON) and uninstall restores the original bytes when the file is unchanged since install.
- Rendering pauses when nothing is on screen (0% CPU) and in Focus mode.

## Developer switches (environment variables)

| Variable | Effect |
|---|---|
| `CLAUDETTE_DEBUG=1` | adds Debug menus (add/end session, simulate scene, simulate limits) |
| `CLAUDETTE_DEBUG_SPAWN=N` | starts with N fake sessions |
| `CLAUDETTE_DEBUG_SCENES=a,b,c` | acts out scenes (see `AppModel.scenes`) one per 0.8 s |
| `CLAUDETTE_DEBUG_LIMITS=fresh,low,limit,lifted` | steps through limit states every 4 s |
| `CLAUDETTE_DEBUG_DRAGTEST=1` | drags the first character across the screen using the real code path |
| `CLAUDETTE_LOG_EVENTS=1` | logs raw payloads to `~/Library/Logs/Claudette/events.jsonl` (off by default: prompts) |
| `CLAUDETTE_HOME=dir` | redirects every `~/.claude` and Application Support path (sandbox for testing) |
| `Claudette --write-plugin DIR` | writes the Claude Code plugin to DIR and exits |
