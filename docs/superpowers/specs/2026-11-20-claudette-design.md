# Claudette: design

Status: draft for approval. Date: 2026-11-20.

## Intent

Claude Code runs for minutes or hours while the user does something else. Claudette is a
macOS menubar-only app (no Dock icon) that gives those sessions a face: a charming,
animated Claude-mascot character that lives on the desktop and acts out what Claude Code
is doing. It is company during long sessions first, and an ambient status display second.

Success looks like: the user keeps it running all day because it is delightful, and
glances at it to learn "needs me", "long shell running", or "limit hit" without switching windows.

## Goals

1. One Claudette per running Claude Code session; sub-agents appear as 0.55x minis that
   split off the parent and hand work back to it.
2. Session lifecycle: start = wake up/yawn on screen; end = fall asleep in a corner and
   wander off-screen.
3. A scene for every tool call (see "Scenes"). Busier/heavier sessions get a more cluttered
   surrounding (clutter scales with recent tool-call rate and number of open props).
4. MCP calls are visually distinct per server: Claudette plugs a coloured cable into a
   labelled cartridge; known servers (GitHub, Playwright, Figma, Context7, ...) get their
   own icon, unknown ones a generic plug with the server's initials.
5. Glanceable status, highest priority first: needs approval, Claude has a question,
   error, long-running shell, usage limit hit, done.
6. Usage limits: 5-hour window = Spark Jar she carries; weekly window = Moon; reset times
   on a tag; night-nap scene when in limit; confetti when lifted (art in
   `design/concepts/opus/D-usage-limits.png`).
7. Interactive: props are clickable (file preview), Claudette can be dragged and waves back,
   looks at the cursor when idle.
8. Context window shown as a backpack that fills; compaction is her squashing it down.
9. Menubar item mirrors state (moon phase + jar level glyph, status dot) for when she is hidden.

## Non-goals (v1)

- Controlling Claude Code (approving permissions, sending prompts) from the app.
- Windows/Linux, cloud sync, telemetry of any kind, analytics.
- Replacing the terminal UI or showing full transcripts.
- 3D rendering (kept possible by the renderer interface).

## Anti-goals (a failure even if it works)

- Distracting or blocking work: she must never steal focus or clicks outside her own
  sprites and props; a Focus mode and Reduce Motion must exist.
- Heavy: noticeable CPU/GPU/battery use. Idle must be near zero (pause when screen is
  locked, a full-screen app is active, or no sessions exist).
- Leaking content: file names and prompts can be hidden (privacy mode) for screen sharing.
- Ugly or off-model: all character art follows the locked style below.

## Approaches considered

| | Approach | Verdict |
|---|---|---|
| A | **Native Swift + SpriteKit, 2D rigged puppet** | **Chosen** |
| B | Native Swift + 3D cel-shaded (Blender, RealityKit) | Later option; B-style art maps 1:1 to a toon shader |
| C | Electron/Tauri + web | Rejected: heavy always-on process for a pet |

Data feed approaches: hooks only (live, precise), transcript tailing only (no install, laggy),
or both. **Chosen: hooks as primary feed, transcript tailing as enrichment**, and the status
line payload for limits, context and model (below).

## Art direction (decided)

Style **B "Ink & Cel"** (chunky warm-ink outline, hard two-tone cel shading, tall glossy
eyes) with **A's soft blurred contact shadow and top gloss** added. Claude-mascot silhouette
is locked (body 150x100, side nubs, four legs, the Claude spark above the head). Palette,
proportions, the SpriteKit rig tree and the first eight animations are in
`design/concepts/opus/DESIGN-NOTES.md`; generator scripts in `design/concepts/opus/src/`.
C (Paper Sticker) is a possible later alternate skin.

**Process rule (user decision):** all character and visual design is produced by an Opus 5.5
subagent, briefed with the locked style. Still to be drawn: tool-call props, MCP cartridges,
status scenes (approval, question, error, long shell, weekly limit), per-model outfits,
and a part-named, rig-ready export.

## Data sources

### Hooks (primary)

