# Claudette

A macOS menubar-only app (no Dock icon) that gives Claude Code a face: a cute, animated
Claude-mascot avatar that lives on your desktop and acts out what Claude Code is doing.

- One Claudette per running Claude Code session; sub-agents appear as mini-Claudettes.
- Sessions start (she pops in) and end (she falls asleep and leaves).
- Every tool call is a little scene: reading a file, searching, editing, running scripts, background
  shells, web, skills and MCP servers (each server gets its own labelled cartridge).
- Glanceable status: waiting for approval, Claude has a question, API/sign-in/billing/rate-limit errors.
- Usage limits as a little world: a jar of sparks (5-hour window) and a moon (weekly window), a night
  nap when you hit the limit, confetti when it lifts.
- Playful: drag her around, she dodges the pointer (hold Option to catch her), fades when she covers
  your text, scales from 50% to 200%, and shows up on every desktop.
- Everything stays on your Mac: Claude Code talks to Claudette over `127.0.0.1` only.

> Status: foundation complete with placeholder shape art. The final character art (style
> "Ink & Cel", see `design/concepts/opus/`) and the full animation set come next.

## Build and run

Requirements: macOS 14+, Xcode command line tools with Swift 6, Claude Code.

```bash
scripts/bundle.sh          # builds build/Claudette.app (ad-hoc signed, no notarisation)
open build/Claudette.app   # menubar item appears, no Dock icon
swift test                 # unit tests for ClaudetteCore
```

Claudette is not notarised (there is no paid Apple developer account behind it); you build it from
source. If macOS blocks the first launch, right-click `Claudette.app`, choose Open, and confirm.

Then open **Settings…** from the menubar item and install the Claude Code plugin and (optionally) the
status line connection. See [docs/usage.md](docs/usage.md).

## Privacy

No network access beyond `127.0.0.1`, no telemetry. Raw payload logging is off unless you set
`CLAUDETTE_LOG_EVENTS=1`. Privacy mode hides file, project and server names on screen.
The status line step edits `~/.claude/settings.json` only after you confirm, keeps a backup, and can
restore it exactly.

## Known gaps

See `docs/spikes/payloads.md`. In short: pure network disconnects are not reported by any Claude Code
hook, real mouse clicks on the overlay still need a hands-on check on each macOS version, and a few
hook payloads (`StopFailure`, `Notification`, interactive `SessionStart`) were confirmed from the
documentation but not yet from live traffic.

## Layout

- `Sources/ClaudetteCore`: pure, unit-tested logic (feed server, state machines, geometry, installers).
- `Sources/ClaudetteApp`: AppKit/SpriteKit/SwiftUI app.
- `docs/`: design (`superpowers/specs`), plan (`superpowers/plans`), `architecture.md`, `usage.md`.
- `design/concepts/`: concept art, including the Opus design sheets.
