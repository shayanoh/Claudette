# Claudette Scene Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. (User chose inline execution: use executing-plans.)

**Goal:** Turn the screen into a persistent world (walking Claudettes, shared draggable items, cleanup with a trash can) and ship the Phase 1 quick wins first.

**Architecture:** Pure logic in `ClaudetteCore` (`WorldModel`, `Scatter`, `ActorBrain`, `CleanupPlanner`, `ClutterPolicy`, `PerchPlanner`), unit tested. `ClaudetteApp` only animates intents and reports drags. One generic `Draggable` hit-target protocol (moon first, then items) extends the existing overlay hit-testing.

**Tech Stack:** Swift 6 package, SpriteKit, AppKit/SwiftUI, swift-testing (`@Test`), existing art pipeline (`scripts/art.sh`).

**Spec:** `docs/superpowers/specs/2026-11-20-claudette-scene-polish-design.md`

## Global Constraints

- macOS 14+, non-sandboxed, Intel i7 test machine: measure CPU/RSS with `ps -o %cpu,rss`.
- `swift test` must stay green after every task; Swift is formatted with `swift format -i <files>`.
- Core stays UI-free and test-first; app code is verified by running it (screenshots with `screencapture -R <small region>`, never the whole screen).
- All character/visual design (menubar icon, poses, trash can, settings layout) is produced by an Opus 5.5 subagent (`Agent` with `model: "opus"`), exported through `scripts/art.sh`.
- Never edit the real `~/.claude`; test installers with `CLAUDETTE_HOME=<scratch dir>`.
- Validate all external input (hook bodies, window frames, settings); idle CPU stays near 0.
- Committing in this repo is pre-approved. Commit message trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Caps from the spec: items hard cap 80, per-session soft limit 12 (auto cleanup down to 6), cleanup 10-30 s, label about 13 pt, terminal item 1.3x, minis 0.55x.

## Review Focus

- File paths: relative, `..`, symlink, trailing slash and same-basename-different-folder must resolve to the right item (Task 8).
- Hook script with the port closed, a 1 MiB body, quotes/newlines/unicode in the body: exit 0, returns in well under 1 s, writes nothing to stdout/stderr (Task 1).
- An item dragged off-screen, onto another display, or left on a display that is unplugged: clamped back onto a screen (Tasks 4, 11).
- A busy session (hundreds of tool calls): item count never exceeds the cap, frame rate returns to idle afterwards (Tasks 8, 11).
- A session or sub-agent ends while holding an item or mid-cleanup: no orphaned node, no item stuck "held" (Tasks 10, 16, 17).

---

# Phase 1: quick wins

### Task 1: Fail-silent hooks (command script instead of http)

**Files:**
- Modify: `Sources/ClaudetteCore/PluginInstaller.swift`
- Test: `Tests/ClaudetteCoreTests/PluginInstallerTests.swift`

**Interfaces:**
- Produces: `PluginInstaller.hookScript(port: Int) -> String`; `PluginInstaller.hooksJSON(port: Int, scriptPath: String) -> Data` (handler `{"type":"command","command":"<single-quoted scriptPath>","timeout":5}`); `PluginInstaller.isLegacy(pluginDir: URL) -> Bool` (installed and its hooks.json contains `"type" : "http"`); `write(to:port:)` also writes `hooks/post.sh` with mode 0o755.