Confirmed in the official docs (fetched 2026-11-20): events SessionStart/SessionEnd,
UserPromptSubmit, Stop, StopFailure, PreToolUse, PostToolUse, PostToolUseFailure,
PostToolBatch, PermissionRequest, PermissionDenied, SubagentStart/SubagentStop,
TaskCreated/TaskCompleted, PreCompact/PostCompact, PreModelSwitch/PostModelSwitch,
WorktreeCreate/Remove, Notification, Elicitation, CwdChanged and more.
Common stdin fields: `session_id`, `transcript_path`, `cwd`, `hook_event_name`,
`permission_mode`, `agent_id`/`agent_type` (inside sub-agents). Tool events carry `tool_name`,
`tool_input`, `tool_use_id`, `duration_ms`; MCP tools are named `mcp__<server>__<tool>` and
PreToolUse also carries `mcp_server {name, source}`. Notification types include
`permission_prompt`, `idle_prompt`, `agent_needs_input`, `elicitation_dialog`,
`quota_auto_resume_*`. Hook handler types: `command`, `http`, `mcp_tool`, `prompt`, `agent`.

Mapping (summary):

| Event | Claudette |
|---|---|
| SessionStart / SessionEnd | wake+yawn / nap and wander off |
| PreToolUse -> PostToolUse(+Failure) | scene starts / resolves (success beat or oops) |
| PermissionRequest, Notification permission_prompt | "needs you" wave with amber `!` |
| Notification elicitation / agent_needs_input | blue `?` bubble |
| SubagentStart / SubagentStop | mini splits off / merges back |
| PreCompact / PostCompact | squash the backpack |
| PreModelSwitch / PostModelSwitch | swap outfit |
| StopFailure (rate_limit etc.) | oops / in-limit scene |
| Stop | task-done happy beat |
| TaskCreated / TaskCompleted | clipboard item appears / ticks |

### Status line payload (limits, context, model, cost)

Official docs and Orca's source agree: Claude Code passes `rate_limits.five_hour` and
`rate_limits.seven_day`, each with `used_percentage` (0-100) and `resets_at` (epoch seconds),
to the `statusLine` command, for claude.ai Pro/Max/Ultra subscribers only, after the first
API response in a session. The same payload has `model`, `cost.total_cost_usd`,
`context_window.used_percentage`, `workspace`, `worktree`, `session_id`. No login needed.
Claudette installs a small status line wrapper that forwards the payload to the app and then
runs the user's existing status line command unchanged (so their status line keeps working).
Windows can be absent independently and vanish after `resets_at`; the UI must handle that.
Fallback considered and **not** in v1: Anthropic's OAuth usage endpoint (undocumented,
needs a token, rate-limits aggressively per Orca's experience).

### Transcript tailing (enrichment)

`transcript_path` JSONL, for things hooks lack (thinking blocks, streaming activity, token
usage). Treated as best effort: parse defensively, never block on it, tolerate schema drift.
Docs say it may lag the current turn.

### Installing the feed

Preferred: ship a Claude Code **plugin** (hooks.json using `http` handlers to the app's
127.0.0.1 server, all `async` so Claude is never slowed) so install/uninstall is clean and
reversible; the status line wrapper is the one piece that needs a user-approved edit to
`settings.json` (never edited silently). If the app is not running, hook delivery fails
non-blocking. These install details are my call and need a quick verification spike.

## Architecture

```
Claude Code sessions ──hooks (http, async)──────┐
                     ──statusLine wrapper───────┤
                     ──transcript JSONL tail────┘
                                                ▼
 Claudette.app (Swift, LSUIElement)
  ├─ FeedServer       127.0.0.1 HTTP listener, validates + decodes payloads
  ├─ SessionStore     per-session state machines keyed by session_id / agent_id
  ├─ LimitsModel      5h/7d windows, reset timers, in-limit/lifted transitions
  ├─ SceneDirector    events + state -> scene requests (priority, cooldowns, queueing)
  ├─ Renderer (protocol; SpriteKit impl)  puppet rig, props, fx, clutter
  ├─ Overlay          one transparent click-through NSPanel per screen; hit-testing only on sprites
  └─ MenuBar          NSStatusItem glyph + menu (sessions, settings, install/uninstall, focus mode)
```

Key behaviours: untrusted input (payloads from localhost) is validated and size-capped;
listener binds to loopback only; per-session placement avoids overlap; sessions with no
events for N minutes and no SessionEnd (crash) are put to sleep then removed.

## Scenes (tool call -> prop and pose)

