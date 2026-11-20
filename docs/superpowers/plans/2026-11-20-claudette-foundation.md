# Claudette Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A working Claudette menubar app: real Claude Code events and usage limits flow in, sessions appear as placeholder-art characters on every desktop, and drag, hover-fade, dodge, size and limit states all work.

**Architecture:** A Swift package with a pure, unit-tested `ClaudetteCore` library (event decoding, session/limit state machines, scene mapping, placement/dodge/fade/drag maths, loopback feed server, installers) and a thin AppKit/SpriteKit `ClaudetteApp` executable (menubar, overlay panels, placeholder puppet, settings UI). Art-dependent scenes are a separate plan (see "Out of scope").

**Tech Stack:** Swift 6.2 toolchain (language mode 5), SwiftPM, AppKit, SpriteKit, SwiftUI (settings only), Network.framework, Swift Testing (`import Testing`). macOS 15.7 / Xcode 26 on this machine.

**Spec:** `docs/superpowers/specs/2026-11-20-claudette-design.md` (read it first; this plan implements everything in it that does not need final art).

## Global Constraints

- Minimum macOS 14; direct distribution, non-sandboxed, ad-hoc signed, built from source; no notarisation.
- `LSUIElement` app: menubar only, no Dock icon.
- FeedServer binds `127.0.0.1` only; request bodies capped at 1 MiB; replies instantly with an empty 2xx.
- Hooks are plugin `http` handlers with a short `timeout`; NO `async` on http handlers (not documented). Plugin hooks file shape: `{"hooks": {Event: [{"matcher"?: ..., "hooks": [{"type":"http","url":...,"timeout":2}]}]}}`.
- Status line wrapper edits only user-level `~/.claude/settings.json`, after explicit consent, with a backup; restores the original on uninstall only if the current value is still ours.
- Avatar scale 0.5 to 2.0 (default 1.0 = about 128 pt). Hover fade opacity 0.20 to 0.30 (default 0.25), default on. Dodge default on. At most 6 full-size Claudettes, extras collapse into minis with a count; sub-agent minis are 0.55x.
- Long shell: PreToolUse for Bash with no PostToolUse after 10 s, or `run_in_background` true. Stale session: sleep after 15 min of silence, remove after 60 min.
- Limits: `rate_limits.five_hour` / `seven_day`, each `used_percentage` 0-100 and `resets_at` epoch seconds, either may be absent. Low >= 80%. In limit = used >= 100 or a rate-limit StopFailure.
- Placeholder art palette: body `#E07C56`, cel shadow `#B0503A`, ink `#3A1A12`, status `?` `#7FC8F8`, `!` `#FFC94D`, error `#E5484D`, success `#9BE38B`.
- Privacy mode redacts file names, prompts, cwd/project names and MCP server names everywhere (overlay and menu).
- Format Swift with `swift format` (Xcode default); validate all external input; commits are pre-approved in this repo.

## Review Focus

- Malformed, truncated or oversized hook/status JSON, wrong content type: server stays up, returns 4xx or empty 2xx, state is untouched (Task 3, 5).
- Out-of-order events: PostToolUse with no Pre, SubagentStop for unknown agent, events for a session never started, duplicate SessionStart: no crash, no negative counts (Task 6).
- `settings.json` missing, invalid JSON, or with an existing multi-argument/quoted statusLine command: install must keep it intact; invalid JSON must be refused, never overwritten (Task 7).
- Limit windows absent, `resets_at` in the past, percentage < 0, > 100 or NaN: clamped, never crashes, no false "lifted" (Task 5).
- Display unplugged or resolution change while a Claudette stands on it; sprite larger than a tiny screen at 200% scale; pointer cornering her: she relocates, stays on screen, and dodging falls back to hover fade (Task 11, 12).

## File Structure

