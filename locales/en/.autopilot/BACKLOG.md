# BACKLOG

Prioritized top-down. Selected items are marked `[active]`.

## Seed (iter 0 bootstrap — run this first)

- [ ] `[bootstrap]` Read the operator's `PRD.md` and **replace** this BACKLOG with 3–5 real first tasks. Remove this bootstrap item itself once done.
  - Read: `PRD.md` at the repo root (path is in `.autopilot/config.json` as `prd_path`).
  - Output: delete this entire "Seed" section and replace with a real task list. Each item must be a vertical slice that fits one iter (≤30 min).
  - Append one line to `HISTORY.md`: `iter 0 bootstrap: BACKLOG initialized`.
  - No production code change is required this iter. BACKLOG rewrite + `STATE.md` Recent Context update is this iter's deliverable.
  - If `PRD.md` is missing or placeholder (e.g. a single `# PRD` line), escalate to `STATE.md` Known Blockers as "PRD missing — operator must fill in" and end the iter.

## Notes

- Keep items small enough to fit one iter (≤30 min).
- When an item becomes `[active]`, clone it to `STATE.md` → Active Task.
- After completion, remove it from BACKLOG and leave a one-line record in `HISTORY.md`.
- The `[bootstrap]` tag is iter-0-only; it must not appear in later iters.
