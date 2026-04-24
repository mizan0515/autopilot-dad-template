# autopilot-dad-template

Autonomous autopilot + DAD (Dual-Agent Dialogue) peer-collaboration template.
One prompt applies a full autopilot loop to any Git project. i18n: operator language
chosen at apply time, so dashboards, status lines, and glossary render in that language.

---

## One-prompt bootstrap (Claude Code / Codex)

> Apply the template at `https://github.com/mizan0515/autopilot-dad-template` to the current project.
>
> Dialogue flow:
> 1. **Agent asks**: "What operator language? (en, ko, ja, zh-CN, es, fr, de, or any BCP-47 tag — default en)"
> 2. **Operator answers**: e.g. "English" / "한국어" / "ja".
> 3. **Agent runs** `apply.ps1 -Language <tag>` (Windows) or `./apply.sh --language <tag>` (macOS/Linux) from the project root, answering the project-name/description/directive prompts from context if known, otherwise asking.
> 4. Installer writes `.autopilot/config.json`, copies `base/` + `locales/<lang>/` into `.autopilot/`, renders placeholders in `PROMPT.md`, and registers hooks via `git config core.hooksPath .autopilot/hooks`.
> 5. If `<lang>` is not shipped, English templates are copied but `operator_language` in config is set to `<lang>` so the agent still renders runtime text in that language.
> 6. Any existing `.autopilot/*` files are preserved; differing incoming files land in `.apply-conflicts/`. **Abort** if conflicts ≥ 5.
> 7. Agent replaces the seed items in `.autopilot/BACKLOG.md` with the project's real first 1–3 tasks.
> 8. First iter: paste `.autopilot/RUN.claude-code.md` into Claude Code desktop (or `RUN.codex-desktop.md` into Codex). The runner self-schedules via `ScheduleWakeup`.

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
