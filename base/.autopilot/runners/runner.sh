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
  cat >"$RUNNER_STATE" <<EOF
{
  "ts": "$(date -Is)",
  "ai": "$AI",
  "phase": "$phase",
  "run_root": "${run_root//\\/\\\\}",
  "note": "${note//\"/\\\"}",
  "last_exit_code": $last_exit,
  "worktree_base": "$(get_worktree_base | sed 's/\\/\\\\/g')"
}
EOF
  if resolve_cmd powershell >/dev/null && [ -f "$PROJECT_SCRIPT" ]; then
    powershell -NoProfile -ExecutionPolicy Bypass -File "$PROJECT_SCRIPT" status-kr -RunRoot "$run_root" -Phase "$phase" -Note "$note" -ExitCode "$last_exit" >/dev/null
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

AI="${AUTOPILOT_AI:-codex}"
CODEX_CMD="$(resolve_cmd codex || true)"
CLAUDE_CMD="$(resolve_cmd claude || true)"

echo "[autopilot] AI=$AI"
echo "[autopilot] worktree base=$(get_worktree_base)"
echo "[autopilot] prompt=$PROMPT_RELATIVE"
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
  echo "[autopilot] iter start $(date -Is)"

  run_root="$(new_iteration_worktree)"
  prompt="$run_root/$PROMPT_RELATIVE"
  [ -f "$prompt" ] || { echo "Missing $prompt" >&2; ai_exit=1; }

  if [ $ai_exit -eq 0 ]; then
    write_runner_state "running" "$run_root" "새 자동 전용 작업 폴더에서 한 번 실행 중입니다." 0
    case "$AI" in
      codex)
        [ -n "$CODEX_CMD" ] || { echo "codex command not found" >&2; exit 2; }
        if [ -n "${AUTOPILOT_CODEX_ARGS:-}" ]; then
          # shellcheck disable=SC2086
          cat "$prompt" | "$CODEX_CMD" exec -C "$run_root" --dangerously-bypass-approvals-and-sandbox - $AUTOPILOT_CODEX_ARGS
        else
          cat "$prompt" | "$CODEX_CMD" exec -C "$run_root" --dangerously-bypass-approvals-and-sandbox -
        fi
        ai_exit=$?
        ;;
      claude)
        [ -n "$CLAUDE_CMD" ] || { echo "claude command not found" >&2; exit 2; }
        cat "$prompt" | "$CLAUDE_CMD" --print
        ai_exit=$?
        ;;
      custom)
        AUTOPILOT_PROMPT_FILE="$prompt" bash -c "$AUTOPILOT_CMD"
        ai_exit=$?
        ;;
      *)
        echo "Unknown AUTOPILOT_AI=$AI" >&2
        ai_exit=2
        ;;
    esac
  fi

  final_state="$(finalize_iteration_worktree "$run_root")"

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

  case "$final_state" in
    removed-clean)
      sleep_phase="sleeping"
      sleep_note="방금 실행은 깨끗하게 끝났고, 자동 전용 작업 폴더를 정리했습니다."
      ;;
    retained-dirty)
      sleep_phase="retained-dirty"
      sleep_note="마지막 실행 결과가 남아 있어 자동 전용 작업 폴더를 보존했습니다. 사용자 작업 폴더는 건드리지 않습니다."
      ;;
    *)
      sleep_phase="sleeping"
      sleep_note="작업 폴더 정리 상태: $final_state"
      ;;
  esac
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
