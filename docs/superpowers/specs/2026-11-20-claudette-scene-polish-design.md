# Claudette: scene polish and the living desktop (design)

Status: draft for approval. Date: 2026-11-20. Follows `2026-11-20-claudette-design.md` (the
"scene polish plan" left open there) and `2026-11-20-claudette-art-design.md`.

## Intent

Today a tool call makes a prop appear beside Claudette, tied to her by a cable, and vanish a
fraction of a second after the tool finishes. She stands still. This phase turns the screen into a
small world: she **walks** to things, **reads and tosses** them, and what she touched **stays**
where it landed. A glance at the desktop then says who is working on what (project names), what
ran (terminal items), and how heavy the session was (clutter). Tidying up is part of the
character's life: she cleans after herself, clumsily, and there is a menubar Cleanup for
everyone. Success: you keep it running all day because the world is charming, and the clutter
reads as a diary of the session instead of noise.

## Goals

1. **Phase 1, quick wins** (independent of the world model).
   1. Hooks fail silently when Claudette is not running (no error reports in Claude Code).
   2. Menubar icon is Claudette herself, not a letter, and looks good.
   3. Settings window redesigned (labels, grouping, layout) by an Opus subagent.
   4. Item labels bigger, with one soft drop shadow instead of the current double hard shadow.
   5. The weekly moon fades to transparent under the pointer and can be dragged.
2. **Phase 2, world model.**
   1. Items (files, terminals, other tools) are objects of their own, not children of a
      puppet. No cable to her. They materialise where she stands, scattered with room between
      them, and stay until collected.
   2. The same file is the same item: a repeat read, edit or write walks to the item already on
      screen, whichever session or sub-agent asks.
   3. Items are draggable with the mouse; she walks to wherever they were moved.
   4. She walks around while thinking, with a proper thinking animation.
   5. Terminal items are larger, show the start of the command inside as far as space allows,
      show the full command on hover, and show the result on hover when done. Finished
      terminals stay around the screen.
   6. Sub-agents are separate, smaller actors (0.55x) that stay near their parent but move and
      work on their own.
   7. Hovering a Claudette shows her project (folder or worktree name) under her.
   8. Shyness: if she dodges the pointer while holding an item, she carries it and puts it down
      where she ends up.
   9. Perching: passing a window's top edge, she can sit on it; if the window moves or goes
      away she gets a sudden jerk (the chair is pulled away), drops to the ground and carries on.
   10. A heavy session leaves a big, visible clutter.
3. **Phase 3, cleanup and the full animation set.**
   1. Manual **Cleanup** in the menubar menu: all Claudettes find every leftover item, carry it
      to a trash can that appears and later leaves, then go back to normal. Animated and
      clumsy, about 10 to 30 seconds depending on the amount.
   2. **Automatic partial cleanup:** when a session is waiting for you (approval, question,
      finished turn) and its own clutter is over a limit, her Claudette tidies some of it.
   3. **End of session:** the Claudette cleans up everything that belongs only to her session,
      then goes to sleep and wanders off as today.
   4. The full animation set, coordinated with Opus-drawn art: yawn and stretch on waking,
      typing, reading scan, searching hop, thinking walk, pick up, carry, toss, trip, celebrate,
      shrug, startled, perch sit, perch jerk.
4. **Hook fix details** are in Phase 1; the rest of the existing behaviour (limits, status
   scenes, dragging, dodging, hover fade) keeps working.

## Non-goals

- Items surviving an app restart (the world lives for the app run).
- Transcript tailing (listed in the old plan, nothing in these notes needs it; thinking is
  detected from hook events). Deferred, my call.
- Reading other apps' window titles or content (perching uses window frames only; see Constraints).
- Controlling Claude Code, new telemetry, a 3D renderer.

## Anti-goals (a failure even if it works)

- Clutter that blocks work: items are click-through everywhere except their own shape, never take
  key focus, and are capped. Clutter that grows without bound is a bug.
- Heavy: idle stays near 0% CPU; walking and cleanup use the 30 fps path only while something
  moves. Item nodes are plain sprites; no per-frame work for resting items.
- Leaking content: privacy mode redacts file names, commands, results, project names and MCP
  server names in labels, tooltips and hover text.
- Off-model: all new art (icon, poses, trash can, settings design) is drawn or designed by an
  Opus subagent through the existing art pipeline (project rule).

## Approaches considered

| | Approach | Verdict |
|---|---|---|
| A | **Pure world model in `ClaudetteCore`** (items, ownership, clutter and cleanup policy, an `ActorBrain` that turns events into intents), thin SpriteKit executor in the app | **Chosen (user)** |
| B | Grow `Stage` in place, items as nodes with state | Rejected: `Stage` is already about 560 lines, sharing and cleanup rules would only be checkable by eye |
| C | Per-session item lists, sharing by lookup | Rejected: breaks "one item, read by every avatar" and tangles cleanup |

