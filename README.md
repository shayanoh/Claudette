# Claudette

A macOS menubar-only app (no Dock icon) that gives Claude Code a face: a cute, animated
avatar that lives on your screen and acts out what Claude Code is doing.

- One Claudette per running Claude Code session; sub-agents appear as mini-Claudettes.
- Sessions start (wake up, yawn) and end (fall asleep in a corner, wander off-screen).
- Every tool call is a little scene: reading a file, grepping, editing, running scripts,
  background shells, waiting. Busier projects mean a more cluttered, busier Claudette.
- Glanceable status: waiting for approval, Claude has a question, long-running shell, error.
- Charm first, status second.

## Build and run

Requirements: macOS 14+, Xcode command line tools with Swift 6.

```bash
scripts/bundle.sh          # builds build/Claudette.app (ad-hoc signed, no notarisation)
open build/Claudette.app   # menubar item appears, no Dock icon
swift test                 # unit tests for ClaudetteCore
```

First run: the app is not notarised. If macOS blocks it, right-click `Claudette.app`, choose
Open, and confirm. Claudette is built from source on purpose; there are no signed releases.

## Status

Design phase. Nothing is built yet. See `docs/` for decisions and concept art.

## Planned stack

- Native Swift app shell (menubar, transparent click-through overlay windows).
- SpriteKit 2D rigged-puppet rendering, art authored with VectorCraft/AniCraft.
  Renderer kept behind a small interface so a 3D cel-shaded renderer can replace it later.
- Claude Code hooks send events over a local socket to the app; transcript tailing
  (`~/.claude/projects/**/*.jsonl`) enriches what hooks don't carry.
