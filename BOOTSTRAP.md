# BOOTSTRAP — autopilot-dad-template orchestrator prompt

Paste the "One-prompt to paste" section below (from `----8<---- BEGIN PROMPT` to `END PROMPT ---->8----`) into Claude Code (or Codex) with the target project directory as the working directory.

The agent will (1) ask for operator language, (2) check prerequisites, (3) run `apply.ps1` / `apply.sh`, (4) seed the backlog, (5) kick off iter 1.

---

## Prerequisites the agent will check (you do not set these up yourself — the agent guides you)

- git, gh (GitHub CLI), PowerShell 7 or bash
- gh authenticated to your GitHub account (the agent runs `gh auth login` if not)
- codex CLI **or** claude CLI (Claude Code desktop ships with `claude`; otherwise install one)
- The target directory is a git repo (the agent runs `git init` if not)

The agent will NOT install core tools (git, gh, pwsh) for you — if any are missing it will stop and give you a copy-paste install command.

---

## One-prompt to paste

----8<---- BEGIN PROMPT

You are the bootstrap operator for the **autopilot-dad-template** (https://github.com/mizan0515/autopilot-dad-template).

Your job is to set up an autonomous autopilot + Dual-Agent Dialogue loop in the current working directory. Follow these steps **in order**. At each step, print a short status line to the operator in their language (once language is known).

### Step 1 — Ask for operator language

Print exactly:

> Which operator language? Examples: `en`, `ko`, `ja`, `zh-CN`, `es`, `fr`, `de`, or any BCP-47 tag. Default: `en`.

Wait for the operator's reply. Accept free-form answers like "English", "한국어", "日本語" and map to the BCP-47 tag. From this point on, all status lines are in that language.

### Step 2 — Prerequisite check

Run each of these and capture the exit code:

```
git --version
gh --version
gh auth status
pwsh -Version   # or: bash --version
```

If `git` or `gh` or a shell (pwsh/bash) is missing, STOP and print in the operator's language:
- Which tool is missing
- The one-line install command for the operator's platform (Windows: `winget install Git.Git`, `winget install GitHub.cli`, `winget install Microsoft.PowerShell` / macOS: `brew install git gh powershell` / Linux: distro-specific)

If `gh auth status` exit code is non-zero, print the install/login hint and run `gh auth login` interactively (the operator will complete it in the browser).

Check for AI CLI (pick whichever is available; prefer `claude`):
```
claude --version     # Claude Code desktop CLI
codex --version      # Codex desktop CLI
```

If neither exists, STOP and explain: "Install Claude Code desktop from https://claude.com/claude-code or Codex desktop from https://chatgpt.com/codex, then re-paste this prompt."

For first-time login detail (desktop vs CLI-only, OAuth flow, corporate-proxy edge cases), point the operator at `docs/cli-login-guide.md` (copied into the target project by `apply` from `locales/<lang>/docs/`).

### Step 3 — Git repo init if needed

```
git rev-parse --is-inside-work-tree
```

If not inside a git repo, run:
```
git init
git config init.defaultBranch main
git checkout -b main 2>nul || git branch -M main
```

### Step 4 — Ask for project details (if not already in conversation context)

Ask the operator three questions in their language. Keep answers short — they are seeds; the operator can edit later.

- **Project name** — defaults to the target directory basename.
- **One-line description** — what the project does.
- **Product directive** — one paragraph. Example: "Ship a playable v1 of a card-climber roguelike within 8 weeks. Prioritize core combat feel over content volume."

Collect `<LANG>`, `<NAME>`, `<DESCRIPTION>`, `<DIRECTIVE>`.

### Step 5 — Fetch and run the installer

Windows:
```
$env:AUTOPILOT_TEMPLATE_URL = 'https://github.com/mizan0515/autopilot-dad-template.git'
$tmp = Join-Path $env:TEMP ("autopilot-bootstrap-" + [Guid]::NewGuid())
git clone --depth 1 $env:AUTOPILOT_TEMPLATE_URL $tmp
& "$tmp/apply.ps1" -Language '<LANG>' -Name '<NAME>' -Description '<DESCRIPTION>' -Directive '<DIRECTIVE>' -Yes
Remove-Item $tmp -Recurse -Force
```

macOS/Linux:
```
export AUTOPILOT_TEMPLATE_URL=https://github.com/mizan0515/autopilot-dad-template.git
tmp=$(mktemp -d)
git clone --depth 1 "$AUTOPILOT_TEMPLATE_URL" "$tmp"
"$tmp/apply.sh" --language "<LANG>" --name "<NAME>" --description "<DESCRIPTION>" --directive "<DIRECTIVE>" --yes
rm -rf "$tmp"
```

If `apply` exits non-zero:
- Exit 1 → not a git repo → run Step 3 then retry.
- Exit 2 → 5+ file conflicts in `.apply-conflicts/` → STOP, print the conflict list, ask operator to resolve manually. Do not proceed.

### Step 6 — Smoke check

After apply succeeds:
```
.autopilot/runners/preflight.ps1
```
(bash equivalent: `./.autopilot/runners/preflight.sh`)

Expected final line: `preflight-ok`. If `preflight-failed:<reason>`, print the reason in the operator's language and stop.

The preflight resolves the autopilot AI from `config.json.autopilot_ai` (which `apply` auto-detected at install time — round-3 F20). You can override with `-Ai claude|codex|custom` (PowerShell) or as the second positional arg in bash if you want to test a different CLI.

### Step 7 — Confirm BACKLOG bootstrap seed is in place

Read `.autopilot/BACKLOG.md`. Confirm it contains a single `[bootstrap]` task whose deliverable is "read PRD.md and rewrite this BACKLOG with 3-5 real tasks". This is what `apply` shipped (round-3 F13). The first autopilot iter will pick this `[bootstrap]` task, read the operator's PRD, and populate the real backlog automatically — you do **not** hand-type seed tasks here.

If the `[bootstrap]` task is missing for any reason (operator hand-edited the seed, partial apply), restore it from `locales/<lang>/.autopilot/BACKLOG.md` in the template repo. Otherwise the first iter has no Active task and stalls.

### Step 8 — Commit the bootstrap

```
git add .autopilot
git commit -m "chore: bootstrap autopilot-dad-template (language=<LANG>)"
```

Do NOT push. The operator decides when to push.

### Step 9 — First iter hand-off

Print to the operator, in their language:

> Bootstrap done. To start the autopilot loop, paste `.autopilot/RUN.claude-code.md` (or `.autopilot/RUN.codex-desktop.md`) into Claude Code / Codex desktop. It will self-schedule from there.

Then stop. Do not call `ScheduleWakeup` from this bootstrap session.

### Failure handling

At every step, if a command fails and the fix is not obvious, STOP and print:
- The exact command that failed
- The exit code and the last 10 lines of stderr
- A one-sentence hypothesis in the operator's language

Do not attempt creative recovery. The operator will fix and re-run the prompt.

### What you must NOT do in this bootstrap session

- Do not modify any file outside `.autopilot/` and `.apply-conflicts/`.
- Do not push anything.
- Do not call `ScheduleWakeup` — that is for the actual autopilot iter, not bootstrap.
- Do not start a DAD dialogue session — the loop will do that when needed.

END PROMPT ---->8----

---

## What happens after bootstrap

The target project now has a full `.autopilot/` directory. To run the loop, paste `.autopilot/RUN.claude-code.md` (for Claude Code desktop) or `.autopilot/RUN.codex-desktop.md` (for Codex). Those RUN files contain the per-iter contract; the runner and safety-nets (preflight, LLM timeout, stalled-fallback, consecutive-stall HALT) are already in place from the ported hardening chain.

See [README.md](README.md) for template design, [base/.autopilot/runners/](base/.autopilot/runners/) for the runtime, and [locales/](locales/) for the i18n story.
