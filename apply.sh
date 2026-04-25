#!/usr/bin/env bash
# apply.sh — autopilot-dad-template installer (Unix).
#
# Usage:
#   ./apply.sh                                     # interactive — asks language, name, directive, PRD, relay
#   ./apply.sh --language en --name "My Project"   # scripted
#   AUTOPILOT_TEMPLATE_URL=... ./apply.sh          # override template source
#
# Supported languages: en (default), ko, ja, zh-CN, es, fr, de, custom
#   - For locales not shipped under locales/<lang>/, apply copies locales/en/ and marks
#     the operator_language in config.json so the agent knows to render in that language.

set -euo pipefail

LANG_ARG=""
NAME_ARG=""
DESC_ARG=""
DIRECTIVE_ARG=""
PRD_ARG=""
RELAY_ARG=""
AI_ARG=""
NON_INTERACTIVE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --language|-l) LANG_ARG="$2"; shift 2 ;;
    --name|-n)     NAME_ARG="$2"; shift 2 ;;
    --description) DESC_ARG="$2"; shift 2 ;;
    --directive)   DIRECTIVE_ARG="$2"; shift 2 ;;
    --prd)         PRD_ARG="$2"; shift 2 ;;
    --relay)       RELAY_ARG="$2"; shift 2 ;;
    --ai)          AI_ARG="$2"; shift 2 ;;
    --yes|-y)      NON_INTERACTIVE=1; shift ;;
    -h|--help)
      sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Round-3 F20: validate --ai if given; otherwise auto-detect by probing CLIs.
case "$AI_ARG" in
  ''|claude|codex|custom) : ;;
  *) echo "[apply] error: --ai must be one of claude|codex|custom (got: $AI_ARG)" >&2; exit 2 ;;
esac

TEMPLATE_URL="${AUTOPILOT_TEMPLATE_URL:-https://github.com/mizan0515/autopilot-dad-template.git}"
TARGET="$(pwd)"
CONFLICTS="$TARGET/.apply-conflicts"
TEMPLATE_VERSION="v0"

if [ ! -d "$TARGET/.git" ]; then
  echo "[apply] error: $TARGET is not a git repo. Run 'git init' first." >&2
  exit 1
fi

# --- PRD auto-detection ---------------------------------------------------
detect_prd() {
  local root="$1"
  local candidates=(
    "PRD.md"
    "docs/PRD.md"
    "Document/PRD.md"
    "게임 규칙 명세서.md"
    "Document/게임 규칙 명세서.md"
    "ROADMAP.md"
    "product.md"
    "README.md"
    "Document/개발 계획서.md"
  )
  for c in "${candidates[@]}"; do
    if [ -f "$root/$c" ]; then
      printf '%s' "$c"
      return 0
    fi
  done
  printf ''
}

# --- interactive prompts --------------------------------------------------
prompt_if_empty() {
  local var_name="$1"
  local question="$2"
  local default_value="${3:-}"
  local current="${!var_name}"
  if [ -n "$current" ] || [ -n "$NON_INTERACTIVE" ]; then
    return
  fi
  if [ -n "$default_value" ]; then
    read -r -p "$question [$default_value]: " ans
    ans="${ans:-$default_value}"
  else
    read -r -p "$question: " ans
  fi
  printf -v "$var_name" '%s' "$ans"
}

echo "[apply] autopilot-dad-template installer"
echo ""
echo "Supported operator languages: en (default), ko, ja, zh-CN, es, fr, de"
echo "(Others work too — apply falls back to English templates but the agent will"
echo " render status lines and dashboard text in your chosen language.)"
echo ""
prompt_if_empty LANG_ARG      "Operator language (BCP-47, e.g. en, ko, ja)" "en"
prompt_if_empty NAME_ARG      "Project name"                                 "$(basename "$TARGET")"
prompt_if_empty DESC_ARG      "One-line project description"                 "(to be filled in)"
prompt_if_empty DIRECTIVE_ARG "Product directive (one paragraph)"            "Ship a working v1. Focus on user value; avoid premature abstraction."

