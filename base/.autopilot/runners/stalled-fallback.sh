#!/usr/bin/env bash
# .autopilot/runners/stalled-fallback.sh
#
# Called by runner.sh when an iter leaves the worktree dirty (retained-dirty).
# Mirror of stalled-fallback.ps1. Never uses --no-verify; if pre-commit is the
# blocker the failure is surfaced loudly, but a snapshot is always attempted
# first so the work is not silently lost.
#
# Usage: stalled-fallback.sh <RunRoot> <AutopilotRoot> [iter]
# Prints final state on the last line of stdout.

set -uo pipefail

RUN_ROOT="${1:-}"
AUTOPILOT_ROOT="${2:-}"
ITER="${3:-0}"

if [ -z "$RUN_ROOT" ] || [ -z "$AUTOPILOT_ROOT" ]; then
  echo "usage: stalled-fallback.sh <RunRoot> <AutopilotRoot> [iter]" >&2
  echo "wip-failed-no-snapshot"
  exit 2
fi

TS="$(date +%Y%m%d-%H%M%S)"
METRICS="$AUTOPILOT_ROOT/METRICS.jsonl"
FAILURES="$AUTOPILOT_ROOT/FAILURES.jsonl"
SNAPSHOT="$AUTOPILOT_ROOT/stalled/$TS"

write_metrics() {
  python3 - "$METRICS" "$ITER" "$@" <<'PY' 2>/dev/null || true
import sys, json, datetime, os
path, iter_s, *pairs = sys.argv[1:]
row = {'ts': datetime.datetime.now(datetime.timezone.utc).isoformat()}
if iter_s and iter_s != '0':
    row['iter'] = int(iter_s)
for pair in pairs:
    k, _, v = pair.partition('=')
    row[k] = v
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, 'a', encoding='utf-8') as f:
    f.write(json.dumps(row, ensure_ascii=False) + '\n')
PY
}

write_failure() {
  python3 - "$FAILURES" "$ITER" "$@" <<'PY' 2>/dev/null || true
import sys, json, datetime, os
path, iter_s, *pairs = sys.argv[1:]
row = {'ts': datetime.datetime.now(datetime.timezone.utc).isoformat()}
if iter_s and iter_s != '0':
    row['iter'] = int(iter_s)
for pair in pairs:
    k, _, v = pair.partition('=')
    row[k] = v
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, 'a', encoding='utf-8') as f:
    f.write(json.dumps(row, ensure_ascii=False) + '\n')
PY
}

if [ ! -d "$RUN_ROOT" ]; then
  echo "[stalled-fallback] missing run-root: $RUN_ROOT" >&2
  write_metrics "event=stalled-fallback" "result=missing-run-root" "run_root=$RUN_ROOT"
  echo "missing-run-root"
  exit 0
fi

STATUS="$(git -C "$RUN_ROOT" status --porcelain 2>/dev/null || true)"
if [ -z "$STATUS" ]; then
  echo "not-dirty"
  exit 0
fi

# --- Step 1: snapshot ------------------------------------------------------
mkdir -p "$SNAPSHOT" || {
  write_failure "event=stalled-fallback" "step=snapshot-mkdir" "error=$?"
  echo "wip-failed-no-snapshot"
  exit 0
}
MANIFEST="$SNAPSHOT/MANIFEST.txt"
printf 'stalled iter %s; source=%s\n' "$TS" "$RUN_ROOT" > "$MANIFEST"

# Parse porcelain output: XY<space><path> or XY<space><old> -> <new>
snap_count=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  rel="${line:3}"
  if [[ "$rel" == *" -> "* ]]; then
    rel="${rel#* -> }"
  fi
  rel="${rel%\"}"; rel="${rel#\"}"
  src="$RUN_ROOT/$rel"
  if [ ! -e "$src" ]; then
    echo "DELETED: $rel" >> "$MANIFEST"
    continue
  fi
  dst="$SNAPSHOT/$rel"
  mkdir -p "$(dirname "$dst")"
  if cp -f "$src" "$dst" 2>/dev/null; then
    echo "COPIED: $rel" >> "$MANIFEST"
    snap_count=$((snap_count + 1))
  else
    echo "COPY-FAILED: $rel" >> "$MANIFEST"
  fi