- [ ] **Step 1: Rewrite the tests that assume http.** Replace `everyHandlerIsHttpLoopbackWithTimeout2` with `everyHandlerIsTheCommandScript` (type `command`, command contains `/hooks/post.sh`, timeout 5) and `reinstallUpdatesPortInPlace` to read `hooks/post.sh` and assert `:2222/hook` present, `:1111/hook` absent. `hooks(port:)` helper calls `hooksJSON(port:scriptPath: "/x/hooks/post.sh")`.
- [ ] **Step 2: Add tests** `scriptExitsZeroWhenPortClosed` (write plugin to temp dir with port 1, run `/bin/sh post.sh` with a JSON body containing quotes, newline and emoji on stdin; assert status 0, stdout and stderr empty, elapsed < 1.5 s), `scriptExitsZeroOnHugeBody` (1 MiB body, same asserts), `scriptDeliversBodyWhenServerListens` (start `FeedServer` the way `FeedServerTests` does on a free port, run the script, assert the handler received the body within 2 s), `scriptIsExecutable` (mode & 0o111 != 0), `legacyHttpInstallIsDetected` (write a hooks.json with an http handler into an installed plugin dir: `isLegacy` true; after `install` false), `scriptQuotesPathsWithSpaces` (`hooksJSON` with a path containing a space and a `'`: the command string round-trips through `/bin/sh -c` to the right path, test by running `printf %s` equivalent: use path to a temp script that echoes ok).
- [ ] **Step 3: Run `swift test --filter PluginInstallerTests`.** Expected: FAIL (missing symbols).
- [ ] **Step 4: Implement.** `hookScript(port:)` returns: `#!/bin/sh`, `body=$(cat)`, then a backgrounded subshell `( printf '%s' "$body" | curl -s -m 2 --connect-timeout 1 -X POST -H 'Content-Type: application/json' --data-binary @- "http://127.0.0.1:<port>/hook" >/dev/null 2>&1 & ) >/dev/null 2>&1`, then `exit 0`. `write` emits the script and `chmod`s it; single-quote the path by replacing `'` with `'\''`.
- [ ] **Step 5: Run `swift test`.** Expected: all PASS. Also run `claudePluginValidatePasses` (runs when the `claude` CLI exists).
- [ ] **Step 6: Commit** `feat: hooks never fail (command script posts in the background, always exits 0)`.

### Task 2: Soft shadowed, larger labels

**Files:**
- Create: `Sources/ClaudetteApp/LabelTexture.swift`
- Modify: `Sources/ClaudetteApp/Props.swift:58-74` (`label`), `Sources/ClaudetteApp/PropNode+Art.swift` (callers pass sizes)

**Interfaces:**
- Produces: `enum LabelTexture { static func texture(_ text: String, size: CGFloat, mono: Bool = false) -> SKTexture }` cached by `(text, size, mono)` in an `NSCache`; text white, one `NSShadow` (offset (0,-1.5), blur 4, ink at 0.85 alpha), padded so the shadow is not clipped. `PropNode.label(_:y:size:)` default size becomes 13 and uses an `SKSpriteNode` from this texture (anchor top).

- [ ] **Step 1: Implement `LabelTexture`** drawing the attributed string into an `NSImage` (scale 2) via `NSImage(size:flipped:)` drawing handler, then `SKTexture(image:)`.
- [ ] **Step 2: Replace the two-label outline in `PropNode.label`** with one sprite; default `size` 13; keep the `privacy`/`shorten` helpers untouched.
- [ ] **Step 3: Verify on screen:** `CLAUDETTE_DEBUG_SPAWN=1 CLAUDETTE_DEBUG_SCENES=read,edit,mcp swift run`, screenshot a 400x300 region over a light and a dark wallpaper; labels readable, a single soft shadow, no hard double edge.
- [ ] **Step 4: Run `swift test`; commit** `feat: bigger item labels with one soft shadow`.

### Task 3: `Draggable` hit targets, moon fade and drag

**Files:**
- Create: `Sources/ClaudetteApp/Draggable.swift`
- Modify: `Sources/ClaudetteApp/Stage.swift` (`updateMouseTransparency`, `pointerMoved`, `mouseDown/Dragged/Up`), `Sources/ClaudetteApp/HUD.swift` (`MoonNode`, `LimitsHUD.refresh`), `Sources/ClaudetteCore/Settings.swift`
- Test: `Tests/ClaudetteCoreTests/SettingsTests.swift`