PRD_DETECTED="$(detect_prd "$TARGET")"
prompt_if_empty PRD_ARG       "PRD / product doc path (auto-detected: '$PRD_DETECTED')" "$PRD_DETECTED"
prompt_if_empty RELAY_ARG     "Relay repo path (optional; leave empty if none)"         ""

if [ -z "$PRD_ARG" ]; then
  PRD_DISPLAY="(no PRD detected — declare in config.json doc_priority)"
else
  PRD_DISPLAY="$PRD_ARG"
fi
if [ -z "$RELAY_ARG" ]; then
  RELAY_DISPLAY="(relay not installed on this machine)"
else
  RELAY_DISPLAY="$RELAY_ARG"
fi

GUARDRAILS_BLOCK="_(Operator: declare project-specific guardrails here. The autopilot loop will fill this in as it learns the project.)_"

# --- fetch template -------------------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
echo "[apply] fetching template from $TEMPLATE_URL"
git clone --depth 1 "$TEMPLATE_URL" "$WORK/template" >/dev/null 2>&1

TPL_BASE="$WORK/template/base"
TPL_LOC="$WORK/template/locales/$LANG_ARG"
if [ ! -d "$TPL_LOC" ]; then
  echo "[apply] locale '$LANG_ARG' not shipped; using locales/en/ as fallback."
  TPL_LOC="$WORK/template/locales/en"
fi

mkdir -p "$CONFLICTS"
conflict_count=0

copy_tree() {
  local src="$1"
  local exclude="${2:-}"  # comma-separated list of relative paths to skip
  if [ ! -d "$src" ]; then return; fi
  ( cd "$src" && find . -type f -print0 ) | while IFS= read -r -d '' rel; do
    rel="${rel#./}"
    if [ -n "$exclude" ]; then
      case ",$exclude," in
        *",$rel,"*)
          echo "[apply] skip (locale-root, copied separately): $rel"
          continue
          ;;
      esac
    fi
    local dst="$TARGET/$rel"
    if [ -e "$dst" ]; then
      if ! cmp -s "$src/$rel" "$dst"; then
        mkdir -p "$(dirname "$CONFLICTS/$rel")"
        cp "$src/$rel" "$CONFLICTS/$rel"
        conflict_count=$((conflict_count + 1))
        echo "[apply] conflict: $rel (saved to .apply-conflicts/)"
      fi
    else
      mkdir -p "$(dirname "$dst")"
      cp "$src/$rel" "$dst"
      echo "[apply] installed: $rel"
    fi
  done
}

copy_tree "$TPL_BASE"
# Skip locale-root strings.json — copied explicitly to .autopilot/locales/ below
# (round-3 dogfood F2: was bleeding to target repo root).
copy_tree "$TPL_LOC" "strings.json"

# --- config.json ----------------------------------------------------------
CFG="$TARGET/.autopilot/config.json"
if [ -f "$CFG" ]; then
  echo "[apply] existing config.json preserved at $CFG"
else
  # F20: resolve autopilot_ai. Priority: --ai → probe CLIs → fallback claude.
  RESOLVED_AI="$AI_ARG"
  if [ -z "$RESOLVED_AI" ]; then
    if command -v claude >/dev/null 2>&1 && claude --version >/dev/null 2>&1; then
      RESOLVED_AI="claude"
    elif command -v codex >/dev/null 2>&1 && codex --version >/dev/null 2>&1; then
      RESOLVED_AI="codex"
    else
      RESOLVED_AI="claude"
      echo "[apply] neither claude nor codex CLI detected on PATH; defaulting autopilot_ai='claude'. Edit .autopilot/config.json after install if you actually use codex."
    fi
  fi
  echo "[apply] autopilot_ai=$RESOLVED_AI"

  mkdir -p "$TARGET/.autopilot"
  python3 - "$CFG" "$TARGET" "$NAME_ARG" "$DESC_ARG" "$DIRECTIVE_ARG" "$LANG_ARG" "$PRD_ARG" "$RELAY_ARG" "$TEMPLATE_VERSION" "$RESOLVED_AI" <<'PY'