```
Package.swift
scripts/bundle.sh                       build + wrap Claudette.app (Info.plist LSUIElement) + ad-hoc codesign
scripts/claudette-statusline.sh         wrapper: forward stdin JSON to app, then run original command
Sources/ClaudetteCore/
  JSONValue.swift  HookEvent.swift  StatusPayload.swift  LimitsModel.swift
  SessionStore.swift  SceneMapper.swift  Settings.swift  Geometry.swift
  FeedServer.swift  PluginInstaller.swift  StatusLineInstaller.swift  EventLog.swift
Sources/ClaudetteApp/
  main.swift  AppDelegate.swift  MenuBarController.swift  OverlayController.swift
  ClaudetteScene.swift  PuppetNode.swift  PointerTracker.swift  HUD.swift  SettingsView.swift
Tests/ClaudetteCoreTests/*Tests.swift   (one file per Core source)
docs/spikes/payloads.md                 findings from Task 4
```

---

### Task 1: Package skeleton and app bundle

**Files:** Create `Package.swift`, `Sources/ClaudetteApp/main.swift`, `Sources/ClaudetteApp/AppDelegate.swift`, `Sources/ClaudetteCore/Version.swift`, `Tests/ClaudetteCoreTests/VersionTests.swift`, `scripts/bundle.sh`, `.gitignore`; Modify `README.md` (build + first-run, Gatekeeper right-click Open).

**Interfaces:** Produces `public enum ClaudetteCore { public static let version = "0.1.0" }`; products `ClaudetteCore` (library), `ClaudetteApp` (executable, depends on Core); `swiftLanguageModes: [.v5]`, platforms `.macOS(.v14)`.

- [ ] **Step 1:** Write test `versionIsSemver()` asserting `ClaudetteCore.version` matches `^\d+\.\d+\.\d+$`; run `swift test`, expect FAIL (no target).
- [ ] **Step 2:** Create the package and `Version.swift`; `AppDelegate` sets `NSApp.setActivationPolicy(.accessory)`, creates an `NSStatusItem` titled "C" with a Quit item. `main.swift` starts `NSApplication`.
- [ ] **Step 3:** `scripts/bundle.sh`: `swift build -c release`, assemble `build/Claudette.app/Contents/{MacOS,Info.plist}` with `LSUIElement` true and bundle id `app.claudette.Claudette`, then `codesign --force --sign - build/Claudette.app`.
- [ ] **Step 4:** Run `swift test` (PASS), `scripts/bundle.sh`, `plutil -extract LSUIElement raw build/Claudette.app/Contents/Info.plist` prints `true`, `open build/Claudette.app` shows a menubar "C" and no Dock icon; Quit works. Add `build/`, `.build/` to `.gitignore`.
- [ ] **Step 5:** Commit `feat: package skeleton and bundled menubar app`.

### Task 2: JSONValue and HookEvent decoding

**Files:** Create `JSONValue.swift`, `HookEvent.swift`, `Tests/.../HookEventTests.swift`.

**Interfaces:**
- Produces `public enum JSONValue: Codable, Equatable, Sendable` (`null, bool, number(Double), string, array, object`) with `subscript(key: String) -> JSONValue?` and `var stringValue: String?`, `var boolValue: Bool?`.
- Produces `public struct HookEvent: Equatable, Sendable { name, sessionID: String; cwd, transcriptPath, agentID, agentType, toolName, toolUseID, mcpServerName, notificationType, errorType: String?; toolInput: JSONValue?; raw: JSONValue }` and `static func decode(_ data: Data) throws -> HookEvent`; `enum HookDecodeError: Error { case notAnObject, missingEventName, missingSessionID }`.

- [ ] **Step 1:** Tests: `decodesPreToolUseWithMcpServer` (JSON with `hook_event_name: "PreToolUse"`, `session_id`, `tool_name: "mcp__github__create_issue"`, `mcp_server: {name:"github"}` gives `mcpServerName == "github"`); `decodesSubagentFields` (`agent_id`, `agent_type`); `decodesNotificationType`; `rejectsNonObject`, `rejectsMissingSessionID`, `ignoresUnknownFields`; `fallsBackToToolNamePrefixForMcpServer` (`mcp__memory__x` gives "memory" when `mcp_server` absent).
- [ ] **Step 2:** Run, expect FAIL. **Step 3:** Implement. `errorType` reads `error_type` (spike in Task 4 confirms the real key). **Step 4:** PASS. **Step 5:** Commit.

