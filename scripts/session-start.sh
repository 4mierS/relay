#!/usr/bin/env bash
# SessionStart hook (startup|clear): offer or load a pending handoff for this project.
. "$(dirname "$0")/lib.sh"
INPUT=$(cat)

mode=$(cfg on_new_session ask)
[ "$mode" = "off" ] && exit 0
max_age_h=$(int_or "$(cfg max_age_hours 24)" 24)

dir="$(project_dir)/.claude/relay"
handoff="$dir/handoff.md"
offered="$dir/last.md"
[ -s "$handoff" ] || exit 0

# Never offer a handoff back to the session that wrote it.
session=$(safe_id "$(json_str session_id)")
[ -n "$session" ] && [ "$session" = "$(cat "$dir/handoff.session" 2>/dev/null)" ] && exit 0

age=$(( $(date +%s) - $(mtime "$handoff") ))
[ "$age" -lt 0 ] && age=0
# Offer each handoff once; it stays available as last.md for /relay:resume.
mv -f "$handoff" "$offered"
[ "$age" -gt $((max_age_h * 3600)) ] && exit 0

title=$(sed -n 's/^#[[:space:]]\{1,\}//p' "$offered" | head -n 1)
title="${title:-untitled}"
when=$(human_age "$age")

if [ "$mode" = "auto" ]; then
  context="[relay] Continuing from a handoff written at the end of an earlier session in this project (saved at ${offered}). Treat it as your working context. In your first reply, confirm in one line what you are picking up, then follow the user's lead.

<handoff>
$(head -c 8000 "$offered")
</handoff>"
  notice="relay: loaded handoff from ${when} ago: \"${title}\""
else
  context="[relay] A handoff from an earlier session in this project is waiting: \"${title}\" (written ${when} ago, saved at ${offered}). Before acting on the user's first message, ask them once, in their language, whether to continue from it. If yes, read that file and continue from it. If no, ignore it and handle their message normally."
  notice="relay: found a handoff from ${when} ago: \"${title}\". Claude will ask whether to pick it up."
fi

printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
  "$(printf '%s' "$notice" | json_escape)" "$(printf '%s' "$context" | json_escape)"
