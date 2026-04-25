#!/usr/bin/env bash
# .autopilot/runners/runner.sh — infinite Unix runner.
#
# Loop: create or refresh one reusable detached automation worktree -> submit
# PROMPT.md -> clean up if the worktree is clean -> sleep NEXT_DELAY -> repeat.

set -uo pipefail
cd "$(dirname "$0")/../.."

resolve_cmd() {
  local name="$1"
  command -v "$name" 2>/dev/null || command -v "${name}.exe" 2>/dev/null || command -v "${name}.cmd" 2>/dev/null
}

ROOT="$PWD"
AP="$ROOT/.autopilot"
HALT="$AP/HALT"
DELAY="$AP/NEXT_DELAY"
RUNNER_STATE="$AP/RUNNER-LIVE.json"
PROJECT_SCRIPT="$AP/project.ps1"
PROMPT_RELATIVE="${AUTOPILOT_PROMPT_RELATIVE:-.autopilot/PROMPT.md}"

get_worktree_base() {
  if [ -n "${AUTOPILOT_WORKTREE_DIR:-}" ]; then
    printf '%s\n' "$AUTOPILOT_WORKTREE_DIR"
    return
  fi
  parent="$(dirname "$ROOT")"
  leaf="$(basename "$ROOT")"
  printf '%s\n' "$parent/$leaf-autopilot-runner"
}

write_runner_state() {
  local phase="$1"
  local run_root="${2:-}"
  local note="${3:-}"
  local last_exit="${4:-0}"
  # Round-3 F33: `date -Is` is GNU-only. macOS BSD date rejects -Is and the
  # heredoc would expand to an empty `ts` field, breaking JSON. Use the
  # POSIX-portable `date -u +%Y-%m-%dT%H:%M:%SZ` which produces a valid
  # ISO 8601 / RFC 3339 timestamp on both GNU and BSD.
  cat >"$RUNNER_STATE" <<EOF
{
  "ts": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "ai": "$AI",
  "phase": "$phase",
  "run_root": "${run_root//\\/\\\\}",
  "note": "${note//\"/\\\"}",
  "last_exit_code": $last_exit,
  "worktree_base": "$(get_worktree_base | sed 's/\\/\\\\/g')"
}
EOF
  # Round-3 F23: previously invoked `status-kr -RunRoot ... -Phase ... -Note
  # ... -ExitCode ...` but project.ps1's ValidateSet does not include
  # `status-kr` and has no such named params. Every call was a silent
  # parameter-binding failure swallowed by `>/dev/null`, so OPERATOR-LIVE.html
  # was never refreshed. The phase/note context already lives in
  # RUNNER-LIVE.json (just written above) which `status` reads, so the extra
  # args were redundant anyway. Try pwsh first (cross-platform), fall through
  # to powershell.exe on Windows-with-old-shells.
  status_runner=""
  if resolve_cmd pwsh >/dev/null; then status_runner="pwsh"
  elif resolve_cmd powershell >/dev/null; then status_runner="powershell"
  fi
  if [ -n "$status_runner" ] && [ -f "$PROJECT_SCRIPT" ]; then
    if ! "$status_runner" -NoProfile -ExecutionPolicy Bypass -File "$PROJECT_SCRIPT" status >/dev/null 2>&1; then
      echo "[autopilot] dashboard refresh failed (project.ps1 status); continuing." >&2
    fi
  fi
}

new_iteration_worktree() {
  local base
  base="$(get_worktree_base)"
  mkdir -p "$base"
  git fetch origin main --prune >/dev/null
  git worktree prune >/dev/null
  local run_root="$base/live"
  if [ -d "$run_root" ]; then
    git worktree remove --force "$run_root" >/dev/null 2>&1 || rm -rf "$run_root"
  fi
  git worktree add --detach "$run_root" origin/main >/dev/null
  printf '%s\n' "$run_root"
}

finalize_iteration_worktree() {
  local run_root="$1"
  if [ ! -d "$run_root" ]; then
    printf 'missing\n'
    return
  fi
  if [ -n "$(git -C "$run_root" status --porcelain 2>/dev/null)" ]; then
    printf 'retained-dirty\n'
    return
  fi
  git worktree remove --force "$run_root" >/dev/null
  local parent
  parent="$(dirname "$run_root")"
  rmdir "$parent" >/dev/null 2>&1 || true
  printf 'removed-clean\n'
}

