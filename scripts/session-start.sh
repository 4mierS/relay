#!/usr/bin/env bash
# SessionStart hook (startup|clear): offer or load waiting handoffs for this project.
# After /clear, a handoff written in the same terminal (same Claude process) is
# this session's own. Handoffs of parallel sessions are only listed, never consumed.
. "$(dirname "$0")/lib.sh"
INPUT=$(cat)

mode=$(cfg on_new_session ask)
[ "$mode" = "off" ] && exit 0
max_age_h=$(int_or "$(cfg max_age_hours 24)" 24)
[ -d "$(project_dir)/.claude/relay" ] || exit 0
migrate_legacy

session=$(safe_id "$(json_str session_id)")
source=$(json_str source)
pid=$(claude_pid)
now=$(date +%s)

own=""; others=()
for f in "$(pending_dir)"/*.md; do
  [ -f "$f" ] || continue
  # Never offer a handoff back to the session that wrote it.
  [ -n "$session" ] && [ "$(meta "$f" session)" = "$session" ] && continue
  age=$(( now - $(mtime "$f") ))
  [ "$age" -gt $((max_age_h * 3600)) ] && continue
  if [ "$source" = clear ] && [ -n "$pid" ] && [ "$(meta "$f" pid)" = "$pid" ]; then
    own="$f"  # names start with a timestamp, so the newest one wins
  else
    others+=("$f")
  fi
done
# Without CLAUDE_PID (older Claude Code), /clear with a single waiting handoff behaves like relay 0.1.
if [ -z "$own" ] && [ -z "$pid" ] && [ "$source" = clear ] && [ "${#others[@]}" -eq 1 ]; then
  own="${others[0]}"; others=()
fi

describe() { # file -> "title" (written 12 min ago on branch main)
  local age b; age=$(( now - $(mtime "$1") )); [ "$age" -lt 0 ] && age=0
  b=$(meta "$1" branch)
  printf '"%s" (written %s ago%s)' "$(handoff_title "$1")" "$(human_age "$age")" "${b:+ on branch $b}"
}

# Warn when the code moved on since the handoff was written.
drift() {
  local b h cb ch; b=$(meta "$1" branch); h=$(meta "$1" head); cb=$(git_branch); ch=$(git_head)
  if [ -n "$b" ] && [ -n "$cb" ] && [ "$b" != "$cb" ]; then
    printf ' Note: it was written on branch %s, but the project is now on %s. Check this with the user before continuing.' "$b" "$cb"
  elif [ -n "$h" ] && [ -n "$ch" ] && [ "$h" != "$ch" ]; then
    printf ' Note: HEAD moved from %s to %s since it was written; verify its current state before relying on it.' "$h" "$ch"
  fi
}

emit() { # notice, context
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
    "$(printf '%s' "$1" | json_escape)" "$(printf '%s' "$2" | json_escape)"
}

if [ -n "$own" ]; then
  # This terminal's own handoff: offered once, then kept in done/ for /relay:resume.
  desc=$(describe "$own"); note=$(drift "$own")
  finish_handoff "$own"
  file="$(done_dir)/$(basename "$own")"
  printf '%s\n' "$(basename "$own")" > "$(state_dir)/${session:-unknown}.from"
  if [ "$mode" = "auto" ]; then
    emit "relay: loaded handoff ${desc}" "[relay] Continuing from a handoff written at the end of the previous session in this terminal (saved at ${file}). Treat it as your working context.${note} In your first reply, confirm in one line what you are picking up, then follow the user's lead.

<handoff>
$(handoff_body "$file" | head -c 8000)
</handoff>"
  else
    emit "relay: found a handoff ${desc}. Claude will ask whether to pick it up." "[relay] A handoff from the previous session in this terminal is waiting: ${desc}, saved at ${file}.${note} Before acting on the user's first message, ask them once, in their language, whether to continue from it. If yes, read that file and continue from it. If no, ignore it and handle their message normally."
  fi
  exit 0
fi

[ "${#others[@]}" -eq 0 ] && exit 0

# Handoffs of other sessions stay waiting until a session reads one (the Stop hook marks it picked up).
list=""; i=0
for f in "${others[@]}"; do
  i=$((i + 1)); list="${list}${i}. $(describe "$f"), saved at ${f}$(drift "$f")
"
done
if [ "$i" -eq 1 ]; then
  emit "relay: a handoff from another session is waiting: $(describe "${others[0]}"). Claude will ask whether to pick it up." "[relay] A handoff from another session in this project is waiting:
${list}
Before acting on the user's first message, ask them once, in their language, whether to continue from it. If yes, read that file and continue from it. If no, ignore it and handle their message normally; it stays available for other sessions."
else
  emit "relay: ${i} handoffs from other sessions are waiting. Claude will ask which one to pick up." "[relay] ${i} handoffs from other sessions in this project are waiting (newest last):
${list}
Before acting on the user's first message, show the user these titles once, in their language, and ask whether to continue from one of them. If they pick one, read that file and continue from it. If none, ignore them and handle their message normally; they stay available for other sessions."
fi
