# DAD Operator Decisions

This file is the **one-way input surface** for the human operator. The session ledger (`state.json`, turn packets) remains authoritative for what happened; this file records what the operator intends.

## Rules

- Modify only on a work branch and merge via PR. Direct edits on `main`/`master` are blocked by `tools/Validate-DadDecisionWorkflow.ps1`.
- Use it for: approvals, direction changes, deferrals, "not this session" notes.
- Do NOT use it for: session state, turn packets, or derived data.
- Entries should be timestamped and reference the affected session id when applicable.

## Format

```markdown
## YYYY-MM-DD HH:MM — decision title

- session_id: (if applicable)
- context: one line
- decision: one line
- follow_up: one line (optional)
```

## Current decisions

<!-- These five DECISION lines are required by tools/Validate-DadDecisions.ps1
     and must always be present. Operator may change the values; removing a
     line makes the pre-commit hook fail. See the Format block above for
     allowed values. Round-3 F9: shipped seed previously had no keys and
     blocked the very first `chore: apply` commit. -->

DECISION: focus none
DECISION: human-review default
DECISION: session-resume auto
DECISION: next-session bootstrap
DECISION: approval pending

## Entries

_(No decisions yet.)_
