# Payload spike (Task 4)

Captured 2026-11-20 with Claude Code 2.1.329 on macOS 15.7, using `claude -p --plugin-dir <generated plugin>`
against the running Claudette app (events logged to `~/Library/Logs/Claudette/events.jsonl`).
Headless (`-p`) mode only so far; interactive-only behaviour is listed under "Not yet confirmed".

## Confirmed

- **Plugin + `http` hooks work.** `claude plugin validate` passes (only an "author" warning). All 22
  registered events are accepted. Hook delivery to the loopback server works with an empty-2xx reply.
- **Common fields** on every event: `session_id`, `cwd`, `transcript_path`, `prompt_id`; most also carry
  `permission_mode`, `effort {level}`.
- **PreToolUse / PostToolUse**: `tool_name`, `tool_input`, `tool_use_id`; PostToolUse adds `tool_response`
  and `duration_ms`. Bash input: `{command, timeout}`.
- **PostToolUseFailure**: `error` (string, e.g. `"Exit code 1\ncat: ..."`) and `is_interrupt` (bool).
- **Skill loading**: tool name `Skill`, `tool_input.skill` = skill name (e.g. `superpowers:verification-before-completion`).
- **MCP**: PreToolUse/PostToolUse carry `mcp_server {name, source}` plus `tool_name` `mcp__<server>__<tool>`.
- **Sub-agents**: the spawning tool is named **`Agent`** (not `Task`); `tool_input` has `subagent_type`,
  `prompt`. `SubagentStart` / `SubagentStop` carry `agent_id`, `agent_type`. Tool events fired inside a
  sub-agent carry that sub-agent's `agent_id` and `agent_type`.
- **PermissionRequest** fires (also in `-p` mode when a tool is not allowed): `tool_name`, `tool_input`,
  `permission_suggestions[]`. No decision was returned and the normal flow continued.
- **Stop** carries `last_assistant_message`, `stop_hook_active`, **`background_tasks[]`** and
  **`session_crons[]`** (both empty arrays here). `background_tasks` is a likely source for background
  shells; its element shape is still unknown.
- **SessionEnd**: `reason` (`other` in `-p`).
- `UserPromptSubmit`: `prompt`.

## Not yet confirmed (need an interactive session or a forced failure)

- `SessionStart` did **not** arrive in `-p` mode (SessionStore must auto-create sessions from any event; it does).
- `StopFailure` payload / error key (we read `error_type`; a real API error is needed to check).
- `Notification` (`permission_prompt`, `idle_prompt`), `Elicitation`, `PreCompact/PostCompact`, `PreModelSwitch`.
- `background_tasks[]` element shape; whether `run_in_background` appears in Bash `tool_input`.
- Hook latency under load (no slowdown noticed in these runs).
- Skills-dir plugin route (`~/.claude/skills/claudette/`): not tested; needs the user's go-ahead to touch `~/.claude`.
- Status line `rate_limits` capture (Task 7).

## Consequences for the code

- `SceneMapper`: treat tool name `Agent` as the sub-agent scene (the plan said `Task`).
- Skill scene: `tool_name == "Skill"`, name from `tool_input.skill`.
- `SessionStore` must not rely on `SessionStart`.

## Known gaps (Task 14)

- **Pure network disconnects** are not reported by any hook we have seen; only API errors that end a turn
  (`StopFailure` with `server_error` etc.) are. The "offline" error kind exists in the UI but nothing emits it yet.
- Scenes for `Task`/`TaskCreated`/`TaskCompleted` events and per-model outfits are not drawn yet.