### Task 3: FeedServer (loopback HTTP)

**Files:** Create `FeedServer.swift`, `Tests/.../FeedServerTests.swift`.

**Interfaces:**
- Consumes `HookEvent.decode`, `StatusPayload.decode` (Task 5; until then status route returns 404 behind a `statusHandler` closure parameter, wired in Task 5).
- Produces `public enum FeedMessage: Equatable, Sendable { case hook(HookEvent), status(Data) }`; `public final class FeedServer { init(port: UInt16, onMessage: @escaping @Sendable (FeedMessage) -> Void); func start() throws; func stop(); var boundPort: UInt16? }`. Routes: `POST /hook`, `POST /status`. Pass `port: 0` for an ephemeral port in tests.

- [ ] **Step 1:** Tests using `URLSession` against `127.0.0.1:boundPort`: `postHookDeliversEvent` (200, handler got event); `malformedJSONReturns400AndNoMessage`; `bodyOver1MiBReturns413`; `getReturns405`; `unknownPathReturns404`; `serverStaysUpAfterBadRequests` (bad request then a good one still works); `bindsLoopbackOnly` (listener endpoint host is `127.0.0.1`).
- [ ] **Step 2:** FAIL. **Step 3:** Implement with `NWListener` on `127.0.0.1` (`requiredInterfaceType`/ `acceptLocalOnly = true`), a minimal HTTP/1.1 parser (request line, `Content-Length`, read to length, cap 1 MiB, 5 s read timeout per connection), reply `Content-Length: 0`. **Step 4:** PASS. **Step 5:** Commit.

### Task 4: Event log and payload spike (GATE for later details)

**Files:** Create `EventLog.swift`, `Sources/ClaudetteApp` wiring (log every `FeedMessage` as JSON line to `~/Library/Logs/Claudette/events.jsonl`), `Sources/ClaudetteCore/PluginInstaller.swift` (first cut, see Task 8 for full tests), `docs/spikes/payloads.md`.

**Interfaces:** Produces `public final class EventLog { init(url: URL); func append(_ line: Data) }` (creates the directory, appends newline-terminated lines, never throws to callers: failures are swallowed to stderr). `PluginInstaller.hooksJSON(port: Int) -> Data` and `PluginInstaller.write(to: URL, port: Int) throws` (full definition in Task 8).

- [ ] **Step 1:** Test `appendWritesOneJSONLinePerCall` and `appendCreatesMissingDirectory`. FAIL, implement, PASS.
- [ ] **Step 2:** Build/run the app (feed on port 47631). Generate a plugin dir with `PluginInstaller.write(to: <scratch>/claudette-plugin, port: 47631)`.
- [ ] **Step 3:** Run real sessions: `claude -p --plugin-dir <scratch>/claudette-plugin "read README.md, grep for 'Claudette', then run 'sleep 12'"` and one that triggers a permission prompt, a sub-agent (`Task`), a skill (`Skill` tool), an MCP tool, and a failing tool. Also try the skills-dir route by copying the plugin to `~/.claude/skills/claudette/` and starting a normal session (ask the user before touching `~/.claude`).
- [ ] **Step 4:** Write `docs/spikes/payloads.md`: which events arrived, the real key names (StopFailure error key, Skill tool input key, SessionEnd, PermissionRequest, TaskCreated), whether http hooks add noticeable latency, whether the skills-dir plugin loads, whether the status line payload carries `rate_limits` (see Task 7 step for the capture). Update Task 2/5/6 field names in code and tests to match, and note any scene that must degrade.
- [ ] **Step 5:** Commit `spike: capture real hook payloads`.

### Task 5: StatusPayload and LimitsModel

**Files:** Create `StatusPayload.swift`, `LimitsModel.swift`, tests for both; Modify `FeedServer` wiring (`/status` decodes via `StatusPayload`).