## Decided behaviour

### Items and identity

- Item kinds: `file`, `terminal`, `tool` (search, web, skill, mcp server, todo, plan, other).
- Identity: a file is its **absolute normalised path** (two files with the same name in different
  folders are two items); a terminal and every other tool call is its `tool_use_id`; a skill is its
  name. `Read`, `Edit`, `MultiEdit`, `Write` and `NotebookEdit` on the same path share one item.
- An item records owners (the set of session ids that touched it), created and last-touched time,
  position and display, and for terminals the command and the result.
- If the item for a path is on screen, it is reused wherever it was dragged to. A path with no item
  gets a new one at the asking Claudette's feet. Reuse works across sessions and sub-agents.
- An item outlives its tool call. It leaves only through cleanup (see below) or the clutter cap.
- Ownership on release: an item is collected at session end only when the ending session was its
  last owner. Shared items stay for the other sessions (my call).

### Placement and look

- New items appear at the asking actor's current position, offset and scattered. Minimum spacing
  between item centres (about one item width at the current scale); the scatter radius grows with
  the number of nearby items so a busy session spreads out instead of stacking. Always on screen.
- Labels: about 13 pt at 100% size (was about 10), one soft blurred shadow, no hard double
  shadow. Rendered once to a cached texture with `NSShadow` rather than a live effect node
  (my call, cheap at idle).
- Terminal items: about 1.3x the size of other items, first characters of the command inside as
  far as the width allows (monospaced, single line, trailing ellipsis), full command in a hover
  tooltip, and the result (exit status, duration, the end of the output if the payload carries it)
  in the tooltip once done. States: running, done, failed.
- Hover over a Claudette shows her project name below her (the last path component of the session
  cwd, or the worktree name). Hover over a file item shows its path (privacy: dots).

### Behaviour (the `ActorBrain`)

States: `idle`, `thinking`, `goingTo(item)`, `working(item, action)`, `tossing`, `perched`,
`carrying(item)`, `collecting`, `shy`. The brain is a pure function from (events, world snapshot,
actor snapshot, time) to a short queue of intents (walk to point, face, play animation, pick up,
put down, sit on window, fall). The app animates intents and reports completion or interruption.

- Thinking is a new state: from `UserPromptSubmit` (and the gaps between tool calls) until a tool
  starts or the turn stops. She wanders at a calm pace with a thought bubble and slow sparkles.
  `SessionStore` needs a `thinking` flag for this (today only tool start sets `working`).
- Reading a file: she walks to the item, plays the read animation, tosses it a little to the side
  and leaves it. The next time that file is needed she walks back.
- Sub-agents: own actors and brains, 0.55x, tethered to their parent by a leash radius (they pick
  work and wander freely inside it; they do not stack on the parent). They share the same world.
- Dragging an item while she is walking to it makes her re-target. Dropping an item between her
  and a target does not make her trip over it unless it is the cleanup scene.
- Shy dodge with an item in hand: the item rides with her, and is put down where the dodge ends.
- Perching: while walking, if a normal on-screen window's top edge is close and free of other
  windows at that spot, she may hop up and sit there. Window frames come from
  `CGWindowListCopyWindowInfo` (on-screen, layer 0, not ours, minimum size), polled at about 2 Hz
  only while she is near one or perched. Frames need no Screen Recording permission; titles do,
  and we never read them. If the top edge moves by more than a few points, or the window is gone
  or covered, she jerks (a startled drop), falls to the ground line (the usual screen-bottom
  layout row), and resumes. Setting to turn perching off (default on).

### Cleanup

- **Manual:** menubar item "Clean up". All actors collect every item (nearest-first assignment,
  several items per trip when many). A trash can slides in at a screen edge (the display holding
  most items), all collected items go in, and the can leaves when done. Clumsiness: trips, a
  dropped item chased, an over-full armful, a missed toss. Total time scales with the item count
  and is clamped to 10 to 30 s (more items means more per trip, not longer than 30 s). Work that
  arrives during the cleanup creates new items that are not collected by it; her sessions carry on
  afterwards.
- **Auto partial:** when a session enters waiting-for-you (needs approval, has a question, turn
  finished) and the items owned by that session exceed a soft limit (default 12), her Claudette
  collects the oldest items down to half the limit and returns. The same trash can scene, smaller.
  Cancelled gracefully if she gets work again (drops what she holds where she stands).
- **Session end:** she collects every item whose last owner was her session, then sleeps and
  wanders off. Sub-agent end: the mini clears its own items, then fades.