# Resolve the autopilot AI in this priority order:
#   1. $AUTOPILOT_AI  (per-shell override)
#   2. .autopilot/config.json's `autopilot_ai` (operator's apply choice)
#   3. 'codex' (template default)
# Round-3 F14: config.json.autopilot_ai was written by apply.{ps1,sh} but
# never consumed — operators who answered "claude" still got codex
# preflight + execution unless they also exported AUTOPILOT_AI.
if [ -n "${AUTOPILOT_AI:-}" ]; then
  AI="$AUTOPILOT_AI"
else
  AI=""
  cfg_path="$(dirname "$0")/../config.json"
  if [ -f "$cfg_path" ]; then
    if command -v jq >/dev/null 2>&1; then
      AI="$(jq -r '.autopilot_ai // empty' "$cfg_path" 2>/dev/null || true)"
    else
      # jq-less fallback: extract "autopilot_ai": "<value>"
      AI="$(sed -n 's/.*"autopilot_ai"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$cfg_path" | head -1)"
    fi
  fi
  [ -z "$AI" ] && AI="codex"
fi
CODEX_CMD="$(resolve_cmd codex || true)"
CLAUDE_CMD="$(resolve_cmd claude || true)"

# Timeout for single AI CLI invocation (min). Clamp [5, 120], default 25.
LLM_TIMEOUT_MIN="${AUTOPILOT_LLM_TIMEOUT_MIN:-25}"
[[ "$LLM_TIMEOUT_MIN" =~ ^[0-9]+$ ]] || LLM_TIMEOUT_MIN=25
[ "$LLM_TIMEOUT_MIN" -lt 5 ] && LLM_TIMEOUT_MIN=5
[ "$LLM_TIMEOUT_MIN" -gt 120 ] && LLM_TIMEOUT_MIN=120

# Consecutive-stall HALT threshold (clamp >=2, default 5).
STALL_HALT_THRESHOLD="${AUTOPILOT_STALL_HALT_THRESHOLD:-5}"
[[ "$STALL_HALT_THRESHOLD" =~ ^[0-9]+$ ]] || STALL_HALT_THRESHOLD=5
[ "$STALL_HALT_THRESHOLD" -lt 2 ] && STALL_HALT_THRESHOLD=2

CONSECUTIVE_STALLS=0

echo "[autopilot] AI=$AI"
echo "[autopilot] worktree base=$(get_worktree_base)"
echo "[autopilot] prompt=$PROMPT_RELATIVE"
echo "[autopilot] LLM timeout=${LLM_TIMEOUT_MIN} min"
echo "[autopilot] consecutive-stall HALT threshold=$STALL_HALT_THRESHOLD"
write_runner_state "startup" "" "러너를 시작했습니다." 0

while :; do
  if [ -f "$HALT" ]; then
    echo "[autopilot] HALT present. Stopping."
    write_runner_state "halted" "" "HALT 파일이 있어 러너를 종료했습니다." 0
    break
  fi

  iter_start=$(date +%s)
  run_root=""
  ai_exit=0
  llm_timed_out=0
  preflight_failed=0
  echo "[autopilot] iter start $(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # --- Preflight --------------------------------------------------------
  preflight_script="$(cd "$(dirname "$0")" && pwd)/preflight.sh"
  preflight_ap_root="$(cd "$(dirname "$0")/.." && pwd)"
  if [ -f "$preflight_script" ]; then
    pf_output="$(bash "$preflight_script" "$preflight_ap_root" "$AI" 2>&1 || true)"
    pf_final="$(printf '%s\n' "$pf_output" | tail -n 1 | tr -d '[:space:]')"
    echo "[autopilot] preflight: $pf_final"
    if [ "$pf_final" != "preflight-ok" ]; then
      preflight_failed=1
      ai_exit=2
      write_runner_state "preflight-failed" "" "환경 점검 실패: $pf_final" 2
    fi
  fi

  if [ $preflight_failed -eq 0 ]; then
    run_root="$(new_iteration_worktree)"
    prompt="$run_root/$PROMPT_RELATIVE"
    [ -f "$prompt" ] || { echo "Missing $prompt" >&2; ai_exit=1; }
  fi

  if [ $preflight_failed -eq 0 ] && [ $ai_exit -eq 0 ]; then
    write_runner_state "running" "$run_root" "새 자동 전용 작업 폴더에서 한 번 실행 중입니다." 0
    # Hard-timeout the AI CLI. GNU timeout works on Linux/macOS/WSL/Git-Bash.
    TIMEOUT_CMD=""
    if command -v timeout >/dev/null 2>&1; then
      TIMEOUT_CMD="timeout --kill-after=30s ${LLM_TIMEOUT_MIN}m"
    elif command -v gtimeout >/dev/null 2>&1; then
      TIMEOUT_CMD="gtimeout --kill-after=30s ${LLM_TIMEOUT_MIN}m"
    fi
    case "$AI" in
      codex)
        [ -n "$CODEX_CMD" ] || { echo "codex command not found" >&2; exit 2; }
        if [ -n "${AUTOPILOT_CODEX_ARGS:-}" ]; then
          # shellcheck disable=SC2086
          cat "$prompt" | $TIMEOUT_CMD "$CODEX_CMD" exec -C "$run_root" --dangerously-bypass-approvals-and-sandbox - $AUTOPILOT_CODEX_ARGS
        else
          cat "$prompt" | $TIMEOUT_CMD "$CODEX_CMD" exec -C "$run_root" --dangerously-bypass-approvals-and-sandbox -
        fi
        ai_exit=$?
        ;;
      claude)
        [ -n "$CLAUDE_CMD" ] || { echo "claude command not found" >&2; exit 2; }
        cat "$prompt" | $TIMEOUT_CMD "$CLAUDE_CMD" --print
        ai_exit=$?
        ;;
      custom)
        AUTOPILOT_PROMPT_FILE="$prompt" $TIMEOUT_CMD bash -c "$AUTOPILOT_CMD"
        ai_exit=$?
        ;;
      *)
        echo "Unknown AUTOPILOT_AI=$AI" >&2
        ai_exit=2
        ;;
    esac
    # `timeout` exits 124 on timeout, 137 on SIGKILL after kill-after.
    if [ "$ai_exit" -eq 124 ] || [ "$ai_exit" -eq 137 ]; then
      llm_timed_out=1
      echo "[autopilot] AI call exceeded ${LLM_TIMEOUT_MIN} min — killed (exit $ai_exit)." >&2
      python3 - "$preflight_ap_root/FAILURES.jsonl" "$AI" "$LLM_TIMEOUT_MIN" <<'PY' 2>/dev/null || true
