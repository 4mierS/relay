#!/usr/bin/env bash
# Shared helpers for relay hooks. Dependency-free: bash + coreutils + sed/grep/awk.

# --- config -----------------------------------------------------------------
# Precedence: RELAY_<KEY> env > plugin userConfig (CLAUDE_PLUGIN_OPTION_<KEY>) > default.
cfg() {
  local key="$1" default="$2" upper val
  upper=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')
  val=$(printenv "RELAY_$upper" 2>/dev/null)
  [ -z "$val" ] && val=$(printenv "CLAUDE_PLUGIN_OPTION_$upper" 2>/dev/null)
  [ -z "$val" ] && val="$default"
  printf '%s' "$val"
}

int_or() { case "$1" in ''|*[!0-9]*) printf '%s' "$2" ;; *) printf '%s' "$1" ;; esac; }

# --- hook input -------------------------------------------------------------
# Extract a top-level string field from the hook's JSON input ($INPUT).
# Windows paths arrive as C:\\Users\\... and are normalized to forward slashes.
json_str() {
  printf '%s' "$INPUT" | tr -d '\r\n' \
    | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" \
    | sed 's/\\\\/\//g' | head -n 1
}

json_true() {
  printf '%s' "$INPUT" | tr -d '\r\n' | grep -q "\"$1\"[[:space:]]*:[[:space:]]*true"
}

# --- output -----------------------------------------------------------------
# Escape stdin as the inside of a JSON string.
json_escape() {
  tr -d '\000-\010\013\014\016-\037' | tr '\t' ' ' | sed -e 's/\r$//' -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
    | awk 'NR > 1 { printf "\\n" } { printf "%s", $0 }'
}

# Decode a JSON string body (without surrounding quotes) from stdin.
# LC_ALL=C makes %c emit raw bytes in every awk, so \uXXXX can be encoded as UTF-8.
json_unescape() {
  LC_ALL=C awk '
    function hex(h,   i, v) { v = 0; for (i = 1; i <= 4; i++) v = v * 16 + index("0123456789abcdef", tolower(substr(h, i, 1))) - 1; return v }
    function utf8(v) {
      if (v < 128) return (v >= 32 || v == 10 || v == 9) ? sprintf("%c", v) : ""
      if (v < 2048) return sprintf("%c%c", 192 + int(v / 64), 128 + v % 64)
      if (v < 65536) return sprintf("%c%c%c", 224 + int(v / 4096), 128 + int(v / 64) % 64, 128 + v % 64)
      return sprintf("%c%c%c%c", 240 + int(v / 262144), 128 + int(v / 4096) % 64, 128 + int(v / 64) % 64, 128 + v % 64)
    }
    {
      s = $0; n = length(s); out = ""; i = 1
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\\" && i < n) {
          d = substr(s, i + 1, 1); i += 2
          if (d == "n") out = out "\n"; else if (d == "t") out = out "\t"
          else if (d == "\"" || d == "\\" || d == "/") out = out d
          else if (d == "u") {
            v = hex(substr(s, i, 4)); i += 4
            # Surrogate pair: 😀 -> one code point.
            if (v >= 55296 && v < 56320 && substr(s, i, 2) == "\\u") { v = 65536 + (v - 55296) * 1024 + hex(substr(s, i + 2, 4)) - 56320; i += 6 }
            out = out utf8(v)
          }
        } else { out = out c; i++ }
      }
      printf "%s", out
    }'
}

# --- context size -----------------------------------------------------------
# Tokens in context after the last main-thread assistant message of a transcript.
context_tokens() {
  local transcript="$1" line n total=0 key
  [ -f "$transcript" ] || { echo 0; return; }
  line=$(grep '"usage"' "$transcript" | grep '"type":"assistant"' \
    | grep -v '"isSidechain":true' | grep -v '"model":"<synthetic>"' | tail -n 1)
  for key in input_tokens cache_creation_input_tokens cache_read_input_tokens output_tokens; do
    n=$(printf '%s' "$line" | sed -n "s/.*\"$key\":\([0-9][0-9]*\).*/\1/p")
    total=$((total + $(int_or "$n" 0)))
  done
  echo "$total"
}

# --- files ------------------------------------------------------------------
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

project_dir() {
  local d="${CLAUDE_PROJECT_DIR:-$(json_str cwd)}"
  printf '%s' "${d:-$PWD}" | sed 's/\\/\//g'
}

# .claude/relay/ inside the project, ignored by git.
relay_dir() {
  local d
  d="$(project_dir)/.claude/relay"
  mkdir -p "$d" 2>/dev/null
  [ -f "$d/.gitignore" ] || printf '*\n' > "$d/.gitignore" 2>/dev/null
  printf '%s' "$d"
}

state_dir() {
  local d="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/relay-data}"
  d="$(printf '%s' "$d" | sed 's/\\/\//g')/state"
  mkdir -p "$d" 2>/dev/null
  printf '%s' "$d"
}

safe_id() { printf '%s' "$1" | tr -cd 'A-Za-z0-9_-'; }

human_age() {
  local s="$1"
  if [ "$s" -lt 3600 ]; then echo "$(( (s + 59) / 60 )) min"
  elif [ "$s" -lt 172800 ]; then echo "$(( s / 3600 )) h"
  else echo "$(( s / 86400 )) days"
  fi
}