**Interfaces:**
- Produces `public struct LimitWindow: Equatable, Sendable { usedPercentage: Double /*clamped 0...100*/; resetsAt: Date }`; `public struct StatusPayload: Equatable, Sendable { sessionID: String; cwd: String?; modelDisplayName: String?; contextUsedPercentage: Double?; totalCostUSD: Double?; fiveHour: LimitWindow?; sevenDay: LimitWindow?; static func decode(_ data: Data) throws -> StatusPayload }`.
- Produces `public enum LimitKind { case fiveHour, sevenDay }`; `public enum LimitStatus: Equatable, Sendable { case unknown, fresh, low, inLimit }`; `public struct WindowState: Equatable, Sendable { status: LimitStatus; usedPercentage: Double?; resetsAt: Date? }`; `public final class LimitsModel { init(now: @escaping () -> Date); func ingest(_ p: StatusPayload); func ingestRateLimitFailure(resetsAt: Date?); func tick(); func state(_ k: LimitKind) -> WindowState; var onTransition: ((LimitKind, LimitStatus, LimitStatus) -> Void)?; var onLifted: ((LimitKind) -> Void)? }`.

- [ ] **Step 1:** StatusPayload tests: `decodesBothWindows` (23.5 / epoch 1738425600); `windowAbsentIsNil`; `clampsPercentage` (-5 gives 0, 140 gives 100, NaN window dropped); `noRateLimitsKeyGivesNilWindows`; `rejectsNonObject`.
- [ ] **Step 2:** LimitsModel tests with a fake clock: `unknownBeforeAnyData`; `freshBelow80Low80To99InLimitAt100`; `rateLimitFailureForcesInLimit`; `liftedFiresOnceWhenResetsAtPasses` (tick after `resetsAt`); `liftedFiresWhenLaterPayloadShowsLowerPercentage`; `noLiftedWhenWindowSimplyVanishesWithoutBeingInLimit`; `windowIndependence` (only sevenDay present leaves fiveHour `unknown`); `pastResetsAtInFreshPayloadIsIgnored`.
- [ ] **Step 3:** FAIL, implement, PASS. **Step 4:** Commit.

### Task 6: SessionStore state machine and SceneMapper

**Files:** Create `SessionStore.swift`, `SceneMapper.swift`, tests.

**Interfaces:**
- Consumes `HookEvent`, `StatusPayload`.
- Produces `public enum SessionPhase: Equatable, Sendable { case sleeping, idle, working, needsApproval, hasQuestion, error(ErrorKind) }`; `public enum ErrorKind: Equatable, Sendable { case api, auth, billing, rateLimit, disconnect, unknown }`; `public struct ToolActivity: Equatable, Sendable { toolUseID: String; toolName: String; mcpServer: String?; input: JSONValue?; startedAt: Date; isBackground: Bool }`; `public struct SessionState: Equatable, Sendable { id: String; cwd: String?; phase: SessionPhase; activeTools: [ToolActivity]; subagents: Set<String>; model: String?; contextUsedPercentage: Double?; startedAt: Date; lastEventAt: Date }`.
- Produces `public enum SessionChange: Equatable, Sendable { started(String), ended(String), phaseChanged(String, SessionPhase), toolStarted(String, ToolActivity), toolFinished(String, toolUseID: String, success: Bool), longShell(String, toolUseID: String), subagentStarted(String, agentID: String), subagentStopped(String, agentID: String), compacted(String), skillLoaded(String, name: String), modelChanged(String, String) }`.
- Produces `public final class SessionStore { init(now: @escaping () -> Date); func apply(_ e: HookEvent) -> [SessionChange]; func applyStatus(_ p: StatusPayload) -> [SessionChange]; func tick() -> [SessionChange]; var sessions: [String: SessionState] }`.
- Produces `public enum Scene: Equatable, Sendable { read(file: String), search, edit(file: String?), write(file: String?), shell(long: Bool, background: Bool), web, skill(name: String), mcp(server: String, tool: String), todo, plan, subagent, other(tool: String) }` and `public enum SceneMapper { static func scene(for tool: ToolActivity, now: Date) -> Scene }`.

