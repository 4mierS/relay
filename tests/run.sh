#!/usr/bin/env bash
# Simulates hook inputs against scripts/stop.sh and scripts/session-start.sh.
# Usage: bash tests/run.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0

export CLAUDE_PROJECT_DIR="$tmp/project"
export CLAUDE_PLUGIN_DATA="$tmp/data"
mkdir -p "$CLAUDE_PROJECT_DIR"
unset RELAY_THRESHOLD_TOKENS RELAY_ON_NEW_SESSION RELAY_ON_DECLINE RELAY_MAX_AGE_HOURS CLAUDE_PID
relay="$CLAUDE_PROJECT_DIR/.claude/relay"

check() { # name, condition-result
  if [ "$2" = 0 ]; then pass=$((pass + 1)); echo "  ok   $1"
  else fail=$((fail + 1)); echo "  FAIL $1"; fi
}
valid_json() {
  if command -v python3 >/dev/null; then printf '%s' "$1" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null
  elif command -v node >/dev/null; then printf '%s' "$1" | node -e 'JSON.parse(require("fs").readFileSync(0,"utf8"))' 2>/dev/null
  else return 0; fi
}
transcript() { # tokens, [extra jsonl line] -> path
  local f="$tmp/t-$1-$RANDOM.jsonl"
  {
    echo '{"type":"user","message":{"role":"user","content":"hi \"input_tokens\":999999"}}'
    echo "{\"type\":\"assistant\",\"message\":{\"model\":\"claude-x\",\"usage\":{\"input_tokens\":5,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":1000,\"output_tokens\":10}}}"
    echo "{\"type\":\"assistant\",\"message\":{\"model\":\"claude-x\",\"usage\":{\"input_tokens\":2,\"cache_creation_input_tokens\":500,\"cache_read_input_tokens\":$(( $1 - 602 )),\"output_tokens\":100,\"output_tokens_details\":{\"thinking_tokens\":0}}}}"
    echo '{"type":"assistant","isSidechain":true,"message":{"model":"claude-x","usage":{"input_tokens":1,"cache_read_input_tokens":5}}}'
    echo '{"type":"assistant","message":{"model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0}}}'
    if [ -n "${2:-}" ]; then echo "$2"; fi
  } > "$f"
  printf '%s' "$f"
}
stop() { # session, tokens, [stop_hook_active], [last message], [extra transcript line]
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":%s,"last_assistant_message":"%s"}' \
    "$1" "$(transcript "$2" "${5:-}")" "$CLAUDE_PROJECT_DIR" "${3:-false}" "${4:-Done.}" | bash "$root/scripts/stop.sh"
}
save() { # session, title: Claude prints a handoff block
  printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"Stop","stop_hook_active":true,"last_assistant_message":"Done.\\n\\n<relay-handoff>\\n# %s\\n## Next steps\\n1. Go on\\n</relay-handoff>\\n\\nType /clear."}' \
    "$1" "$(transcript 1000)" "$2" | bash "$root/scripts/stop.sh"
}
start() { # session, source
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SessionStart","source":"%s"}' \
    "$1" "$CLAUDE_PROJECT_DIR" "$2" | bash "$root/scripts/session-start.sh"
}
waiting() { ls "$relay/handoffs" 2>/dev/null | grep -c '\.md$'; }
reset() { rm -rf "$relay" "$CLAUDE_PLUGIN_DATA"; }
has() { printf '%s' "$1" | grep -qF -- "$2"; }

echo "context_tokens"
. "$root/scripts/lib.sh"
[ "$(context_tokens "$(transcript 140000)")" = 140000 ]; check "sums last main-thread usage, ignores sidechain/synthetic/content" $?