done <<< "$STATUS"
echo "[stalled-fallback] snapshot saved to $SNAPSHOT ($snap_count files)" >&2

# --- Step 2: WIP commit ----------------------------------------------------
BRANCH="autopilot/wip-rescue-$TS"
COMMIT_MSG_FILE="$(mktemp)"
cat > "$COMMIT_MSG_FILE" <<EOF
wip(autopilot): iter stalled — auto WIP rescue at $TS

runner 가 감지한 자동 구조 commit 이다.
AI CLI 가 clean 한 commit 을 만들지 못한 채 워크트리를 dirty 로 남겨서,
변경 내용을 잃지 않도록 runner 가 대신 올린다.

snapshot: .autopilot/stalled/$TS/
run_root: $RUN_ROOT
EOF

git -C "$RUN_ROOT" add -A >/dev/null 2>&1
COMMIT_OUTPUT="$(git -C "$RUN_ROOT" commit -F "$COMMIT_MSG_FILE" 2>&1)"
COMMIT_RC=$?
rm -f "$COMMIT_MSG_FILE"

if [ $COMMIT_RC -ne 0 ]; then
  echo "[stalled-fallback] commit failed (pre-commit or index):" >&2
  echo "$COMMIT_OUTPUT" >&2
  write_failure "event=stalled-fallback" "step=commit" "error=${COMMIT_OUTPUT:0:400}" "run_root=$RUN_ROOT" "snapshot=$SNAPSHOT"
  write_metrics "event=stalled-fallback" "result=wip-commit-failed-snapshotted" "snapshot=$SNAPSHOT"
  echo "wip-commit-failed-snapshotted"
  exit 0
fi

git -C "$RUN_ROOT" switch -c "$BRANCH" >/dev/null 2>&1 || true

# --- Step 3: push + draft PR ----------------------------------------------
PUSH_OK=0
PR_URL=""
PUSH_OUTPUT="$(git -C "$RUN_ROOT" push -u origin "$BRANCH" 2>&1)"
if [ $? -eq 0 ]; then
  PUSH_OK=1
else
  echo "[stalled-fallback] push failed:" >&2
  echo "$PUSH_OUTPUT" >&2
  write_failure "event=stalled-fallback" "step=push" "error=${PUSH_OUTPUT:0:400}" "branch=$BRANCH"
fi

if [ "$PUSH_OK" -eq 1 ]; then
  PR_BODY="$(cat <<EOF
Runner 자동 구조 commit입니다. iter가 clean한 commit을 만들지 못하고 워크트리를 retained-dirty로 남겨서 runner가 대신 올렸습니다.

변경 내용 검토 후 필요하면 정리/리베이스하여 본격 PR로 만드세요. 필요 없으면 branch와 함께 닫아 주세요.

- snapshot: .autopilot/stalled/$TS/
- run_root: $RUN_ROOT
- iter: $ITER
EOF
)"
  PR_OUTPUT="$(cd "$RUN_ROOT" && gh pr create --draft --base main --head "$BRANCH" \
    --title "wip(autopilot): stalled-iter 자동 WIP 구조 ($TS)" \
    --body "$PR_BODY" 2>&1)"
  if [ $? -eq 0 ]; then
    PR_URL="$(printf '%s\n' "$PR_OUTPUT" | grep -Eo 'https?://[^[:space:]]+' | head -n 1)"
  else
    echo "[stalled-fallback] PR create failed:" >&2
    echo "$PR_OUTPUT" >&2
    write_failure "event=stalled-fallback" "step=pr-create" "error=${PR_OUTPUT:0:400}" "branch=$BRANCH"
  fi
fi

# --- Step 4: clean worktree ------------------------------------------------
git worktree remove --force "$RUN_ROOT" >/dev/null 2>&1 || true

# --- Step 5: final metrics -------------------------------------------------
if [ -n "$PR_URL" ]; then
  FINAL="wip-rescued"
elif [ "$PUSH_OK" -eq 1 ]; then
  FINAL="wip-local-only-snapshotted"
else
  FINAL="wip-local-only-snapshotted"
fi
write_metrics "event=stalled-fallback" "result=$FINAL" "branch=$BRANCH" "pr_url=$PR_URL" "snapshot=$SNAPSHOT" "push_ok=$PUSH_OK"
echo "$FINAL"
