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

If nothing is left to do, Claude just says so and nothing is saved. If you want an unrelated new session, say no and the handoff is ignored.

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
- `/relay:resume`: continue from the latest handoff in this project.

## How it works

- A **Stop hook** reads the token usage of the last turn from the transcript. Past the threshold, it blocks the stop once and asks Claude for a handoff between `<relay-handoff>` tags. When Claude's reply contains that block, the same hook saves it to `.claude/relay/handoff.md`. Claude never writes the file itself, so you get no permission prompt, and you see the handoff in the chat.
- A **SessionStart hook** (on `startup` and `/clear`) finds the handoff for the current project and either asks or loads it. Each handoff is offered once and then kept as `.claude/relay/last.md`.
- `.claude/relay/` contains its own `.gitignore`, so nothing ends up in your repo.

## Development

```
bash tests/run.sh                 # simulated hook inputs, no API calls
claude --plugin-dir .             # try it locally
RELAY_THRESHOLD_TOKENS=5000 claude --plugin-dir .   # trigger it fast
```

## License

MIT
