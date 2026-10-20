# relay

**Hand off to a fresh Claude Code session at the end of a task, instead of compacting in the middle of one.**

Long sessions get expensive and fuzzy: every turn resends the whole context, and auto-compact eventually kicks in wherever you happen to be. relay waits until the context is large **and** Claude has finished what it was doing. Then it asks Claude for a short, structured handoff. You type `/clear`, and the fresh session asks whether to pick it up.

```
… task done, context at 134k
relay ─► Claude prints a handoff (goal, state, next steps, key files, decisions)
         "relay: handoff saved. Type /clear to continue in a fresh session."
/clear
relay ─► "Found a handoff from 2 min ago: 'Finish contact form'. Continue from it?"
ja ────► Claude reads it and carries on, with a ~2k context instead of 134k
```

If nothing is left to do, Claude just says so and nothing is saved. If you want an unrelated new session, say no and the handoff is ignored. If Claude's last reply was a question to you, relay waits for the next turn instead of interrupting.

### Several sessions in one project

Every handoff is its own file, tagged with the session and terminal that wrote it, plus the git branch and commit.

- After `/clear`, a terminal only gets **its own** handoff. Parallel sessions in the same project never take or overwrite each other's handoffs.
- A **new terminal** lists the handoffs that are waiting and asks which one to continue:
  ```
  relay: 2 handoffs from other sessions are waiting. Claude will ask which one to pick up.
  1. "Auth refactor" (written 12 min ago on branch feat/auth)
  2. "Landing page copy" (written 3 h ago on branch main)
  ```
  Saying no leaves them waiting for their own terminals.
- If the branch changed since the handoff was written, Claude points it out before continuing.
- Handoffs form a chain: each one records the handoff its session started from (`previous`), so relay 1 → 2 → 3 stays traceable.

## Install

```
/plugin marketplace add 4mierS/relay
/plugin install relay@relay
```

Requires Claude Code 2.1.271+ and `bash` (on Windows, Git Bash, which Claude Code already uses). There are no other dependencies: no `jq`, Node or Python.

## Settings

All settings live in `/config` under **relay**:

| Setting | Default | |
|---|---|---|
| `threshold_tokens` | `130000` | Context size that triggers a handoff at the end of a turn. `0` turns relay off. |
| `on_new_session` | `ask` | After `/clear` or startup: `ask` whether to continue, `auto` load it straight away, or `off`. |
| `on_decline` | `ignore` | If you keep working in the same session instead: `ignore` (stay quiet) or `remind` (new handoff later). |
| `remind_every_tokens` | `30000` | With `remind`: how much the context must grow before the next handoff. |
| `max_age_hours` | `24` | Older handoffs aren't offered (still reachable with `/relay:resume`). |

Each setting can also be overridden per shell with `RELAY_<SETTING>`, for example `RELAY_THRESHOLD_TOKENS=80000 claude`.

## Commands

- `/relay:handoff`: write a handoff now, whatever the context size.
- `/relay:resume`: continue from a waiting handoff in this project (asks which one if there are several), or from the last one picked up.

## How it works

- A **Stop hook** reads the token usage of the last turn from the transcript. Past the threshold, it blocks the stop once and asks Claude for a handoff between `<relay-handoff>` tags. When Claude's reply contains that block, the same hook saves it to `.claude/relay/handoffs/<time>-<title>.md`. Claude never writes the file itself, so you get no permission prompt, and you see the handoff in the chat.
- A **SessionStart hook** (on `startup` and `/clear`) looks at the waiting handoffs. After `/clear` it offers the one written by the same Claude process (`CLAUDE_PID` stays the same across `/clear`), then moves it to `.claude/relay/done/`. In a new terminal it lists the waiting ones and leaves them in place.
- When a session reads a waiting handoff, the Stop hook moves it to `done/` and remembers it as that session's `previous`.
- `.claude/relay/` contains its own `.gitignore`, so nothing ends up in your repo. Handoffs from relay 0.1 (`handoff.md`) are picked up automatically.

## Other agents

[`standalone/relay`](standalone/relay/SKILL.md) is a hook-free version as a single `SKILL.md` for Cursor, Codex CLI, Copilot, Gemini CLI and other agents that support skills. You trigger the handoff and the resume yourself. It uses the same files, so both versions can be used in the same project.

## Development

```
bash tests/run.sh                 # simulated hook inputs, no API calls
claude --plugin-dir .             # try it locally
RELAY_THRESHOLD_TOKENS=5000 claude --plugin-dir .   # trigger it fast
```

## License

MIT