import sys, json, datetime, os
path, ai, tmin = sys.argv[1:]
row = {'ts': datetime.datetime.now(datetime.timezone.utc).isoformat(),
       'event': 'llm-timeout', 'ai': ai, 'timeout_min': int(tmin)}
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, 'a', encoding='utf-8') as f:
    f.write(json.dumps(row, ensure_ascii=False) + '\n')
PY
    fi
  fi

  final_state="$(finalize_iteration_worktree "$run_root")"

  # Stalled-fallback: iter left worktree dirty. Snapshot files, try WIP commit
  # + push + draft PR so work is not lost and the operator sees the stall.
  if [ "$final_state" = "retained-dirty" ] && [ -n "$run_root" ]; then
    fallback_script="$(cd "$(dirname "$0")" && pwd)/stalled-fallback.sh"
    fallback_ap_root="$(cd "$(dirname "$0")/.." && pwd)"
    if [ -f "$fallback_script" ]; then
      write_runner_state "stalled-fallback" "$run_root" "워크트리가 dirty로 남아 자동 WIP 구조를 시도합니다." 0
      fb_output="$(bash "$fallback_script" "$run_root" "$fallback_ap_root" 0 2>&1 || true)"
      fb_final="$(printf '%s\n' "$fb_output" | tail -n 1 | tr -d '[:space:]')"
      echo "[autopilot] stalled-fallback result: $fb_final"
      case "$fb_final" in
        wip-rescued|wip-local-only-snapshotted|wip-commit-failed-snapshotted|wip-failed-no-snapshot)
          final_state="$fb_final"
          ;;
      esac
    fi
  fi

  # DAD dispatch: drain any tasks the autopilot queued during its turn. See
  # .autopilot/dispatch/README.md for the protocol.
  dispatcher="$(cd "$(dirname "$0")" && pwd)/dispatch.sh"
  autopilot_root="$(cd "$(dirname "$0")/.." && pwd)"
  unity_root="$(cd "$autopilot_root/.." && pwd)"
  if [[ -x "$dispatcher" ]]; then
    "$dispatcher" "$autopilot_root" "$unity_root" || echo "[autopilot] dispatcher error (continuing)" >&2
  elif [[ -f "$dispatcher" ]]; then
    bash "$dispatcher" "$autopilot_root" "$unity_root" || echo "[autopilot] dispatcher error (continuing)" >&2
  fi

  # Phase 6: probation gate — detect regressions from recent self-mods.
  probation_gate="$(cd "$(dirname "$0")" && pwd)/probation-gate.sh"
  if [[ -f "$probation_gate" ]]; then
    bash "$probation_gate" "$autopilot_root" || echo "[autopilot] probation-gate error (continuing)" >&2
  fi

  # Consecutive-stall tracking
  is_stall=0
  if [ $preflight_failed -eq 1 ] || [ $llm_timed_out -eq 1 ]; then
    is_stall=1
  fi
  case "$final_state" in
    wip-commit-failed-snapshotted|wip-failed-no-snapshot) is_stall=1 ;;
  esac
  if [ $is_stall -eq 1 ]; then
    CONSECUTIVE_STALLS=$((CONSECUTIVE_STALLS + 1))
    echo "[autopilot] consecutive stalls: $CONSECUTIVE_STALLS / $STALL_HALT_THRESHOLD"
    if [ $CONSECUTIVE_STALLS -ge $STALL_HALT_THRESHOLD ]; then
      halt_reason="연속 $CONSECUTIVE_STALLS 회 stall 로 runner 자동 HALT. 최근: $final_state. 원인 확인 후 .autopilot/HALT 파일을 삭제하고 재시작."
      printf '%s\n' "$halt_reason" > "$HALT"
      echo "[autopilot] $halt_reason"
      python3 - "$preflight_ap_root/FAILURES.jsonl" "$CONSECUTIVE_STALLS" "$STALL_HALT_THRESHOLD" "$final_state" <<'PY' 2>/dev/null || true