- **Clutter cap:** a hard global cap (default 80 items). Beyond it the oldest resting items are
  swept by a quick auto-tidy so memory and rendering stay bounded. Both limits are settings
  (new controls placed in the Phase 1 settings redesign).

### Phase 1 specifics

- **Hooks:** switch the plugin from `http` handlers to a `command` handler running a small
  shell script that the installer writes (executable, in the plugin directory). The script reads
  stdin, sends it with `curl` in a backgrounded subshell with short connect and total timeouts,
  discards all output, and **always exits 0** (so a closed app never produces a hook failure).
  It must return fast because command hooks block Claude Code until they exit. Existing installs
  keep working (the old `http` plugin continues to function noisily) and the Settings window
  offers the update; nothing in `~/.claude` is rewritten without the user pressing it.
- **Menubar icon:** a template-tinted Claudette (head and spark silhouette) drawn by an Opus
  subagent at 18 pt @1x/@2x, with the existing status dot (amber, blue, red). The jar and moon
  level glyph is kept only if it stays legible next to the new icon, otherwise that information
  moves to the menu's header. Builder and Opus decide, with a screenshot check.
- **Moon:** under the pointer it fades to about 25% opacity and cannot block clicks to what is
  behind it; it can be picked up and dropped anywhere; its position is persisted in settings.
- **Settings redesign:** an Opus subagent redesigns layout, grouping, labels and help text
  (front-end design principles, not a programmer's form), including controls for the new
  phase 2 and 3 settings (clutter limits, auto cleanup, perching, project name on hover).

## Constraints and risks

- Payload facts to verify against `docs/spikes/payloads.md` and a live session: the Bash
  `tool_input.command` is known; `tool_response` shape (output text, exit code) and whether it is
  present on `PostToolUse` must be confirmed. Where output is missing, the result tooltip shows
  status and duration only (graceful, not faked). `PostToolUseFailure.error` carries failures.
- Window frames for perching: not available while another Space is active (windows on other
  Spaces are absent from the on-screen list, so she drops as if the window moved); full-screen
  apps give a full-screen window with no free top edge.
- Hit-testing must expand from "avatar rectangles" to "avatars, items and the moon" without ever
  capturing clicks elsewhere (`updateMouseTransparency`).
- Command hooks spawn a process per event. Hook volume is high in busy sessions; the script
  must stay minimal (`/bin/sh`, `curl`, no extra tools).

## Phases and checkpoints (one plan)

| Phase | Content | Done when |
|---|---|---|
| 1 | hooks, menubar icon, labels, moon, settings redesign | closing the app causes no hook error; icon, labels, moon and settings verified on screen |
| 2 | world model, walking, thinking, items, terminals, sub-agents, hover name, shy carry, perch | a scripted heavy session leaves persistent, shared, draggable items; core tests green |
| 3 | cleanup (manual, auto, session end), trash can, full animation set | cleanup scene takes 10 to 30 s and leaves the screen empty; animation set screenshot-verified |

Each phase ends with `swift test` green, an on-screen check (small-region `screencapture -R`),
`ps -o %cpu,rss` idle and busy numbers, and a commit. Art (Opus subagent through
`scripts/art.sh`): phase 1 icon; phase 3 poses, trash can, and any new item art.

## Testing

Core (test-first): `WorldModel` identity and reuse (path normalisation, cross-session, sub-agent),
ownership and release rules, clutter cap and auto-partial threshold; scatter placement (spacing,
bounds, growth); `ActorBrain` intents for thinking, work, toss, shy carry, perch and fall;
`CleanupPlanner` (assignment, trips, duration clamp, interruption); the perch decision from window
frames (candidate choice, moved-window detection); the hook script (exit 0 with the port closed,
body delivered when open). App: debug switches in the existing style (`CLAUDETTE_DEBUG_CLUTTER=N`,
`CLAUDETTE_DEBUG_CLEANUP=1`, scene scripts for thinking and perching) documented in
`docs/architecture.md`, verified by screenshots.

## Left to the builder

Exact timings, spacing numbers, the walk speed curve, the scatter algorithm, the intent
vocabulary and its Swift types, the trash can design brief for Opus, text fitting for the command
inside a terminal item, the hover tooltip implementation (SpriteKit label versus a small panel),
and how to render a soft shadow cheaply.

## Calls made (mine, flag if wrong)

- Items die only through cleanup or the cap; not persisted across restarts.
- Shared items are released by their last owning session at its end.
- Transcript tailing deferred; thinking from hook events.
- Moon position persisted; perching defaults on with a setting; the trash can is reused for
  automatic partial cleanup.
- Hook script is the always-succeeds command handler; old http installs keep working until the
  user presses the update.
- Menubar icon keeps jar/moon information only if legible.