- [ ] **Step 1:** SessionStore tests (fake clock): `sessionStartCreatesIdleSession`; `duplicateSessionStartIsIdempotent`; `eventForUnknownSessionAutoCreatesIt`; `preThenPostToolTogglesWorking`; `postWithoutPreIsIgnored`; `overlappingToolsStayWorkingUntilAllDone`; `permissionRequestSetsNeedsApprovalAndNextPostToolClears`; `elicitationNotificationSetsHasQuestion`; `stopFailureMapsErrorKinds` (rate_limit/authentication_failed/billing_error/server_error); `subagentStartStopTracksAndUnknownStopIgnored`; `longShellEmittedOnceAfter10sWithoutPost`; `backgroundBashFlagsIsBackgroundAndNeverLongShellTimer`; `staleSleepsAt15MinAndRemovedAt60`; `sessionEndRemoves`; `skillToolCallEmitsSkillLoaded`; `userPromptExpansionEmitsSkillLoaded`; `preCompactEmitsCompacted`; `statusPayloadUpdatesModelAndContext`.
- [ ] **Step 2:** SceneMapper tests: `readFileShowsBasename` (`/a/b/auth.ts` gives `read(file:"auth.ts")`); `grepGlobAreSearch`; `editWriteMultiEdit`; `bashLongAfter10s`; `mcpToolSplitsServerAndTool` (`mcp__plugin_figma_figma__get_design_context`); `unknownToolIsOther`; `missingInputDoesNotCrash`.
- [ ] **Step 3:** FAIL, implement (tool-name to scene table, `Skill` tool name and input key per `docs/spikes/payloads.md`), PASS. **Step 4:** Commit.

### Task 7: Status line wrapper and installer

**Files:** Create `scripts/claudette-statusline.sh`, `StatusLineInstaller.swift`, tests.

**Interfaces:**
- Produces `public enum StatusLineInstaller { static func install(settingsURL: URL, wrapperPath: String, stateDir: URL) throws -> InstallOutcome; static func uninstall(settingsURL: URL, wrapperPath: String, stateDir: URL) throws -> UninstallOutcome; static func status(settingsURL: URL, wrapperPath: String) -> InstallState }`, `InstallState { notInstalled, installed, overriddenByProject }` (project-level check via `projectSettingsURL: URL?` parameter), `enum InstallError: Error { case settingsNotValidJSON, wrapperMissing }`. State dir stores `settings.backup.json` and `original-statusline.json` (the original `statusLine` object or `null`).
- Wrapper contract: reads stdin fully; posts it to `http://127.0.0.1:47631/status` with `curl --max-time 1 -s -o /dev/null` in the background; if `original-statusline.json` has a command, pipes the same stdin to it and prints its output; otherwise prints an empty line. Never fails the status line (always exit 0).

- [ ] **Step 1:** Tests (temp dirs): `installOnMissingSettingsCreatesFileWithWrapper`; `installPreservesOtherKeys`; `installStoresAndWrapsExistingCommand` (command `bash -c "echo \"a b\"" --x` kept byte-for-byte in `original-statusline.json`); `installRefusesInvalidJSONAndLeavesFileUntouched`; `installIsIdempotent` (second install does not wrap our wrapper); `uninstallRestoresOriginal`; `uninstallLeavesChangedStatusLineAlone` (user changed it after install); `uninstallRemovesKeyWhenThereWasNone`; `statusReportsOverriddenByProject`.
- [ ] **Step 2:** Shell test: run the wrapper with a fake original (`cat`) and a dead port; output equals input and exit code 0; with no original, empty output and exit 0.
- [ ] **Step 3:** FAIL, implement (read, parse with `JSONSerialization`, write atomically, backup first), PASS. **Step 4:** Spike capture: with the user's consent install on a scratch `CLAUDE_CONFIG_DIR`, run a session, confirm `rate_limits` reaches `/status`; record in `docs/spikes/payloads.md`. **Step 5:** Commit.