import sys, json, datetime, os
path, cs, thr, fs = sys.argv[1:]
row = {'ts': datetime.datetime.now(datetime.timezone.utc).isoformat(),
       'event': 'consecutive-stall-halt',
       'consecutive': int(cs), 'threshold': int(thr), 'final_state': fs}
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, 'a', encoding='utf-8') as f:
    f.write(json.dumps(row, ensure_ascii=False) + '\n')
PY
      write_runner_state "halted" "$run_root" "$halt_reason" "$ai_exit"
      break
    fi
  else
    CONSECUTIVE_STALLS=0
  fi

  case "$final_state" in
    removed-clean)
      sleep_phase="sleeping"
      sleep_note="방금 실행은 깨끗하게 끝났고, 자동 전용 작업 폴더를 정리했습니다."
      ;;
    retained-dirty)
      sleep_phase="retained-dirty"
      sleep_note="마지막 실행 결과가 남아 있어 자동 전용 작업 폴더를 보존했습니다. 사용자 작업 폴더는 건드리지 않습니다."
      ;;
    wip-rescued)
      sleep_phase="wip-rescued"
      sleep_note="iter가 dirty로 끝나서 runner가 자동 WIP commit + draft PR을 만들어 변경을 구조했습니다."
      ;;
    wip-local-only-snapshotted)
      sleep_phase="wip-local-only"
      sleep_note="WIP commit은 만들었지만 push 또는 PR 생성이 실패했습니다. .autopilot/stalled/ 스냅샷을 확인하세요."
      ;;
    wip-commit-failed-snapshotted)
      sleep_phase="wip-commit-failed"
      sleep_note="자동 WIP commit이 pre-commit 훅 등에서 실패했지만 스냅샷은 .autopilot/stalled/에 저장됐습니다."
      ;;
    wip-failed-no-snapshot)
      sleep_phase="wip-failed"
      sleep_note="자동 WIP 구조가 전부 실패했습니다. .autopilot/FAILURES.jsonl을 확인하세요."
      ;;
    *)
      sleep_phase="sleeping"
      sleep_note="작업 폴더 정리 상태: $final_state"
      ;;
  esac

  if [ $preflight_failed -eq 1 ]; then
    sleep_phase="preflight-failed"
    sleep_note="환경 점검(preflight) 실패로 이번 iter를 건너뜁니다. gh auth / codex / claude 상태를 확인하세요."
  elif [ $llm_timed_out -eq 1 ]; then
    sleep_phase="llm-timeout"
    sleep_note="AI CLI가 ${LLM_TIMEOUT_MIN}분 안에 끝나지 않아 강제 종료했습니다. 다음 iter가 다시 시도합니다."
  fi

  write_runner_state "$sleep_phase" "$run_root" "$sleep_note" "$ai_exit"

  sleep_for=900
  if [ -f "$DELAY" ]; then
    raw="$(tr -d '[:space:]' < "$DELAY")"
    if [[ "$raw" =~ ^[0-9]+$ ]]; then
      sleep_for="$raw"
      [ "$sleep_for" -lt 60 ] && sleep_for=60
      [ "$sleep_for" -gt 3600 ] && sleep_for=3600
    fi
  fi

  dur=$(( $(date +%s) - iter_start ))
  echo "[autopilot] iter took ${dur}s; sleeping ${sleep_for}s"
  write_runner_state "$sleep_phase" "$run_root" "최근 실행 시간 ${dur}초, 다음 대기 ${sleep_for}초" "$ai_exit"
  sleep "$sleep_for"
done
