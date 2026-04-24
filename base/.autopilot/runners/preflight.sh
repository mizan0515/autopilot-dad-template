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

# 4. PROMPT.md exists (Row 12: empty-prompt infinite loop)
if [ ! -f "$AUTOPILOT_ROOT/PROMPT.md" ]; then
  problems+=("prompt-missing")
fi

# 5. Optional project-specific verify hook (Row 8 slot — static config)
if [ -x "$AUTOPILOT_ROOT/hooks/preflight-verify.sh" ]; then
  if ! "$AUTOPILOT_ROOT/hooks/preflight-verify.sh" "$AUTOPILOT_ROOT"; then
    problems+=("verify-hook-failed")
  fi
fi

# 6. Optional runtime-bridge hook — responsive probe for external tools
#    (Unity MCP, Claude Preview, DB, etc.). Soft-fail only: doctor-green
#    does not mean responsive. A failure here does not abort the iter but
#    is logged so the loop can mark runtime-evidence as untrustworthy.
if [ -x "$AUTOPILOT_ROOT/hooks/preflight-runtime-bridge.sh" ]; then
  if ! "$AUTOPILOT_ROOT/hooks/preflight-runtime-bridge.sh" "$AUTOPILOT_ROOT"; then
    write_failure "event=preflight-runtime-bridge" "result=unresponsive" "ai=$AI"
    echo "[preflight] runtime-bridge unresponsive — doc-only iter recommended" >&2
  fi
fi

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