### Task 8: Plugin installer

**Files:** Complete `PluginInstaller.swift`, tests.

**Interfaces:** `public enum PluginInstaller { static let events: [String]; static func hooksJSON(port: Int) -> Data; static func write(to dir: URL, port: Int) throws; static func install(pluginDir: URL, port: Int) throws; static func uninstall(pluginDir: URL) throws; static func isInstalled(pluginDir: URL) -> Bool; static let defaultPluginDir: URL /* ~/.claude/skills/claudette */ }`. `events` = every event in the spec's mapping table plus UserPromptExpansion, InstructionsLoaded, StopFailure, SessionStart, SessionEnd, PostToolUseFailure, PermissionRequest, Notification, Stop, TaskCreated, TaskCompleted, PreCompact, PostCompact. Each handler `{"type":"http","url":"http://127.0.0.1:<port>/hook","timeout":2}`; `.claude-plugin/plugin.json` has `name: "claudette"` and `version`.

- [ ] **Step 1:** Tests: `hooksJSONHasWrapperKeyAndAllEvents`; `everyHandlerIsHttpLoopbackWithTimeout2`; `noHandlerSetsAsync`; `writeCreatesManifestAndHooks`; `uninstallRemovesOnlyOurDirectory` (refuses a directory without our manifest); `claude plugin validate <dir>` exits 0 (shell test, skipped if `claude` is missing).
- [ ] **Step 2:** FAIL, implement, PASS. **Step 3:** Commit.

### Task 9: Settings store

**Files:** Create `Settings.swift`, tests.

**Interfaces:** `public struct ClaudetteSettings: Codable, Equatable, Sendable { scale: Double = 1.0; hoverFadeEnabled = true; hoverFadeOpacity = 0.25; dodgeEnabled = true; shyness = 0.5; privacyMode = false; focusMode = false; reduceMotion = false; launchAtLogin = false; func clamped() -> ClaudetteSettings }`; `public final class SettingsStore { init(defaults: UserDefaults); private(set) var settings: ClaudetteSettings; func update(_ f: (inout ClaudetteSettings) -> Void); var onChange: ((ClaudetteSettings) -> Void)? }`.

- [ ] **Step 1:** Tests: `defaultsMatchSpec`; `clampsScaleTo0_5...2_0`; `clampsOpacityTo0_2...0_3`; `clampsShynessTo0...1`; `persistsAcrossInstances` (separate `UserDefaults(suiteName:)`); `corruptStoredDataFallsBackToDefaults`; `onChangeFiresOnUpdate`.
- [ ] **Step 2:** FAIL, implement, PASS. **Step 3:** Commit.

### Task 10: Geometry (placement, hover fade, dodge, drag physics)

**Files:** Create `Geometry.swift`, tests.

**Interfaces:**
- `public enum Placement { static func layout(count: Int, screen: CGRect, spriteSize: CGSize, cap: Int = 6) -> (full: [CGPoint], overflow: Int) }` (non-overlapping slots along the bottom edge, extras counted in `overflow`).
- `public enum HoverFade { static func opacity(pointerInside: Bool, settings: ClaudetteSettings) -> CGFloat }` (1.0 when off or outside, `hoverFadeOpacity` when inside).
- `public enum DodgePlanner { static func nextPosition(sprite: CGRect, pointer: CGPoint, screens: [CGRect], shyness: Double, otherSprites: [CGRect]) -> CGPoint? }` (nil means cornered/no free spot, caller falls back to fade; result is always fully on one of `screens`).
- `public struct DragPhysics { init(); mutating func begin(at: CGPoint); mutating func move(to: CGPoint, dt: TimeInterval); mutating func release() -> CGVector /*velocity*/; static func glide(from: CGPoint, velocity: CGVector, screen: CGRect, spriteSize: CGSize) -> [CGPoint] }` (inertia path, friction, clamped inside screen).
- `public enum ScreenFit { static func clamp(_ origin: CGPoint, size: CGSize, to screens: [CGRect]) -> CGPoint }` (relocates when a display vanishes; a sprite larger than the screen is centred).

