# Using Claudette

## Connect it to Claude Code

Open the menubar item, choose **Settings…**, and under **Claude Code**:

1. **Activity plugin → Install…** creates `~/.claude/skills/claudette` (a small script that sends
   activity to Claudette on this Mac only, and always exits quietly, so Claude Code reports no hook
   errors when Claudette is closed). Start a new Claude Code session afterwards. An older install
   shows **Update…**: press it to switch to the silent script.
2. **Usage limits → Connect…** wraps your `statusLine` command in `~/.claude/settings.json` so the
   5-hour and weekly limits reach Claudette. Your own status line keeps working; a backup is kept;
   **Disconnect** restores it. Limits only appear for Claude.ai Pro/Max subscribers, and only after
   the first reply of a session.

Both steps ask for confirmation first and show exactly which file they change.

## What you will see

- One Claudette per Claude Code session, standing along the bottom of the screen on every desktop.
  More than six collapse into a `+N` pill.
- Tool calls become items on the screen (file, search, shell, web, skill, MCP cartridge). She walks to
  them, picks them up, works, and tosses them aside; they stay where they land. A file she touched
  before is the *same* item (for every session and sub-agent), so she walks back to it. Terminals are
  bigger and show the start of the command; hover for the full command and, when done, the result.
  **Drag any item** and she follows it. A busy session leaves a lot lying around (the limit is in
  Settings, "Clutter limit").
- While Claude thinks she paces about with a thought bubble. Hover her to see her project name.
  She may perch on a window's top edge, and tumbles if you move that window.
- Sub-agents are little Claudettes that roam near her and do their own work.
- `!` (amber, she waves) means a permission prompt is waiting; `?` (blue) means Claude asked a
  question; a red pill names an API, sign-in, billing or rate-limit error.
- The jar on her shoulder is the 5-hour window (fill = what is left); the moon in the top-right is the
  weekly window (it fades under the pointer; drag it wherever you like, it remembers). At the limit the screen dims, she naps with a "back at HH:MM" sign, and when the
  limit lifts there is confetti. The menubar icon is Claudette herself with a status dot; the limit levels are the first line of its menu.
- Context window = the little backpack on her left shoulder.

## Playing with her

- Drag her anywhere; flick her and she slides to a stop. Her spot is remembered per session.
- Move the pointer towards her and she may dodge. **Hold Option** to keep her still so you can grab
  her. If she is cornered, or dodging is off, she fades to about 25% while the pointer is over her.
- Rest the pointer on her for two seconds to pet her.
- Settings: size (50% to 200%), fade and dodge, privacy mode (hides file, project and server names),
  Focus mode (hides her completely), Reduce motion, launch at login.

## Troubleshooting

- Nothing appears: check the menu says "Listening on 127.0.0.1:47631" and that you started a *new*
  Claude Code session after installing the plugin.
- No limits: the status line only runs while a session is open, and only subscribers get
  `rate_limits`. A project-level `statusLine` overrides the user-level one (Settings shows a warning).
- She covers text: leave "Fade when the pointer is over her" on, or use Focus mode.
