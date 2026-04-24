<!-- validate:ignore-refs: Document/.archive/, INDEX.md -->
<!-- Archive tree + archive INDEX.md are project-conditional (round-3 F7). -->

# Shared Project Rules — {{PROJECT_NAME}}

This file contains rules that apply to **all agents** (Claude Code, Codex, DAD peers, autopilot runner).

Related files:
- `CLAUDE.md` — Claude Code contract. Auto-loaded by Claude Code.
- `AGENTS.md` — Codex agent contract.
- `DIALOGUE-PROTOCOL.md` — Dual-Agent Dialogue protocol.
- `.autopilot/` — autonomous loop state + runners.

---

## Product directive

{{PROJECT_DIRECTIVE}}

## Source of truth

If documents conflict, use this priority order:
1. `{{PRD_PATH}}` — product requirements / design intent
2. Any higher-priority spec the operator declares in `.autopilot/config.json`
3. The relevant feature spec inside this repo
4. Inline code comments and commit messages

Lower-priority documents must not redefine core numbers, rule ownership, or canonical terms from higher-priority documents. If a lower-priority summary is stale, follow the higher document and update the stale summary in the same task when possible.

## Current repository reality

Read this section before trusting older summaries, chat logs, or temp plans.

- Prefer actual file inventory over narrative summaries. Run `rg --files <path>` or `git ls-files <path>` before asserting a file exists.
- Stale summaries that describe future modules as missing even when the files now exist are common. Update the stale summary in the same task when you find it.
- Before relying on a file name mentioned in docs or logs, confirm it exists.

## Agent guardrails

- Do not bypass shared systems with one-off logic when a common pipeline exists.
- Keep behavior data-driven when the domain allows it. Do not fork logic per-case when a shared resolver can express it.
- Do not bury core rules inside transport callbacks, UI scripts, or one-off glue.
- If documents, chat notes, and actual files disagree, do not guess. Verify the live files, then update stale guidance.
- Search roots: keep LLM searches scoped to source directories the operator declares in `.autopilot/config.json` → `search_roots`. Do NOT wildcard-search cache directories (`Library/`, `Temp/`, `node_modules/`, `target/`, `build/`, `dist/`, `.autopilot/.archive/`, `Document/.archive/`).
- Archive skip: `.archive/` subtrees are historical. Read the archive `INDEX.md` one-line summary first; only open a specific archived file if strictly needed.
- Git time queries: use commit hashes or absolute dates (`--since=2026-04-01`), not relative dates like `"1 week ago"`.

## Implementation strategy

- Prefer vertical slices over broad framework work.
- Typical task size should fit one of: 1-3 source files, 1 data schema, 1 UI screen, 1 module integration, 1 end-to-end flow.
- A task is not done until code path, data hookup, and minimal verification all exist.
- For systems with large data surfaces, validation and debug visibility are part of the task, not optional follow-up work.

## Document update rules

- Keep the operator-facing metadata block (if your docs use one) in every tracked doc file.
- Encoding: agent-facing Markdown (`AGENTS.md`, `CLAUDE.md`, `DIALOGUE-PROTOCOL.md`, `PROJECT-RULES.md`, `.claude/commands/**/*.md`, `.prompts/**/*.md`) must stay UTF-8 with BOM.
  - **Exception:** Codex skill runtime files `.agents/skills/**/SKILL.md` and `.agents/skills/**/agents/openai.yaml` must stay UTF-8 without BOM (Codex loads frontmatter/YAML from byte 0).
  - If non-ASCII text appears garbled, fix encoding before continuing.
- Run `tools/Validate-Documents.ps1` after meaningful document work. Use `-Fix` to normalize BOM. Use `-IncludeRootGuides -IncludeAgentDocs` when the task touches agent/protocol Markdown.
- When changing a canonical number or term, update every affected document in the same pass.
- Keep terminology consistent across docs, code comments, logs, and test names.

## Research file rules (optional)

If your project uses per-folder research files, update the corresponding research file whenever you add, remove, or modify files in that folder. Do not defer research-file updates to a follow-up task.

Research updates should capture: new files and purpose, removed files and reason, behavior changes, new gaps, resolved gaps.

## Testing and verification expectations

- After production code changes, run the narrowest useful verification step that matches the change.
- Prefer project-native verification flow when available (test runner, linter, type checker, integration harness).
- If the full verification is blocked by unrelated issues, still run the narrowest local check and document the blocker clearly.
- Never use language like "should work" or "looks fine" as a substitute for verified facts.

## Editing and shell fallback rules

- Prefer structured patch tools for code edits. If they fail on Windows, fall back to explicit-encoding PowerShell writes (`[System.IO.File]::ReadAllText/WriteAllText` with `UTF8Encoding $false` for BOM-less, or the with-BOM constructor as required).
- Before editing an encoding-sensitive file (localized strings, non-ASCII content), read the exact target lines first. After editing, re-read the edited neighborhood immediately instead of assuming the write was safe.
- If a localized file shows one broken string, assume nearby strings may also be unsafe until checked against a last-known-good source (`git show`, canonical spec).
- For localized string repair work, restore text from the last-known-good source before inventing replacement wording. Treat this as repair, not rewrite.
- When using shell fallback writes, preserve existing encoding and newline style.
- After any edit that touches strings, interpolated strings, or labels, run at least one syntax-focused guard check before declaring success: quote-balance scan, `git diff --check`, narrowest available compile/test validation.

## Conversation logging

- Record concise work-session summaries in `Document/chat/` as `YYYY-MM-DD-HHMM-topic.md`.
- Capture: request, decisions, changed files, blockers, next steps. No raw transcripts.

## Git workflow

- After each meaningful update, create a Git commit. Push only after the commit is self-contained and verified.
- If the worktree is dirty in unrelated ways, report that commit/push was skipped and why.
- Never skip commit/push silently. The final report must say either that you committed and pushed, or why you did not.
- Never use `--no-verify`. Pre-commit hooks enforce template invariants; bypassing them corrupts the template contract.
- Branch policy: if currently on `main`/`master`, create a new working branch. Do not push directly to main.
