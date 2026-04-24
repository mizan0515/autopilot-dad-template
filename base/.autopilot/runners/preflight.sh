#!/usr/bin/env bash
# .autopilot/runners/preflight.sh — mirror of preflight.ps1.
# Usage: preflight.sh <AutopilotRoot> [ai]
# Exit 0 if all checks pass; exit 1 + prints "preflight-failed:<reason>" otherwise.

set -uo pipefail

AUTOPILOT_ROOT="${1:-}"
AI="${2:-codex}"

if [ -z "$AUTOPILOT_ROOT" ]; then
  echo "usage: preflight.sh <AutopilotRoot> [ai]" >&2
  exit 2
fi

FAILURES="$AUTOPILOT_ROOT/FAILURES.jsonl"

write_failure() {
  python3 - "$FAILURES" "$@" <<'PY' 2>/dev/null || true
import sys, json, datetime, os
path, *pairs = sys.argv[1:]
row = {'ts': datetime.datetime.now(datetime.timezone.utc).isoformat()}
for pair in pairs:
    k, _, v = pair.partition('=')
    row[k] = v
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, 'a', encoding='utf-8') as f:
    f.write(json.dumps(row, ensure_ascii=False) + '\n')
PY
}

problems=()

# 1. git + origin
if ! git --version >/dev/null 2>&1; then
  problems+=("git-missing")
fi
if ! git remote get-url origin >/dev/null 2>&1; then
  problems+=("git-no-origin")
fi

# 2. gh CLI + auth
if ! command -v gh >/dev/null 2>&1; then
  problems+=("gh-missing")
else
  if ! gh auth status >/dev/null 2>&1; then
    problems+=("gh-auth-failed")
  fi
fi

# 3. AI CLI
case "$AI" in
  codex)
    if ! command -v codex >/dev/null 2>&1 && ! command -v codex.exe >/dev/null 2>&1 && ! command -v codex.cmd >/dev/null 2>&1; then
      problems+=("codex-missing")
    fi
    ;;
  claude)
    if ! command -v claude >/dev/null 2>&1 && ! command -v claude.exe >/dev/null 2>&1 && ! command -v claude.cmd >/dev/null 2>&1; then
      problems+=("claude-missing")
    fi
    ;;
  custom) ;;
  *) problems+=("unknown-ai:$AI") ;;
esac

if [ "${#problems[@]}" -gt 0 ]; then
  reason="$(IFS=, ; echo "${problems[*]}")"
  echo "[preflight] FAILED: $reason" >&2
  write_failure "event=preflight" "result=failed" "reason=$reason" "ai=$AI"
  echo "preflight-failed:$reason"
  exit 1
fi

echo "[preflight] OK (ai=$AI)" >&2
echo "preflight-ok"
exit 0