- [ ] **Step 1:** Tests: `layoutNeverOverlapsAndCapsAtSix`; `sevenSessionsGiveOverflowOne`; `fadeOpacityMatrix` (off, inside, outside); `dodgeMovesAwayFromPointerAndStaysOnScreen`; `dodgeAvoidsOtherSprites`; `dodgeReturnsNilInTightCorner`; `higherShynessDodgesFromFurtherAway`; `dragVelocityFromRecentMoves`; `glideStaysInsideScreenAndDecelerates`; `clampRelocatesFromRemovedDisplay`; `clampCentresOversizedSprite`; `zeroSizedScreenListDoesNotCrash`.
- [ ] **Step 2:** FAIL, implement, PASS. **Step 3:** Commit.

### Task 11: Overlay panels, placeholder puppet, all Spaces

**Files:** Create `OverlayController.swift`, `ClaudetteScene.swift`, `PuppetNode.swift`; Modify `AppDelegate.swift`.

**Interfaces:** `PuppetNode: SKNode` with parts `shadow, legs[4], bodyPivot{arms[2], body, eyes[2], mouth}, spark` drawn from SKShapeNodes in the placeholder palette, names matching the spec's rig (`leg_0..3`, `arm_L/R`, `eye_L/R`, `spark`, `shadow`); methods `idle()` (breathe + blink loop), `wake()`, `sleep()`, `setScale(_ s: CGFloat)`. `OverlayController` creates one borderless transparent `NSPanel` per `NSScreen` (`level = .statusBar`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, `ignoresMouseEvents = true`, never key/main, `hasShadow = false`) hosting an `SKView` with `ClaudetteScene`; rebuilds on `NSApplication.didChangeScreenParametersNotification`.

- [ ] **Step 1:** Implement the above; a debug menu item "Spawn test Claudette" adds a puppet.
- [ ] **Step 2:** Verify manually and record results in the commit message: no Dock icon; puppet visible over a full-screen app and on a second Space after Ctrl+Left/Right (no flicker, same position); plugging/unplugging a display relocates her; window never takes focus (typing in another app still works while clicking her area is pass-through).
- [ ] **Step 3:** Run with Activity Monitor: idle CPU < 3% with one puppet. Commit.

### Task 12: Sessions on screen, pointer behaviours

**Files:** Create `PointerTracker.swift`; Modify `ClaudetteScene.swift`, `OverlayController.swift`, `AppDelegate.swift`.

**Interfaces:** `PointerTracker` wraps `NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged])` plus a local monitor; publishes `pointer: CGPoint` (screen coords) and `onMove`. Overlay toggles `ignoresMouseEvents = false` only while the pointer is over a sprite or prop. Scene consumes `SessionChange` to add/remove puppets (`wake` on `started`, `sleep` then fade on `ended`, 0.55x minis on `subagentStarted/Stopped`, overflow badge `+N`), uses `Placement.layout`, `HoverFade`, `DodgePlanner`, `DragPhysics`, `ScreenFit` and live `ClaudetteSettings` (scale, toggles). Drag phases animate: grab (stretch, legs dangle), carry (sway by velocity), drop (squash and bounce), flick (glide with skid); a held-still hover of 2 s triggers a happy beat. Positions persist per session id for the app run.

- [ ] **Step 1:** Wire FeedServer to `SessionStore` and `LimitsModel` (main-queue hops), `tick()` every 1 s.
- [ ] **Step 2:** Verify manually: with real sessions (Task 4 plugin installed) a puppet appears per session and disappears on exit; two sessions do not overlap; seven fake sessions show 6 plus `+1`; drag, drop and flick work and animate; with dodge on she side-steps the pointer and falls back to fading when cornered; hover fade returns to full opacity on leave; toggling each setting takes effect live; size slider 50% and 200% both stay on screen.
- [ ] **Step 3:** Commit.

