# Claudette

[![CI](https://github.com/shayanoh/Claudette/actions/workflows/ci.yml/badge.svg)](https://github.com/shayanoh/Claudette/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A macOS menubar-only app (no Dock icon) that gives Claude Code a face: a cute, animated
Claude-mascot avatar that lives on your desktop and acts out what Claude Code is doing.

- One Claudette per running Claude Code session; sub-agents are small Claudettes that roam near her
  and work on their own.
- Sessions start (she yawns and stretches) and end (she tidies up, falls asleep and leaves).
- Every tool call leaves something on your screen: a file she reads and tosses, a terminal showing
  its command, a skill, an MCP cartridge. She walks to them, they stay where they land, the same file is
  the same item for every session, and you can drag them around. She paces while Claude thinks, perches
  on window tops, carries things with her when she is shy. A busy session leaves a mess; she clears it
  up on her own when the session waits for you, and the menubar **Clean up** sends everybody to the
  trash can.
- Glanceable status: waiting for approval, Claude has a question, API/sign-in/billing/rate-limit errors.
- Usage limits as a little world: a jar of sparks (5-hour window) and a moon (weekly window), a night
  nap when you hit the limit, confetti when it lifts.
- Playful: drag her around, she dodges the pointer (hold Option to catch her), fades when she covers
  your text, scales from 50% to 200%, and shows up on every desktop.
- Everything stays on your Mac: Claude Code talks to Claudette over `127.0.0.1` only.

> Status: character art, the world of persistent items, cleanup and the full animation set are in.
> Not yet checked live: perching on a real moving window, and a long soak (see `docs/architecture.md`).

## Build and run

Requirements: macOS 14+, Xcode command line tools with Swift 6, Claude Code.
Clone with `git clone https://github.com/shayanoh/Claudette.git`.

```bash
scripts/bundle.sh          # builds build/Claudette.app (ad-hoc signed, no notarisation)
open build/Claudette.app   # menubar item appears, no Dock icon
swift test                 # unit tests for ClaudetteCore
```

Claudette is not notarised (there is no paid Apple developer account behind it); you build it from
source. If macOS blocks the first launch, right-click `Claudette.app`, choose Open, and confirm.

Then open **Settings…** from the menubar item and install the Claude Code plugin and (optionally) the
status line connection. See [docs/usage.md](docs/usage.md).

## Art

The character, props, status badges, sleep scenes and the three model outfits (Opus, Sonnet, Haiku) are
drawn in the "Ink & Cel" style and exported from `art/generate.py` to `art/export/`. The export is
committed; `scripts/art.sh` regenerates it (needs `rsvg-convert`, from `brew install librsvg`). If the
export is missing or invalid the app falls back to simple shape art.

## Privacy

No network access beyond `127.0.0.1`, no telemetry. Raw payload logging is off unless you set
`CLAUDETTE_LOG_EVENTS=1`. Privacy mode hides file, project and server names on screen.
The status line step edits `~/.claude/settings.json` only after you confirm, keeps a backup, and can
restore it exactly.

## Known gaps

See `docs/spikes/payloads.md`. In short: pure network disconnects are not reported by any Claude Code
hook, the overlay's click handling has only been hand-checked on one macOS version (15.7), and a few
hook payloads (`StopFailure`, `Notification`, interactive `SessionStart`) were confirmed from the
documentation but not yet from live traffic.

## Layout

- `Sources/ClaudetteCore`: pure, unit-tested logic (feed server, state machines, geometry, installers).
- `Sources/ClaudetteApp`: AppKit/SpriteKit/SwiftUI app.
- `docs/`: design (`superpowers/specs`), plan (`superpowers/plans`), `architecture.md`, `usage.md`.
- `design/concepts/`: concept art, including the Opus design sheets.

## License

[MIT](LICENSE)
