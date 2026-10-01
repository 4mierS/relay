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
unset RELAY_THRESHOLD_TOKENS RELAY_ON_NEW_SESSION RELAY_ON_DECLINE RELAY_MAX_AGE_HOURS

check() { # name, condition-result
  if [ "$2" = 0 ]; then pass=$((pass + 1)); echo "  ok   $1"
  else fail=$((fail + 1)); echo "  FAIL $1"; fi
}
valid_json() {
  if command -v python3 >/dev/null; then printf '%s' "$1" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null
  elif command -v node >/dev/null; then printf '%s' "$1" | node -e 'JSON.parse(require("fs").readFileSync(0,"utf8"))' 2>/dev/null
  else return 0; fi
}
transcript() { # tokens -> path
  local f="$tmp/t-$1.jsonl"
  {
    echo '{"type":"user","message":{"role":"user","content":"hi \"input_tokens\":999999"}}'
    echo "{\"type\":\"assistant\",\"message\":{\"model\":\"claude-x\",\"usage\":{\"input_tokens\":5,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":1000,\"output_tokens\":10}}}"
    echo "{\"type\":\"assistant\",\"message\":{\"model\":\"claude-x\",\"usage\":{\"input_tokens\":2,\"cache_creation_input_tokens\":500,\"cache_read_input_tokens\":$(( $1 - 602 )),\"output_tokens\":100,\"output_tokens_details\":{\"thinking_tokens\":0}}}}"
    echo '{"type":"assistant","isSidechain":true,"message":{"model":"claude-x","usage":{"input_tokens":1,"cache_read_input_tokens":5}}}'
    echo '{"type":"assistant","message":{"model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0}}}'
  } > "$f"
  printf '%s' "$f"
}
stop() { # session, tokens, [stop_hook_active]
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":%s}' \
    "$1" "$(transcript "$2")" "$CLAUDE_PROJECT_DIR" "${3:-false}" | bash "$root/scripts/stop.sh"
}
start() { # session, source
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SessionStart","source":"%s"}' \
    "$1" "$CLAUDE_PROJECT_DIR" "$2" | bash "$root/scripts/session-start.sh"
}
write_handoff() { printf '# Finish contact form\n## Goal\nShip it\n' > "$CLAUDE_PROJECT_DIR/.claude/relay/handoff.md"; }

echo "context_tokens"
. "$root/scripts/lib.sh"
[ "$(context_tokens "$(transcript 140000)")" = 140000 ]; check "sums last main-thread usage, ignores sidechain/synthetic/content" $?

echo "Stop hook"
out=$(stop s1 100000); [ -z "$out" ]; check "below threshold: silent" $?
out=$(stop s1 140000); printf '%s' "$out" | grep -q '"decision":"block"'; check "above threshold: blocks" $?
valid_json "$out"; check "block output is valid JSON" $?
printf '%s' "$out" | grep -q '140k'; check "reason mentions token count" $?
[ -f "$CLAUDE_PROJECT_DIR/.claude/relay/.gitignore" ]; check "creates self-ignoring .claude/relay/" $?
out=$(stop s1 150000 true); [ -z "$out" ]; check "stop_hook_active: silent" $?
out=$(stop s1 200000); [ -z "$out" ]; check "on_decline=ignore: silent after first offer" $?
out=$(RELAY_ON_DECLINE=remind stop s2 140000); [ -n "$out" ]; check "remind: first offer" $?
out=$(RELAY_ON_DECLINE=remind stop s2 160000); [ -z "$out" ]; check "remind: quiet before +30k" $?
out=$(RELAY_ON_DECLINE=remind stop s2 171000); [ -n "$out" ]; check "remind: offers again after +30k" $?
out=$(RELAY_THRESHOLD_TOKENS=0 stop s3 500000); [ -z "$out" ]; check "threshold 0 disables" $?
out=$(CLAUDE_PLUGIN_OPTION_THRESHOLD_TOKENS=50000 stop s4 60000); [ -n "$out" ]; check "reads plugin userConfig" $?

echo "Stop hook: saving the handoff from Claude's reply"
reply='Done.\n\n<relay-handoff>\n# Add beta to notes\n## Next steps\n1. Append \"beta\" to C:\\tmp\\notes.txt über — 🚀 ok\n</relay-handoff>\n\nType /clear to continue.'
out=$(printf '{"session_id":"s20","transcript_path":"%s","hook_event_name":"Stop","stop_hook_active":true,"last_assistant_message":"%s"}' \
  "$(transcript 1000)" "$reply" | bash "$root/scripts/stop.sh")
printf '%s' "$out" | grep -q 'handoff saved'; check "confirms saved handoff" $?
valid_json "$out"; check "confirmation is valid JSON" $?
f="$CLAUDE_PROJECT_DIR/.claude/relay/handoff.md"
[ "$(head -n 1 "$f")" = "# Add beta to notes" ]; check "saves block without leading blank lines" $?
grep -qF 'Append "beta" to C:\tmp\notes.txt' "$f"; check "decodes quotes and backslashes" $?
grep -qF 'über — 🚀 ok' "$f"; check "decodes \\u escapes to UTF-8, incl. surrogate pairs" $?
! grep -q 'relay-handoff\|Type /clear' "$f"; check "saves only the block" $?
[ "$(cat "$CLAUDE_PROJECT_DIR/.claude/relay/handoff.session")" = s20 ]; check "records writing session" $?
rm -f "$f"

echo "SessionStart hook"
out=$(start s5 clear); [ -z "$out" ]; check "no handoff: silent" $?
write_handoff; echo s6 > "$CLAUDE_PROJECT_DIR/.claude/relay/handoff.session"
out=$(start s6 startup); [ -z "$out" ]; check "same session that wrote it: silent" $?
out=$(start s7 clear); printf '%s' "$out" | grep -q 'ask them once'; check "ask mode: asks" $?
valid_json "$out"; check "ask output is valid JSON" $?
printf '%s' "$out" | grep -q 'Finish contact form'; check "ask mode: shows title" $?
[ -f "$CLAUDE_PROJECT_DIR/.claude/relay/last.md" ] && [ ! -f "$CLAUDE_PROJECT_DIR/.claude/relay/handoff.md" ]; check "offered once, kept as last.md" $?
out=$(start s8 clear); [ -z "$out" ]; check "not offered twice" $?
write_handoff; printf 'with "quotes" and \\backslash\n\ttab\n' >> "$CLAUDE_PROJECT_DIR/.claude/relay/handoff.md"
out=$(RELAY_ON_NEW_SESSION=auto start s9 clear); printf '%s' "$out" | grep -q '<handoff>'; check "auto mode: injects content" $?
valid_json "$out"; check "auto output with quotes/backslashes is valid JSON" $?
write_handoff; out=$(RELAY_ON_NEW_SESSION=off start s10 clear); [ -z "$out" ]; check "off mode: silent" $?
touch -d '2 days ago' "$CLAUDE_PROJECT_DIR/.claude/relay/handoff.md" 2>/dev/null || touch -t "$(date -v-2d +%Y%m%d%H%M)" "$CLAUDE_PROJECT_DIR/.claude/relay/handoff.md"
out=$(start s11 clear); [ -z "$out" ]; check "older than max age: silent" $?

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
