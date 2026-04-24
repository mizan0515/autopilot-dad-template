# PITFALLS

Recurring traps. Read at iter start; append when you spot a new one.

## Seed

- Do not edit IMMUTABLE blocks in `PROMPT.md` under the guise of "cleanup". The pre-commit hook rejects such changes.
- Never edit `Document/dialogue/sessions/**/turn-*.yaml` originals — always create a new turn file.
- Avoid relative date queries like `git log --since "1 week ago"` — use commit hashes or absolute dates.
- Avoid recursive searches of `.archive/` — read `.archive/INDEX.md` first and pinpoint-read at most one file.