import json, os, sys, pathlib
path, target, name, desc, directive, lang, prd, relay, tpl_ver, ai = sys.argv[1:]

# Round-3 F17: search_roots used to be a static array including Unity-only
# `Assets/Scripts`/`Assets/Tests`. Now auto-detect.
always_present = ['.autopilot', '.agents', '.prompts', 'tools']
candidates = ['src','lib','tests','test','docs','Document','app','pkg','internal','cmd','Assets/Scripts','Assets/Tests']
detected = [c for c in candidates if pathlib.Path(target, c).exists()]
search_roots = detected + always_present

# Round-3 F15: sensitive_delete_paths exposed as config so non-Unity projects
# don't get checks against paths that don't exist.
sensitive = ['Document/']  # universal — every DAD project has Document/dialogue/
for u in ['Assets/Scripts/','Assets/Tests/','Assets/Prefabs/','src/','lib/','app/','pkg/','internal/','cmd/']:
    if pathlib.Path(target, u.rstrip('/')).exists():
        sensitive.append(u)

cfg = {
    "project_name": name,
    "project_description": desc,
    "product_directive": directive,
    "operator_language": lang,
    "prd_path": prd,
    "relay_repo_path": relay,
    "search_roots": search_roots,
    "sensitive_delete_paths": sensitive,
    "template_version": tpl_ver,
    "autopilot_ai": ai,
    "next_delay_default": 900,
}
pathlib.Path(path).write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding='utf-8')
PY
  echo "[apply] wrote $CFG"
fi

# --- render PROMPT.md + PROMPT.lite.md placeholders -----------------------
# Both share placeholders; skipping the lite one leaks literal {{...}} the
# moment AUTOPILOT_PROMPT_RELATIVE switches to maintenance mode (round-3 F5).
for pn in PROMPT.md PROMPT.lite.md; do
  PROMPT_PATH="$TARGET/.autopilot/$pn"
  if [ -f "$PROMPT_PATH" ]; then
    python3 - "$PROMPT_PATH" "$NAME_ARG" "$DESC_ARG" "$DIRECTIVE_ARG" "$LANG_ARG" <<'PY'
import sys, pathlib
path, name, desc, directive, lang = sys.argv[1:]
p = pathlib.Path(path)
t = p.read_text(encoding='utf-8')
t = t.replace('{{PROJECT_NAME}}', name)
t = t.replace('{{PROJECT_DESCRIPTION}}', desc)
t = t.replace('{{PRODUCT_DIRECTIVE}}', directive)
t = t.replace('{{OPERATOR_LANGUAGE}}', lang)
p.write_text(t, encoding='utf-8')
PY
    echo "[apply] rendered placeholders in .autopilot/$pn"
  fi
done

# --- render top-level agent MDs (UTF-8 with BOM) --------------------------
for md in PROJECT-RULES.md DIALOGUE-PROTOCOL.md AGENTS.md CLAUDE.md RTK.md; do
  MD_PATH="$TARGET/$md"
  if [ -f "$MD_PATH" ]; then
    python3 - "$MD_PATH" "$NAME_ARG" "$DIRECTIVE_ARG" "$PRD_DISPLAY" "$RELAY_DISPLAY" "$LANG_ARG" "$GUARDRAILS_BLOCK" <<'PY'
import sys, pathlib
path, name, directive, prd, relay, lang, guardrails = sys.argv[1:]
p = pathlib.Path(path)
t = p.read_text(encoding='utf-8')
t = t.replace('{{PROJECT_NAME}}', name)
t = t.replace('{{PROJECT_DIRECTIVE}}', directive)
t = t.replace('{{PRD_PATH}}', prd)
t = t.replace('{{RELAY_REPO_PATH}}', relay)
t = t.replace('{{OPERATOR_LANG}}', lang)
t = t.replace('{{PROJECT_GUARDRAILS_BLOCK}}', guardrails)
# Agent-facing Markdown must be UTF-8 with BOM (see PROJECT-RULES.md).
p.write_bytes(b'\xef\xbb\xbf' + t.encode('utf-8'))
PY
    echo "[apply] rendered placeholders in $md"
  fi
