# Claudette

macOS menubar-only app: an animated avatar that visualises Claude Code activity.
See `README.md` for the vision.

## Decisions so far

- Native Swift + SpriteKit, 2D rigged puppet. Renderer stays behind a swappable interface.
- Data source: Claude Code hooks -> local socket; transcript JSONL tailing as enrichment.
- Priority: charm and visual quality first, glanceable status (approval, question,
  long-running shell, error) second.
- Art tools: VectorCraft / AniCraft / PhotoCraft MCPs; Blender at
  `/Applications/Blender.app/Contents/MacOS/Blender` (not on PATH) for 3D.

## Working rules

- Process: brainstorm -> design doc in `docs/superpowers/specs/` -> plan -> build.
  Nothing is built before the design doc is approved.
- Concept art and other throwaway work lives in `design/concepts/`.
- Committing in this repo is pre-approved by the user.
- Format Swift with `swift-format`/Xcode defaults; validate input and handle errors,
  especially for anything parsing hook payloads or transcripts.
