#!/usr/bin/env bash
# Stop hook:
# 1. If Claude's reply contains a <relay-handoff> block, save it for the next session.
# 2. Once the context passes the threshold at the end of a turn, ask Claude for that block.
. "$(dirname "$0")/lib.sh"
INPUT=$(cat)
session=$(safe_id "$(json_str session_id)")

# Claude prints the handoff instead of writing it: writes under .claude/ always
# need approval, and this way the user sees the handoff too.
open='<relay-handoff>'; close='</relay-handoff>'
flat=$(printf '%s' "$INPUT" | tr -d '\r\n')
case "$flat" in *"$open"*"$close"*)
  body=${flat##*"$open"}
  body=${body%%"$close"*}
  dir=$(relay_dir)
  printf '%s' "$body" | json_unescape | sed '/./,$!d' > "$dir/handoff.md"
  printf '%s\n' "$session" > "$dir/handoff.session"
  printf '{"systemMessage":"relay: handoff saved. Type /clear to continue in a fresh session."}\n'
  exit 0
esac

# Our own block makes Claude continue; never trigger on that follow-up turn.
json_true stop_hook_active && exit 0

threshold=$(int_or "$(cfg threshold_tokens 130000)" 130000)
[ "$threshold" -eq 0 ] && exit 0
on_decline=$(cfg on_decline ignore)
remind_every=$(int_or "$(cfg remind_every_tokens 30000)" 30000)

tokens=$(context_tokens "$(json_str transcript_path)")
[ "$tokens" -lt "$threshold" ] && exit 0

state="$(state_dir)/${session:-unknown}"
find "$(dirname "$state")" -type f -mtime +7 -delete 2>/dev/null

# Already offered in this session and the user kept going here.
if [ -f "$state" ]; then
  [ "$on_decline" = "remind" ] || exit 0
  last=$(int_or "$(cat "$state" 2>/dev/null)" 0)
  [ "$tokens" -lt $((last + remind_every)) ] && exit 0
fi
echo "$tokens" > "$state"
# An older, never-picked-up handoff is outdated now.
rm -f "$(relay_dir)/handoff.md"

k=$((tokens / 1000)); tk=$((threshold / 1000))
reason="[relay] Context is at ~${k}k tokens (threshold ${tk}k). The current task is finished, so this is a good point to continue in a fresh session.

Is there concrete follow-up work from this conversation?
- If NO: reply with one short line that everything is done and nothing needs to be carried over.
- If YES: print a handoff in your reply between a line containing only ${open} and a line containing only ${close}. relay saves it automatically; do not write any file yourself. After the block, tell the user in one line (in their language) that they can type /clear to continue in a fresh session, or just keep going here.

Handoff format: Markdown without code fences, under 6000 characters, written for a fresh Claude with no memory of this session:
# <one-line title>
## Goal
## Current state (what is done, and how it was verified)
## Next steps (ordered, concrete)
## Key files (paths and why they matter)
## Decisions and constraints (including approaches tried and rejected, and why)
## Open questions
Use exact paths, commands, names and IDs. Do not narrate the session."

printf '{"decision":"block","reason":"%s"}\n' "$(printf '%s' "$reason" | json_escape)"
