# Scene polish: rulings, review outcome and open items (2026-11-20/21)

Kept from the executor's ledger (the working ledger itself is git-ignored scratch).

## Rulings made while executing the plan

- Worked on `main` (no worktree): all earlier history is there and committing is pre-approved.
- Menubar icon: the jar and moon glyph was dropped (illegible next to the silhouette); limit levels are the
  first line of the menu. Cost if wrong: limits are less glanceable in the bar.
- `WorldModel.touch` takes `cwd` and reads the path from `tool.input` (`ToolScene` only has the basename);
  `releaseSession` drops ownership and returns ownerless ids but keeps them until `remove` (cleanup collects).
- `Brain`: plain struct with config; `BrainActor.task` lets a dragged item re-target her;
  `toolStarted` carries the `Move`; `plan()` takes no clock. Every tool visit is
  `[walk?, face, pickUp, play, toss]`: she holds the item while working (so a shy dodge carries it) and
  tosses it after, revisits included. Cost if wrong: items drift more on revisits.

## Whole-branch review (fresh Opus reviewer) and what was done

Critical and important findings were fixed in one pass (commit "fix: review findings"):
C1 cleanup bookkeeping skipped when a cleanup ended by perch fall, `release`, `removeSub` (ghost
Claudette, permanent can, frozen actor); I1 walks overwrote drags and dodges; I2 thinking pacing ran one
batch at most; I3 auto tidy-up almost never fired; I4 a resumed session id lost its Claudette while she
was leaving; I5 items stranded on an unplugged display; I6 one item node held by two actors or revived
after being trashed (invisible, click-eating); I7 privacy mode did not hide items already on screen.
Also fixed: M8 the name tag now follows drags and dodges.
These App-side fixes have no unit tests (ClaudetteApp is not unit tested); the leaving/resume flow and the
cleanup were exercised against the real feed (`CLAUDETTE_DEBUG_CLEANUP=1` traces).

## Deferred minors (not fixed; for the user to decide)

- M1 `ItemID.file` resolves symlinks only for files that exist, so a Write that creates a file and a later
  Read can become two items when the path goes through a symlink or `/private/...`; it also does synchronous
  filesystem I/O on the main thread per file tool call.
- M2 shells whose `PostToolUse` never arrives stay "running…" forever (never evicted or auto-tidied).
- M3 a held item's `display` is stale after riding across displays (partly fixed: reparenting now compares scenes).
- M4 cleanup speed-up is uncapped (120 items, one Claudette: ~15-20x).
- M5 sub-agents ignore Reduce Motion and being dragged while roaming.
- M6 dragging a sitting Claudette keeps the sit pose until fixed by `interrupt` (done) and perch is cleared on grab.
- M7 an overflow (hidden) Claudette that receives a tool call stays hidden.

## Not verified live

Perching on a real moving window; thinking pacing and automatic tidy-up after the fix; grab-while-walking;
display unplug/replug (items relocate); privacy mode hiding items already shown; sub-agent roaming; the name
tag staying opaque under the hover fade. A 30-minute soak. In a 10-minute soak resident memory grew from
50 MB to 104 MB; `leaks` finds 0 leaks (5.5 MB malloc'd), so the growth is probably graphics (IOSurface)
accounting, not a proven cause.