### Task 13: Limits HUD and menubar glyph

**Files:** Create `HUD.swift`; Modify `MenuBarController.swift`, `ClaudetteScene.swift`.

Placeholder visuals following `design/concepts/opus/D-usage-limits.png`: jar (fill = remaining 5h budget, flicker >= 80%), moon phase for the weekly window, tag `5h 88% · in 47m` / `new moon Mon 09:00` (24 h clock, local time zone), night tint + sleeping pose + "back at HH:MM" sign when `inLimit`, one-shot confetti on `onLifted`, dim jar and no moon on `unknown`. Menubar glyph shows moon phase + jar level, with a status dot (amber `!`, blue `?`, red error).

- [ ] **Step 1:** Add a debug submenu "Simulate limits" (unknown, 40%, 85%, 100%, lifted) driving `LimitsModel.ingest`.
- [ ] **Step 2:** Verify manually each state against the sheet and that real `rate_limits` data from Task 7 drives it. Commit.

### Task 14: Status scenes (placeholder) incl. errors, disconnects, skills

**Files:** Modify `ClaudetteScene.swift`, `PuppetNode.swift`.

Map `SessionPhase` and `Scene` to placeholder visuals: spark becomes `!` (amber) with periodic wave-hop for `needsApproval`, `?` blue for `hasQuestion`; error kinds each get a distinct spark glyph and text label (API, auth, billing, rate limit, offline); a recovering session plays a relief sigh; `Scene.read/search/edit/write/shell/web/skill/mcp/subagent` show a labelled coloured placeholder prop (filename visible for read; MCP shows a cartridge with the server name or initials); `skillLoaded` shows the rune-name rise; `compacted` squashes the context backpack. Privacy mode replaces names with `•••`.

- [ ] **Step 1:** Add a debug submenu "Simulate scene" listing every `Scene`, `SessionPhase` and `ErrorKind`.
- [ ] **Step 2:** Verify each by simulation and once with a real session (read, shell > 10 s, permission prompt, sub-agent, MCP, skill, failing API if reproducible). Record any scene hooks cannot detect (e.g. pure network disconnect) in `docs/spikes/payloads.md` as known gaps. Commit.

### Task 15: Menubar menu, settings window, install/uninstall

**Files:** Create `SettingsView.swift`; Modify `MenuBarController.swift`.

SwiftUI settings window: size slider (0.5-2.0), hover fade toggle + opacity slider (0.2-0.3), dodge toggle + shyness, privacy, Focus mode (hides her, stops animation), Reduce Motion, launch at login (`SMAppService.mainApp`), Claude Code plugin install/uninstall and status line install/uninstall with explicit consent dialogs showing the file to be changed, state labels from `isInstalled`/`status`, and a warning row for `overriddenByProject`. Menubar menu lists sessions (project name or `•••`), Settings, Quit.

- [ ] **Step 1:** Implement; **Step 2:** verify each control changes behaviour live, install then uninstall leaves `settings.json` byte-identical to before (diff it), and the consent dialog appears before any write. **Step 3:** Commit.

### Task 16: Hardening and docs

**Files:** Modify `README.md`; add `docs/architecture.md`, `docs/usage.md`.

- [ ] **Step 1:** Review pass for the five Review Focus items: confirm each has its test and passes (`swift test`), run a 30-minute soak with a real session and check memory and CPU stay flat.
- [ ] **Step 2:** README: what it is, requirements, build/run/first-run (including Gatekeeper), installing the plugin and status line, privacy statement (nothing leaves the machine), known gaps from the spike. **Step 3:** Commit.

## Out of scope (next plans)

1. **Art plan:** Opus brief for the final rig-ready export (per-part @2x PNGs plus anchor manifest), tool props, MCP cartridges, status scenes, per-model outfits, weekly-limit state, hat/scarf accents; then swapping `PuppetNode` placeholders for textures.
2. **Scene polish plan:** the full animation set (wake/yawn, typing, reading, celebration), clutter scaling, transcript-tailing enrichment, perching on window title bars.