**Interfaces:**
- Produces (Core): `ClaudetteSettings.moonX: Double?`, `moonY: Double?` (fraction 0...1 of the main display's visible frame, centre of the moon; `clamped()` fits to 0...1 and drops half-set pairs; decode keeps defaults when missing).
- Produces (App): `protocol Draggable: AnyObject { var hitRect: CGRect { get } /* global screen coords */; func pointerEntered(); func pointerExited(); func dragBegan(at: CGPoint); func dragMoved(to: CGPoint); func dragEnded(at: CGPoint) }`; `Stage.draggables: [Draggable]` (settable; checked after actors, so avatars win). Phase 2 items conform to this.

- [ ] **Step 1: Core tests** in `SettingsTests`: `moonPositionClampsToUnitSquare`, `halfSetMoonPositionIsDropped`, `oldStoredSettingsKeepMoonDefault`. Run: FAIL. Implement the fields and `clamped()`. Run: PASS.
- [ ] **Step 2: Stage.** `updateMouseTransparency` also captures when the pointer is inside any `draggable.hitRect` (inset -4); `pointerMoved` calls `pointerEntered/Exited` on transitions; `mouseDown` picks a draggable only if no avatar is hit; `mouseDragged/Up` forward to the active draggable; keep `dragging` for avatars separate.
- [ ] **Step 3: Moon.** `MoonNode` (or a wrapper owned by `LimitsHUD`) conforms to `Draggable`: `hitRect` from its scene position and radius (about 44x60 pt including label), `pointerEntered` runs `fadeAlpha(to: 0.25, 0.15)` with key `fade`, `pointerExited` back to 1; while fading it still captures the pointer so it can be grabbed (hover fade must not make it click-through, document why). Dragging moves it, clamped to the visible frame of its display; `dragEnded` writes `moonX/moonY` through `SettingsStore.update`. `LimitsHUD.refresh` places it from settings fractions, defaulting to the current top-right corner.
- [ ] **Step 4: Verify on screen:** hover fades, drag moves it, quit and relaunch keeps the position; moon off-screen after unplugging a display is clamped back (simulate by setting `moonX` to 5 in defaults: it must appear inside).
- [ ] **Step 5: `swift test`; commit** `feat: moon fades under the pointer, draggable, position remembered`.

### Task 4: Claudette menubar icon (Opus art)

**Files:**
- Modify: `art/generate.py` (+ `art/src/`), `art/export/` (regenerated), `Sources/ClaudetteApp/HUD.swift` (`MenuBarGlyph`), `Sources/ClaudetteApp/AppDelegate.swift:19-25`
- Test: manifest validation via `scripts/art.sh`

**Interfaces:**
- Produces: asset `menubar` (single-colour black on transparent, 18 pt tall, @2x PNG, alpha-only so `isTemplate = true` tints it) in the manifest with `tint: false`; `MenuBarGlyph.image(five:seven:dot:)` composites that icon plus the status dot, and keeps the small jar/moon marks only if they stay legible at menubar size (otherwise moves that info to the menu header line "5h 88% · wk 40%"). Falls back to the current drawn glyph when the asset is missing.

- [ ] **Step 1: Brief an Opus subagent** (`Agent`, `model: "opus"`) with the locked "Ink & Cel" style, `design/concepts/opus/DESIGN-NOTES.md`, the template-image requirements above, and the instruction to add the `menubar` export to `art/generate.py` and show 18 pt and 36 px renders on light and dark menubars. Review the PNG yourself (Read the image).
- [ ] **Step 2: Run `scripts/art.sh`.** Expected: validation OK including the new asset.
- [ ] **Step 3: Wire** `MenuBarGlyph` and drop `item.button?.title = "C"`; set `image.isTemplate = true` for the icon, draw the dot non-template by compositing (dot must keep its colour: draw icon template-tinted via `labelColor`, as the current code does with `NSColor.labelColor`).
- [ ] **Step 4: Verify** with `screencapture -R` on the menubar strip (light and dark appearance); `swift test`; commit `feat: Claudette menubar icon`.

### Task 5: Settings window redesign (Opus design)

**Files:**
- Modify: `Sources/ClaudetteApp/SettingsView.swift` (view only; `SettingsModel` logic stays)

**Interfaces:**
- Consumes: `SettingsModel` (existing bindings and install state); adds `pluginNeedsUpdate: Bool` (`PluginInstaller.isLegacy(pluginDir: Paths.pluginDir)`) with `updatePlugin()` calling the existing install path.
- Produces: a layout with sections that Phase 2/3 tasks extend ("Behaviour", "Clutter") without redesign.

- [ ] **Step 1: Brief an Opus subagent** with the current `SettingsView.swift`, the settings model, the macOS 14 target, and the complaint: no labels, programmer layout, missing help text. Required: grouped sections (Appearance, Pointer, Privacy and comfort, Claude Code connection), every control labelled with a one-line explanation, value readouts on sliders, an "Update" button when `pluginNeedsUpdate`, sensible window size, no dead controls (Phase 2/3 controls are added later, not stubbed).
- [ ] **Step 2: Add `pluginNeedsUpdate`/`updatePlugin()`** to `SettingsModel` (in `CLAUDETTE_HOME` sandbox the update path must not touch the real home: it already uses `Paths.pluginDir`).
- [ ] **Step 3: Verify:** `CLAUDETTE_HOME=<scratch> swift run`, open Settings, screenshot the window region; check every control still changes behaviour; install then update then uninstall leaves the scratch tree as expected.
- [ ] **Step 4: Phase 1 close:** `swift test`, `ps -o %cpu,rss` idle check, update `docs/usage.md` (hooks are silent when closed, moon, menubar icon) and `docs/architecture.md` (`Draggable`, `LabelTexture`, hook script); commit `feat: settings redesign` and `docs: phase 1`.

---

# Phase 2: the world model

### Task 6: Payload spike and thinking state

**Files:**
- Modify: `docs/spikes/payloads.md`, `Sources/ClaudetteCore/SessionStore.swift`, `Sources/ClaudetteCore/HookEvent.swift` (if fields are needed)
- Test: `Tests/ClaudetteCoreTests/SessionStoreTests.swift`

**Interfaces:**
- Produces: `SessionChange.thinkingChanged(String, Bool)`; `SessionState.isThinking: Bool` (true from `UserPromptSubmit` and after a tool finishes with no tool active, until a tool starts, `Stop`, `StopFailure` or `SessionEnd`); `SessionChange.toolResult(String, toolUseID: String, ToolResult)` with `public struct ToolResult: Equatable, Sendable { var success: Bool; var durationMs: Int?; var summary: String? }` where `summary` is at most 200 characters (end of output/error) or nil.

- [ ] **Step 1: Spike:** run a real session with `CLAUDETTE_LOG_EVENTS=1` (Bash `ls`, a failing Bash, Read), record the `tool_response` shape for Bash and Read in `docs/spikes/payloads.md`. Decide what `summary` can honestly contain; if output is absent, summary is nil.
- [ ] **Step 2: Tests:** `userPromptSubmitStartsThinking`, `toolStartEndsThinkingAndToolFinishRestartsIt`, `stopEndsThinking`, `thinkingFlagIsPerSession`, `bashResultCarriesDurationAndSummary`, `missingToolResponseGivesNilSummary`, `summaryIsTruncatedTo200Characters`. Run: FAIL.
- [ ] **Step 3: Implement** in `SessionStore`; **Step 4: `swift test`; commit** `feat: thinking state and tool results from hooks`.

### Task 7: Item identity and `WorldModel`

**Files:**
- Create: `Sources/ClaudetteCore/WorldModel.swift`
- Test: `Tests/ClaudetteCoreTests/WorldModelTests.swift`

**Interfaces:**
- Produces: `public enum ItemKind: Equatable, Sendable { case file, terminal, tool(ToolScene) }`; `public struct ItemID: Hashable, Sendable { public let raw: String }` with `static func file(path: String, cwd: String?) -> ItemID` (absolute, `..` and symlinks resolved via `standardizedFileURL.resolvingSymlinksInPath()`, relative paths resolved against `cwd`, trailing slash stripped), `static func tool(useID: String)`; `public struct Item: Equatable, Sendable { id, kind, label: String, owners: Set<String>, createdAt, lastTouched: Date, position: CGPoint?, display: UInt32?, terminal: TerminalInfo? }` with `public struct TerminalInfo: Equatable, Sendable { command: String; state: running/done/failed; result: ToolResult? }`; `public struct WorldModel { var hardCap = 80; mutating func touch(for session: String, tool: ToolActivity, scene: ToolScene, now: Date) -> (Item, isNew: Bool, evicted: [ItemID]); mutating func finish(toolUseID:result:); mutating func move(_ id: ItemID, to: CGPoint, display: UInt32); func items(ownedBy: String) -> [Item]; mutating func releaseSession(_ id: String) -> [ItemID] /* items whose last owner left */; mutating func remove(_ ids: [ItemID]); var all: [Item] }`.

- [ ] **Step 1: Tests:** `sameFileFromTwoSessionsIsOneItem`, `sameBasenameInDifferentFoldersAreTwoItems`, `relativePathResolvesAgainstCwd`, `dotDotAndTrailingSlashNormalise`, `symlinkResolvesToTarget`, `readEditWriteOnSamePathShareItem`, `terminalsAreOneItemPerToolUseID`, `releaseSessionKeepsSharedItems`, `releaseSessionReturnsOnlySoleOwnerItems`, `capEvictsOldestRestingItemsNotTerminalsRunning`, `touchRefreshesLastTouchedAndOwners`, `finishSetsTerminalStateAndResult`. Run: FAIL.
- [ ] **Step 2: Implement.** Eviction order: oldest `lastTouched` first, never an item whose terminal is running.
- [ ] **Step 3: `swift test`; commit** `feat: WorldModel with shared item identity`.

### Task 8: Scatter placement

**Files:**
- Create: `Sources/ClaudetteCore/Scatter.swift`
- Test: `Tests/ClaudetteCoreTests/ScatterTests.swift`

**Interfaces:**
- Produces: `public enum Scatter { static func spot(near: CGPoint, existing: [CGPoint], itemSize: CGSize, screens: [CGRect], seed: UInt64) -> CGPoint }` (deterministic for a seed; at least `itemSize.width` between centres when room exists; radius grows with how many existing points are within 200 pt; result is fully on one of `screens`; never returns NaN for empty or zero-size inputs).

- [ ] **Step 1: Tests:** `spotKeepsMinimumSpacing`, `radiusGrowsWithCrowding`, `alwaysFullyOnScreen`, `deterministicPerSeed`, `emptyScreensReturnsNearClamped`, `fullScreenOfItemsStillReturnsAPointOnScreen` (no infinite loop). FAIL, implement (rejection sampling on a spiral, bounded attempts, falls back to the least-crowded candidate), PASS, commit `feat: scatter placement for items`.

### Task 9: `ActorBrain`

**Files:**
- Create: `Sources/ClaudetteCore/ActorBrain.swift`
- Test: `Tests/ClaudetteCoreTests/ActorBrainTests.swift`

**Interfaces:**
- Consumes: `Item`, `ItemID`, `SessionState.isThinking` (Task 6).
- Produces: `public enum Intent: Equatable, Sendable { case walk(to: CGPoint), face(CGPoint), play(Move), pickUp(ItemID), putDown(at: CGPoint), toss(ItemID, to: CGPoint), sit(onWindow: Int), fall, wait(TimeInterval) }`; `public enum Move: String, Sendable { case think, read, typing, search, shrug, celebrate, startled, yawn, stretch, trip }`; `public struct BrainActor: Sendable { var position: CGPoint; var holding: ItemID?; var isSubagent: Bool; var anchor: CGPoint? /* parent position */; var leash: CGFloat }`; `public struct Brain { mutating func plan(event: BrainEvent, actor: BrainActor, world: [Item], screens: [CGRect], now: Date, rng: inout some RandomNumberGenerator) -> [Intent] }` with `BrainEvent`: `.toolStarted(Item, isNew: Bool)`, `.thinkingChanged(Bool)`, `.idle`, `.dodge(to: CGPoint)`, `.itemMoved(ItemID)`, `.sessionEnded`.

- [ ] **Step 1: Tests:** `newFileItemMakesActorReadInPlaceThenToss`, `existingItemFarAwayMakesActorWalkThereFirst`, `itemMovedWhileWalkingRetargets`, `thinkingProducesWanderPointsOnScreen`, `thinkingStopsWhenToolStarts`, `subagentWanderStaysInsideLeash`, `shyDodgeWhileHoldingPutsItemDownAtEndPoint`, `sessionEndWhileHoldingPutsItemDown`, `walkTargetsAreAlwaysOnScreen`. FAIL.
- [ ] **Step 2: Implement** as a pure planner (no timers; the app drives time). **Step 3: PASS; commit** `feat: ActorBrain intent planner`.

### Task 10: Item nodes and the stage world

**Files:**
- Create: `Sources/ClaudetteApp/ItemNode.swift`, `Sources/ClaudetteApp/World.swift`, `Sources/ClaudetteApp/Walker.swift`
- Modify: `Sources/ClaudetteApp/Stage.swift` (remove `props`, `propSlots`, `layoutProps`, cable), `Sources/ClaudetteApp/Props.swift`, `Sources/ClaudetteApp/AppModel.swift`

**Interfaces:**
- Consumes: Tasks 2, 3, 7, 8, 9.
- Produces: `ItemNode: SKNode` (wraps `PropNode` art; conforms to `Draggable`; terminal variant 1.3x with monospaced command text inside, fitted with trailing ellipsis; `setResult`), `World` (owns the `WorldModel` and the item nodes per display scene, runs the brain per actor, executes intents through `Walker`, feeds `Stage.draggables`), `Walker` (moves a puppet along points with a code-driven leg swing, facing, speed about 140 pt/s at 100%, interruptible). Items are parented to the scene, never to a puppet. The MCP cable is removed.

- [ ] **Step 1: Implement in this order, running the app after each:** (a) items materialise at the actor's feet via `Scatter` and stay; (b) the actor walks to a new tool's item, plays the scene animation, tosses it; (c) item drag with re-target; (d) sharing: second session reading the same path walks to the existing item; (e) terminal item size, command text, hover tooltip (`SKLabelNode`-based small label near the item, privacy dots); (f) cap handling (evicted items fade out).
- [ ] **Step 2: Hit-test:** items register in `Stage.draggables`; verify clicks outside items and avatars still pass through (click a window behind an item-free area).
- [ ] **Step 3: Verify on screen with debug switches** (`CLAUDETTE_DEBUG_CLUTTER=N` adds N fake items, new; document in `docs/architecture.md`): screenshot spacing/readability, drag an item, `ps -o %cpu,rss` with 80 items idle and while walking.
- [ ] **Step 4: `swift test`; commit** `feat: persistent shared draggable items; Claudette walks to them`.

### Task 11: Thinking, project name, shy carry, independent sub-agents

**Files:**
- Modify: `Sources/ClaudetteApp/Stage.swift`, `Sources/ClaudetteApp/World.swift`, `Sources/ClaudetteApp/PuppetNode.swift`, `Sources/ClaudetteApp/PuppetNode+Art.swift`

**Interfaces:**
- Produces: `PuppetNode.think(on: Bool)` (thought bubble with slow sparkles; the walk comes from the brain's wander), `Actor.projectName` label shown on hover (privacy dots), `Actor.held: ItemNode?` carried in the hands and shown with the puppet during dodge/drag, sub-agents as real `Actor`s (`isSubagent`, scale 0.55) tethered to the parent by `leash` (about 260 pt at 100%).

- [ ] **Step 1: Thinking:** `thinkingChanged(true)` starts wandering plus bubble; stop on tool start. **Step 2: Hover name:** a label under the puppet on hover (reuses `LabelTexture`). **Step 3: Shy carry:** dodge with `held` item moves it with her, `putDown` at the end spot. **Step 4: Sub-agents:** replace `addMini` with sub-actors; they work on shared items.
- [ ] **Step 5: Verify:** scripted scene with a parent plus two sub-agents; a dodge while holding a file; screenshots; `swift test`; commit `feat: thinking walk, project hover name, shy carry, roaming sub-agents`.

### Task 12: Perching on windows

**Files:**
- Create: `Sources/ClaudetteCore/PerchPlanner.swift`, `Sources/ClaudetteApp/WindowTracker.swift`
- Test: `Tests/ClaudetteCoreTests/PerchPlannerTests.swift`
- Modify: `Sources/ClaudetteCore/Settings.swift` (`perchEnabled = true`), `Sources/ClaudetteApp/World.swift`

**Interfaces:**
- Produces: `public struct WindowFrame: Equatable, Sendable { number: Int; frame: CGRect; layer: Int; ownerPID: Int32 }`; `public enum PerchPlanner { static func candidate(near: CGPoint, windows: [WindowFrame], ownPID: Int32, minSize: CGSize, reach: CGFloat) -> (window: Int, spot: CGPoint)?  /* top edge not covered at spot, layer 0, not own, big enough */; static func moved(perched: WindowFrame, now: [WindowFrame], tolerance: CGFloat) -> Bool /* gone, covered at spot, or top edge moved more than tolerance */ }`; `WindowTracker.poll() -> [WindowFrame]` from `CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)` using bounds only (no titles, no Screen Recording permission), converted to the same global coordinates as the stage, polled at about 2 Hz only while an actor is near a window or perched.

- [ ] **Step 1: Tests:** `picksNearestUncoveredTopEdge`, `ignoresOwnAndTinyAndNonZeroLayerWindows`, `coveredTopEdgeIsNotACandidate`, `movedBeyondToleranceCountsAsMoved`, `goneWindowCountsAsMoved`, `fullScreenWindowHasNoFreeEdge`. FAIL, implement, PASS.
- [ ] **Step 2: Setting test** `perchDefaultsOn` and clamp; **Step 3: App:** `sit(onWindow:)` hop-up, `fall` jerk (startled jolt, drop to the screen-bottom layout row, short shake), resume wandering. Verify by dragging a real window under her and away; commit `feat: perching on window top edges with the chair-pulled jerk`.

### Task 13: Phase 2 close

- [ ] **Step 1:** Add the Phase 2 settings controls into the redesigned window (perching on/off, show project name on hover, clutter hard cap slider 20...120), with `ClaudetteSettings` fields, clamping tests and live apply. **Step 2:** heavy-session scripted run (`CLAUDETTE_DEBUG_CLUTTER=80`, 3 sessions, sub-agents), CPU/RSS numbers into `docs/architecture.md`; document the new switches. **Step 3:** `swift test`; commit `docs: phase 2`.

---

# Phase 3: cleanup and the full animation set

### Task 14: `CleanupPlanner` and `ClutterPolicy`

**Files:**
- Create: `Sources/ClaudetteCore/Cleanup.swift`
- Test: `Tests/ClaudetteCoreTests/CleanupTests.swift`
- Modify: `Sources/ClaudetteCore/Settings.swift` (`autoCleanup = true`, `clutterSoftLimit = 12` clamped 4...40)

**Interfaces:**
- Produces: `public struct CleanupAssignment: Equatable, Sendable { actor: String; trips: [[ItemID]] }`; `public enum CleanupPlanner { static func plan(items: [Item], actors: [String: CGPoint], can: CGPoint, now: Date) -> (assignments: [CleanupAssignment], duration: TimeInterval) }` (nearest-first assignment, up to 3 items per trip, duration clamped 10...30 s: more items means bigger armfuls, not longer); `public enum ClutterPolicy { static func autoTidy(session: String, owned: [Item], phase: SessionPhase, softLimit: Int, enabled: Bool) -> [ItemID] /* oldest first, down to softLimit/2; only when the phase is needsApproval, hasQuestion or idle-after-Stop */; static func sessionEnd(session: String, items: [Item]) -> [ItemID] /* sole-owner items */ }`.

- [ ] **Step 1: Tests:** `durationIsClampedTo10And30`, `everyItemAssignedExactlyOnce`, `nearestActorGetsNearestItems`, `manyItemsMeansBiggerTripsNotLongerTime`, `noActorsMeansNoAssignments`, `autoTidyOnlyWhenWaitingAndOverLimit`, `autoTidyLeavesHalfTheLimit`, `autoTidyDisabledReturnsEmpty`, `sessionEndReturnsOnlySoleOwnerItems`, `runningTerminalsAreNeverAutoTidied`. FAIL, implement, PASS, commit `feat: cleanup planner and clutter policy`.

### Task 15: Trash can, clumsy cleanup scene, menubar action (Opus art)

**Files:**
- Modify: `art/generate.py`, `art/export/`, `Sources/ClaudetteApp/World.swift`, `Sources/ClaudetteApp/AppDelegate.swift` (menu item "Clean up"), `Sources/ClaudetteApp/PuppetNode.swift`
- Create: `Sources/ClaudetteApp/CleanupScene.swift`

**Interfaces:**
- Consumes: Task 14. Produces: art assets `trash_can`, `trash_lid`, `puppet` variants for carrying (`arm_L.carry`, `arm_R.carry`) from an Opus brief; `CleanupScene.run(items:actors:can:reduceMotion:completion:)` (can slides in at the edge of the display with most items, assigned actors fetch items, clumsy beats: a trip and chase, a dropped armful, a missed toss that bounces off the rim, items vanish into the can, can slides out; honours Reduce Motion by shortening to a quick fade-collect); triggers: menu "Clean up" (all actors), `ClutterPolicy.autoTidy` on entering a waiting phase (smaller scene, same can), `ClutterPolicy.sessionEnd` before the end-of-session nap and sub-agent fade; cancel safely when a session gets work again (item in hand is put down where she stands).

- [ ] **Step 1: Opus art brief and `scripts/art.sh`.** **Step 2: Scene implementation** against the planner output with timings scaled to the planned duration. **Step 3: Verify:** `CLAUDETTE_DEBUG_CLUTTER=60 CLAUDETTE_DEBUG_CLEANUP=1` leaves the screen empty in 10-30 s; session end with items; cancellation mid-scene; no orphan nodes (count children of the overlay scenes before and after). **Step 4: `swift test`; commit** `feat: cleanup scene with trash can; manual, automatic and end-of-session`.

### Task 16: Full animation set

**Files:**
- Modify: `art/generate.py` (new pose variants from Opus), `Sources/ClaudetteApp/PuppetNode.swift`, `Sources/ClaudetteApp/PuppetNode+Art.swift`

**Interfaces:**
- Produces: `PuppetNode` methods `yawn()`, `stretch()`, `typing(on:)`, `readScan()`, `searchHop()`, `pickUp()`, `toss()`, `trip()`, `celebrate()`, `shrug()`, `startled()`, `perchSit()` mapped from `Move` (Task 9) in `World`; `wake()` plays yawn then stretch; `Stop` plays celebrate; interrupt (`is_interrupt`) plays startled then shrug.

- [ ] **Step 1: Opus brief** for the missing poses/variants (list above) following the manifest contract; `scripts/art.sh`. **Step 2: Implement each animation** with code-driven timing over the variants; Reduce Motion falls back to static poses. **Step 3: Verify** each with `CLAUDETTE_DEBUG_SCENES` (extend the scene list) and a screenshot sequence; commit `feat: full animation set`.

### Task 17: Phase 3 close

- [ ] **Step 1:** Add the Phase 3 controls to the settings window (auto cleanup on/off, soft limit 4...40, "Clean up now" button) with clamping tests. **Step 2:** 30-minute soak with real sessions: memory and CPU flat, item count bounded; record in `docs/architecture.md`; update `README.md` (feature list), `docs/usage.md` (Cleanup, perching, dragging items), `CLAUDE.md` (decisions changed: items are world objects). **Step 3:** `swift test`; run `/code-review`; commit `docs: scene polish complete`.