echo "Stop hook: threshold"
out=$(stop s1 100000); [ -z "$out" ]; check "below threshold: silent" $?
out=$(stop s1 140000); has "$out" '"decision":"block"'; check "above threshold: blocks" $?
valid_json "$out"; check "block output is valid JSON" $?
has "$out" '140k'; check "reason mentions token count" $?
[ -f "$relay/.gitignore" ]; check "creates self-ignoring .claude/relay/" $?
out=$(stop s1 150000 true); [ -z "$out" ]; check "stop_hook_active: silent" $?
out=$(stop s1 200000); [ -z "$out" ]; check "on_decline=ignore: silent after first offer" $?
out=$(RELAY_ON_DECLINE=remind stop s2 140000); [ -n "$out" ]; check "remind: first offer" $?
out=$(RELAY_ON_DECLINE=remind stop s2 160000); [ -z "$out" ]; check "remind: quiet before +30k" $?
out=$(RELAY_ON_DECLINE=remind stop s2 171000); [ -n "$out" ]; check "remind: offers again after +30k" $?
out=$(RELAY_THRESHOLD_TOKENS=0 stop s3 500000); [ -z "$out" ]; check "threshold 0 disables" $?
out=$(CLAUDE_PLUGIN_OPTION_THRESHOLD_TOKENS=50000 stop s4 60000); [ -n "$out" ]; check "reads plugin userConfig" $?
out=$(stop s5 140000 false 'Which color should the button be?\n\n'); [ -z "$out" ]; check "reply ends with a question: waits" $?
out=$(stop s6 140000 false 'Soll ich das so bauen?**'); [ -z "$out" ]; check "question with trailing markdown: waits" $?
out=$(stop s5 141000 false 'Is it ok? I also fixed \"the bug\".'); [ -n "$out" ]; check "question in the middle: offers, after waiting a turn" $?

echo "Stop hook: saving the handoff from Claude's reply"
reset
reply='Done.\n\n<relay-handoff>\n# Add beta to notes\n## Next steps\n1. Append \"beta\" to C:\\tmp\\notes.txt über — 🚀 ok\n</relay-handoff>\n\nType /clear to continue.'
out=$(printf '{"session_id":"s20","transcript_path":"%s","hook_event_name":"Stop","stop_hook_active":true,"last_assistant_message":"%s"}' \
  "$(transcript 1000)" "$reply" | CLAUDE_PID=111 bash "$root/scripts/stop.sh")