done

# --- locales dir inside target (copy only chosen + en fallback) -----------
mkdir -p "$TARGET/.autopilot/locales/$LANG_ARG" "$TARGET/.autopilot/locales/en"
cp "$WORK/template/locales/en/strings.json" "$TARGET/.autopilot/locales/en/strings.json" 2>/dev/null || true
if [ -d "$WORK/template/locales/$LANG_ARG" ]; then
  cp "$WORK/template/locales/$LANG_ARG/strings.json" "$TARGET/.autopilot/locales/$LANG_ARG/strings.json" 2>/dev/null || true
fi

# --- Codex skill rebranding ----------------------------------------------
# If the template shipped default "cardgame-*" skills, rename them to the
# project's slug and rewrite metadata via Set-CodexSkillNamespace.ps1.
SLUG="$(printf '%s' "$NAME_ARG" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//')"
if [ -z "$SLUG" ]; then SLUG="myproject"; fi
if [ -d "$TARGET/.agents/skills" ] && [ -f "$TARGET/tools/Set-CodexSkillNamespace.ps1" ]; then
  if [ -d "$TARGET/.agents/skills/cardgame-dialogue-start" ] && [ "$SLUG" != "cardgame" ]; then
    echo "[apply] rebranding Codex skills: cardgame-* -> ${SLUG}-*"
    if command -v pwsh >/dev/null 2>&1; then
      pwsh -ExecutionPolicy Bypass -File "$TARGET/tools/Set-CodexSkillNamespace.ps1" -Namespace "$SLUG" -RepoRoot "$TARGET" -ProjectLabel "$NAME_ARG" >/dev/null || echo "[apply] skill rebrand failed (continuing)"
    elif command -v powershell >/dev/null 2>&1; then
      powershell -ExecutionPolicy Bypass -File "$TARGET/tools/Set-CodexSkillNamespace.ps1" -Namespace "$SLUG" -RepoRoot "$TARGET" -ProjectLabel "$NAME_ARG" >/dev/null || echo "[apply] skill rebrand failed (continuing)"
    else
      echo "[apply] pwsh/powershell not found — skipping skill rebrand (you can run tools/Set-CodexSkillNamespace.ps1 -Namespace $SLUG manually)"
    fi
  fi
fi