Read: scroll with filename, eyes scan. Grep/Glob: magnifying glass, hop per match.
Edit/Write: pencil + diff lines, typing arms. Bash: terminal box; long-running: she sits
on it, spinner spark, optional book/snack. WebFetch/WebSearch: paper plane / telescope.
Task (sub-agent): mini splits off. TodoWrite/Tasks: clipboard ticks. Plan mode: blueprint.
Skill: spellbook. MCP: cable + cartridge. Notebook: notebook. Git ops: tiny branch tree.
Tests pass/fail: plant blooms/droops. Thinking: thought bubble with slow sparkles.
Esc/interrupt: startled then shrug. Errors: oops + band-aid. Time-of-day sky tint.
Per-project accent colour or scarf to tell sessions apart.

## Constraints and risks

- Knowing other apps' window frames (to perch on title bars) may need permissions; v1 can
  fall back to screen edges and the Dock line.
- Several hook details are not confirmed (StopFailure payload, TaskCreated fields,
  background-shell events, whether rate_limits appears in hooks); verify against a real
  session and pin a supported Claude Code version range.
- Status line limits only update while a session is active, and only for subscribers.
- Hooks API may change; the FeedServer must degrade gracefully on unknown fields/events.

## Calls made after the builder check (my calls, not the user's; flag if wrong)

- **Long shell:** a Bash PreToolUse with no PostToolUse after 10 s (configurable) counts as
  long-running. `run_in_background` in `tool_input` marks a backgrounded shell, which stays
  as a prop until a later event or the transcript shows it finished. If hooks cannot carry a
  state, that scene degrades (plain "working") rather than blocking the build. The step-1
  spike is a gate for these details.
- **Hook delivery:** if `http`/`async` hooks misbehave, fall back to `command` hooks calling
  a tiny helper that posts to the loopback server. Stale sessions (no events, no SessionEnd)
  sleep after 15 minutes and are removed after 60. SessionEnd is not assumed on crash.
- **Art vs build:** the build proceeds on placeholder shapes behind the Renderer protocol.
  Export contract, defined here and given to Opus in its brief: one @2x PNG per named part
  (`leg_0..3`, `arm_L/R`, `body`, `eye_L/R`, `mouth_*`, `spark`, `shadow`, props) plus a JSON
  manifest with anchor points and z-order.
- **Distribution:** direct, notarised, non-sandboxed (loopback server and `settings.json`
  edit make a sandboxed App Store build a non-starter). Minimum macOS 14.
- **Status line wrapper:** edits user-level `~/.claude/settings.json` only, after explicit
  consent, with a backup and the original command stored by the app. No existing command:
  the wrapper only forwards. A project-level status line overrides the user-level one, so the
  app detects this and warns. Uninstall restores the original only if the current value is
  still ours.
- **Displays and sessions:** a session starts on the screen with the cursor and can be
  dragged between screens (remembered per session). At most 6 full-size Claudettes; extras
  collapse into a stack of minis with a count.
- **Visibility:** she appears over full-screen Spaces (a terminal is often full-screen);
  pause rendering only when the screen is locked/asleep or Focus mode is on.
- **Click-through:** the panel ignores mouse events except over sprites and props, never
  takes key focus.
- **Preview and privacy:** prop click opens Quick Look on the file when it exists. Privacy
  mode redacts file names, prompts, cwd/project names and MCP server names, in the overlay
  and the menu. Accent colour comes from a hash of the project path.
- **Identity:** the same `session_id` resumed reuses its Claudette. Only settings and the last
  limits snapshot persist across restarts.
- **Limits states:** no data (API-key user, or before the first response) shows a dim jar and
  no moon; a single window shows only that meter. In limit = used >= 100% or a
  rate-limit StopFailure, whichever comes first. Lifted = `resets_at` passes or a later payload
  shows a lower percentage.

## Left to the builder

Swift project layout and packaging, exact animation timings, sprite export pipeline,
placement/steering algorithm, preference UI, test strategy, notarisation/distribution.

## Proposed build order

1. Verification spike: real hook + status line payload capture to a log (no UI).
2. Menubar app + FeedServer + SessionStore with a debug text overlay.
3. Rig-ready Opus-drawn character; idle, wake, sleep, one session on screen.
4. Read/Edit/Bash/needs-you scenes; sub-agent minis; limits (jar, moon, nap, confetti).
5. MCP cartridges, remaining scenes, clutter, interactions, settings, installer.