has "$out" 'handoff saved'; check "confirms saved handoff" $?
valid_json "$out"; check "confirmation is valid JSON" $?
f=$(ls "$relay"/handoffs/*.md 2>/dev/null | head -n 1)
case "$f" in *-add-beta-to-notes.md) true ;; *) false ;; esac; check "file named after the title" $?
[ "$(meta "$f" session)" = s20 ] && [ "$(meta "$f" pid)" = 111 ]; check "frontmatter records session and pid" $?
[ "$(handoff_body "$f" | head -n 1)" = "# Add beta to notes" ]; check "saves block without leading blank lines" $?
grep -qF 'Append "beta" to C:\tmp\notes.txt' "$f"; check "decodes quotes and backslashes" $?
grep -qF 'über — 🚀 ok' "$f"; check "decodes \\u escapes to UTF-8, incl. surrogate pairs" $?
! grep -q 'relay-handoff\|Type /clear' "$f"; check "saves only the block" $?
sleep 1; CLAUDE_PID=111 save s20 "Second try" >/dev/null
[ "$(waiting)" = 1 ] && ls "$relay/handoffs" | grep -q second-try; check "a newer handoff of the same session replaces the old one" $?

echo "SessionStart hook: own terminal after /clear"
reset
out=$(start s5 clear); [ -z "$out" ]; check "no handoff: silent" $?
CLAUDE_PID=111 save sA "Finish contact form" >/dev/null
out=$(CLAUDE_PID=111 start sA startup); ! has "$out" 'Finish contact form'; check "same session that wrote it: not offered" $?
out=$(CLAUDE_PID=111 start sB clear); has "$out" 'ask them once'; check "ask mode: asks" $?
valid_json "$out"; check "ask output is valid JSON" $?
has "$out" 'Finish contact form'; check "ask mode: shows title" $?
[ "$(waiting)" = 0 ] && ls "$relay/done" | grep -q finish-contact-form; check "own handoff offered once, kept in done/" $?
out=$(CLAUDE_PID=111 start sC clear); [ -z "$out" ]; check "not offered twice" $?
CLAUDE_PID=111 save sC 'Quote \"test\" \\\\ back' >/dev/null
out=$(RELAY_ON_NEW_SESSION=auto CLAUDE_PID=111 start sD clear); has "$out" '<handoff>'; check "auto mode: injects content" $?
valid_json "$out"; check "auto output with quotes/backslashes is valid JSON" $?
! has "$out" 'pid: 111'; check "auto mode: injects body without frontmatter" $?
CLAUDE_PID=111 save sE "Off" >/dev/null; out=$(RELAY_ON_NEW_SESSION=off CLAUDE_PID=111 start sF clear); [ -z "$out" ]; check "off mode: silent" $?
reset; CLAUDE_PID=111 save sA "Old" >/dev/null
f=$(ls "$relay"/handoffs/*.md); touch -d '2 days ago' "$f" 2>/dev/null || touch -t "$(date -v-2d +%Y%m%d%H%M)" "$f"
out=$(CLAUDE_PID=111 start sB clear); [ -z "$out" ]; check "older than max age: silent" $?

echo "SessionStart hook: parallel sessions"
reset
CLAUDE_PID=111 save sA "Auth refactor" >/dev/null; sleep 1
CLAUDE_PID=222 save sB "Landing page" >/dev/null
out=$(CLAUDE_PID=111 start sA2 clear); has "$out" 'Auth refactor' && ! has "$out" 'Landing page'; check "/clear picks this terminal's own handoff only" $?
ls "$relay/handoffs" | grep -q landing-page; check "other terminal's handoff stays waiting" $?
out=$(CLAUDE_PID=222 start sB2 clear); has "$out" 'Landing page'; check "other terminal still gets its own after /clear" $?
reset
CLAUDE_PID=111 save sA "Auth refactor" >/dev/null; sleep 1
CLAUDE_PID=222 save sB "Landing page" >/dev/null
out=$(CLAUDE_PID=333 start sN startup); has "$out" '2 handoffs' && has "$out" 'Auth refactor' && has "$out" 'Landing page'; check "new terminal lists all waiting handoffs" $?
valid_json "$out"; check "list output is valid JSON" $?
[ "$(waiting)" = 2 ]; check "listing does not consume them" $?
CLAUDE_PID=222 stop sB 140000 >/dev/null; sleep 1
CLAUDE_PID=222 save sB "Landing page v2" >/dev/null
[ "$(waiting)" = 2 ] && ls "$relay/handoffs" | grep -q auth-refactor; check "threshold/save in one session keeps the other session's handoff" $?
f=$(ls "$relay"/handoffs/*auth-refactor.md)
line="{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Read\",\"input\":{\"file_path\":\"$f\"}}]}}"
CLAUDE_PID=333 stop sN 1000 false 'Picked it up.' "$line" >/dev/null
[ ! -f "$f" ] && [ -f "$relay/done/$(basename "$f")" ]; check "reading a listed handoff marks it picked up" $?
[ "$(cat "$CLAUDE_PLUGIN_DATA/state/sN.from" 2>/dev/null)" = "$(basename "$f")" ]; check "remembers which handoff the session continued" $?
CLAUDE_PID=333 save sN "Auth refactor part 2" >/dev/null
[ "$(meta "$(ls "$relay"/handoffs/*part-2.md)" previous)" = "$(basename "$f")" ]; check "next handoff links the previous one" $?

echo "Migration from relay 0.1"
reset; mkdir -p "$relay"; printf '# Legacy task\n' > "$relay/handoff.md"; echo s0 > "$relay/handoff.session"
out=$(start sL clear); has "$out" 'Legacy task'; check "single legacy handoff.md is offered after /clear" $?
[ ! -f "$relay/handoff.md" ]; check "legacy file moved" $?

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