# --- Relay profile-stub rebranding ---------------------------------------
# Round-3 F24: relay/profile-stub/ ships JSON with `myproject-*` identity ids
# / skill names + a `broker.myproject.json` filename. Set-CodexSkillNamespace
# only touches .agents/skills/, leaving these stubs unchanged. Operators who
# copied them into their forked relay registered identities under wrong
# names and DAD peer routing failed silently for scenario step 6.
RELAY_STUB="$TARGET/relay/profile-stub"
if [ -d "$RELAY_STUB" ] && [ "$SLUG" != "myproject" ]; then
  echo "[apply] rebranding relay profile-stub: myproject -> ${SLUG}"
  for f in "$RELAY_STUB"/*.json; do
    [ -f "$f" ] || continue
    if grep -q "myproject" "$f" 2>/dev/null; then
      python3 -c "
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text(encoding='utf-8')
p.write_text(text.replace('myproject', sys.argv[2]), encoding='utf-8')
" "$f" "$SLUG" 2>/dev/null || sed -i "s/myproject/${SLUG}/g" "$f" 2>/dev/null || true
    fi
  done
  if [ -f "$RELAY_STUB/broker.myproject.json" ] && [ ! -f "$RELAY_STUB/broker.${SLUG}.json" ]; then
    mv "$RELAY_STUB/broker.myproject.json" "$RELAY_STUB/broker.${SLUG}.json"
  fi
fi

# --- hooks ----------------------------------------------------------------
# Prefer top-level .githooks/ (canonical validator chain).
# Fall back to .autopilot/hooks/ for legacy layouts.
if [ -d "$TARGET/.githooks" ]; then
  chmod +x "$TARGET/.githooks/pre-commit" "$TARGET/.githooks/commit-msg" 2>/dev/null || true
  git config core.hooksPath .githooks
  echo "[apply] hooks registered (core.hooksPath=.githooks)"
elif [ -d "$TARGET/.autopilot/hooks" ]; then
  chmod +x "$TARGET/.autopilot/hooks/"*.sh "$TARGET/.autopilot/hooks/pre-commit" "$TARGET/.autopilot/hooks/commit-msg" 2>/dev/null || true
  git config core.hooksPath .autopilot/hooks
  echo "[apply] hooks registered (core.hooksPath=.autopilot/hooks)"
fi

# Round-3 F26: ensure all shipped .sh / hook scripts are stored in the
# operator's git index with mode 100755 (executable). Even though `chmod
# +x` worked above on POSIX filesystems, when an apply runs on a Windows
# host (where NTFS has no exec bit and default `core.fileMode=false`),
# `git add` stages files at 100644. `git update-index --chmod=+x` sets
# the index mode independently of host fs and core.fileMode, so the
# operator's eventual `chore: apply` commit publishes correct modes for
# downstream macOS/Linux clones.
EXEC_SCRIPTS=(
  ".githooks/pre-commit"
  ".githooks/commit-msg"
  ".autopilot/runners/preflight.sh"
  ".autopilot/runners/runner.sh"
  ".autopilot/runners/stalled-fallback.sh"
  ".autopilot/hooks/commit-msg-protect.sh"
  ".autopilot/hooks/protect.sh"
  ".autopilot/hooks/pre-commit"
  ".autopilot/hooks/commit-msg"
  "tools/write-utf8-nobom.sh"
)
( cd "$TARGET" && for rel in "${EXEC_SCRIPTS[@]}"; do
    if [ -e "$rel" ]; then
      git add --intent-to-add -- "$rel" 2>/dev/null || true
      git update-index --add --chmod=+x -- "$rel" 2>/dev/null || true
    fi
  done
) || true

# --- cleanup --------------------------------------------------------------
[ "$conflict_count" -eq 0 ] && rmdir "$CONFLICTS" 2>/dev/null || true

echo ""
if [ "$conflict_count" -gt 0 ]; then
  echo "[apply] done with $conflict_count conflict(s). Review .apply-conflicts/."
  if [ "$conflict_count" -ge 5 ]; then
    echo "[apply] STOP: 5+ conflicts. Operator review required." >&2
    exit 2
  fi
else
  echo "[apply] done. No conflicts."
fi

cat <<HINT

Language: $LANG_ARG
Project:  $NAME_ARG
PRD path: $PRD_DISPLAY
Relay:    $RELAY_DISPLAY

Next steps:
  1. Review .autopilot/config.json and .autopilot/BACKLOG.md (replace seed tasks).
  2. Review PROJECT-RULES.md / CLAUDE.md / AGENTS.md at repo root and fill in project-specific guardrails.
  3. git add .autopilot .githooks .github tools .claude .agents .prompts relay PROJECT-RULES.md DIALOGUE-PROTOCOL.md AGENTS.md CLAUDE.md RTK.md Document/ && git commit -m "chore: apply autopilot-dad-template"
  4. Make sure a GitHub remote exists (preflight will fail with 'git-no-origin' otherwise):
       gh repo create <owner>/<name> --source=. --remote=origin --private --push
     or if the repo already exists on GitHub:
       git remote add origin https://github.com/<owner>/<name>.git
       git push -u origin main
  5. First iter: paste .autopilot/RUN.claude-code.md into Claude Code desktop.
  6. (Optional) To enable MCP pass-through + centralized token budget, see relay/SETUP.md.
     Without a relay, DAD still works in user-bridged mode (copy/paste peer prompts).
HINT
