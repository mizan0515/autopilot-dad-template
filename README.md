# autopilot-dad-template

Autonomous autopilot + DAD (Dual-Agent Dialogue) peer-collaboration template.
One prompt applies a full autopilot loop to any Git project. i18n: operator language
chosen at apply time, so dashboards, status lines, and glossary render in that language.

---

## One-prompt bootstrap (Claude Code / Codex)

See [BOOTSTRAP.md](BOOTSTRAP.md) for the full paste-ready orchestrator prompt. Short summary of what it does:

1. Asks the operator for their language (BCP-47 tag — any language works; shipped locales are `en`, `ko`).
2. Checks prerequisites (git, gh, pwsh/bash, gh auth, claude/codex CLI) and stops with a concrete install hint if anything is missing.
3. Runs `git init` if the target dir is not yet a git repo.
4. Asks for project name / description / product directive.
5. Clones this template to a temp dir and runs `apply.ps1` / `apply.sh` against the target.
6. Smoke-checks via `.autopilot/runners/preflight.ps1`.
7. Replaces the seed items in `.autopilot/BACKLOG.md` with real first tasks based on the directive.
8. Commits the bootstrap (does not push).
9. Tells the operator to paste `.autopilot/RUN.claude-code.md` or `.autopilot/RUN.codex-desktop.md` to start the loop.

The same prompt works regardless of project type (Unity / web / CLI / library).

---

## What's inside

```
autopilot-dad-template/
├── apply.ps1                 # Windows installer (language-aware)
├── apply.sh                  # Unix installer (language-aware)
├── base/
│   └── .autopilot/
│       ├── project.ps1              # status / dashboard / lifecycle verbs
│       ├── OPERATOR-TEMPLATE.html   # i18n HTML shell (reads strings.json)
│       ├── config.schema.json       # JSON Schema for .autopilot/config.json
│       ├── runners/{runner.ps1, runner.sh}
│       ├── hooks/{pre-commit, protect.sh, protect.ps1, commit-msg*}
│       ├── NEXT_DELAY, METRICS.jsonl
└── locales/
    ├── en/
    │   ├── .autopilot/{PROMPT, RUN.claude-code, RUN.codex-desktop,
    │   │               STATE, BACKLOG, HISTORY, PITFALLS, EVOLUTION}.md
    │   └── strings.json             # dashboard + runner + glossary strings
    └── ko/   (same tree, Korean)
```

After apply, the target project has:

```
.autopilot/
├── config.json                  # project_name, operator_language, directive, ...
├── PROMPT.md                    # placeholders already rendered
├── RUN.claude-code.md
├── RUN.codex-desktop.md
├── STATE.md, BACKLOG.md, HISTORY.md, PITFALLS.md, EVOLUTION.md
├── project.ps1                  # .\.autopilot\project.ps1 status → HTML dashboard
├── OPERATOR-TEMPLATE.html
├── locales/{en,<lang>}/strings.json
├── runners/, hooks/
└── NEXT_DELAY, METRICS.jsonl
```

## Design principles

- **Stateless prompt + stateful files** — `PROMPT.md` reads `.autopilot/*` to restore state each turn.
- **IMMUTABLE guard** — `product-directive`, `core-contract`, `boot`, `budget`, `blast-radius`, `halt`, `exit-contract` blocks are rejected by the pre-commit hook if edited.
- **i18n by config** — operator-facing output (dashboard labels, status lines, glossary) is driven by `locales/<lang>/strings.json`; shipping a new language = adding one JSON file.
- **DAD peer dialogue** — `Document/dialogue/sessions/<id>/turn-*.yaml` schema; dashboard surfaces session status (converged / active / blocked) with localized labels.
- **Cross-platform** — PowerShell + bash equivalents for apply, runner, protect, project.
- **Operator dashboard** — `project.ps1 status` emits `OPERATOR-LIVE.{json,html}` so a non-technical operator opens one HTML file to see iter count, recent flow, open PRs, DAD sessions, and a glossary — all in their language.

## Adding a new language

1. `cp -r locales/en locales/<tag>`
2. Translate `.autopilot/*.md` bodies (keep `{{PLACEHOLDERS}}` and IMMUTABLE block headers verbatim).
3. Translate `strings.json` values (keep keys).
4. PR.

## License

MIT
