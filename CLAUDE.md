# Claudette

macOS menubar-only app: an animated avatar that visualises Claude Code activity.
See `README.md` for the vision, `docs/architecture.md` for how it fits together.

## Decisions

- Native Swift + SpriteKit, 2D rigged puppet; renderer stays swappable (3D cel-shaded later).
- Data: Claude Code plugin with `http` hooks -> loopback server (127.0.0.1:47631); status line wrapper
  for usage limits (`rate_limits`), context and model. No `async` on http hooks (not documented).
- Art: style "Ink & Cel" (B) + A's soft shadow; all character/visual design is produced by an
  Opus 5.5 subagent (user rule). On-screen art is the Opus-drawn export in `art/export/` (regenerate
  with `scripts/art.sh`); shape placeholders in `PuppetNode`/`Props` remain only as the fallback.
- World model (2026-11): items are objects of the stage, not props of a puppet. Rules live in
  `ClaudetteCore` (`WorldModel`, `Scatter`, `Brain`, `PerchPlanner`, `CleanupPlanner`/`ClutterPolicy`),
  unit tested; `ClaudetteApp` (`World`, `ItemNode`, `Stage`) only animates. SpriteKit sorts by global z
  (`ignoresSiblingOrder`): every Claudette needs her own z band (`Stage.bringToFront`).
- Charm first, glanceable status (approval, question, errors, limits) second.
- Distribution: build from source, ad-hoc signed, non-sandboxed, macOS 14+, no notarisation.

## Layout

- `Sources/ClaudetteCore`: pure, unit-tested logic. Keep UI out of it. `swift test` must stay green.
- `Sources/ClaudetteApp`: AppKit/SpriteKit/SwiftUI app. Verified by running it (screenshots; capture
  only a small region with `screencapture -R`, never the whole screen: it can hold private windows).
- `art/`: Opus-authored exporter (`generate.py`, `src/`) and the committed export (`export/`, manifest
  contract in `ClaudetteCore/ArtManifest.swift`); new art goes through an Opus subagent, then `scripts/art.sh`.
- `docs/superpowers/specs` (design), `docs/superpowers/plans` (plans), `docs/spikes/payloads.md`
  (real hook payloads and known gaps), `design/concepts/` (concept art).
- `scripts/bundle.sh` builds `build/Claudette.app`.

## Working rules

- Process: brainstorm -> design doc -> plan -> TDD execution. Core logic is test-first.
- Committing in this repo is pre-approved. Do not edit the user's real `~/.claude` without their
  consent; test installers with `CLAUDETTE_HOME=<scratch dir>` (see `docs/architecture.md`).
- Dev switches are environment variables (`CLAUDETTE_DEBUG_*`), listed in `docs/architecture.md`.
- Verified by the user on real hardware (2026-11-20): dragging with the real mouse, and live usage limits
  from a real interactive session, and showing over true full-screen apps. Still unverified: display
  unplug/replug, 30-min soak.
- Synthetic mouse clicks are blocked without Accessibility permission for the harness; moves work.
  `CLAUDETTE_DEBUG_DRAGTEST` exercises the drag code path instead.
- Small-region screenshots only. The screen may be locked or on the screensaver (a video wallpaper in a
  capture means the overlay cannot be seen): do not work around it, check with the user. Never
  full-screen capture.
- Swift is formatted with `swift format -i`; validate all external input.
- The macOS here is an Intel i7-7820HQ: measure CPU/battery changes with `ps -o %cpu,rss`.
