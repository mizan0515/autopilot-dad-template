# .autopilot/dispatch/ — cross-repo job queue

Directory layout:

- `queue/` — pending jobs (JSON per file) produced by this autopilot loop and addressed to a peer relay or another repo.
- `consumed/` — jobs that a consumer picked up and acknowledged. Moved here by the consumer.
- `failed/` — jobs that could not be delivered or processed. One JSON per failure with `{job, reason, ts}`. Surfaced in the operator dashboard.

## Failure handling (Row 9 incident prevention)

Earlier sessions lacked a `failed/` path — cross-repo dispatch failures left only crumbs with no retry or notification. Now:

1. Producer (autopilot iter) drops a job into `queue/<ts>-<slug>.json`.
2. Consumer (relay or peer repo's autopilot) moves it to `consumed/` on success or `failed/` on failure, with a `reason` field.
3. `.autopilot/project.ps1 status` scans `failed/` and surfaces count + newest entry on the dashboard.
4. Operator decides: retry (move back to `queue/`), discard, or fix upstream.

## Retry policy

The autopilot loop does NOT auto-retry failed jobs. A failure usually means upstream config drift (auth, path, schema) that only the operator can resolve. Auto-retry would mask the drift.

## Job file format

```json
{
  "job_id": "2026-04-24T120000Z-example",
  "from_repo": "my-project",
  "to_repo": "relay",
  "kind": "dad-handoff",
  "payload": { /* opaque to dispatch */ },
  "created_at": "2026-04-24T12:00:00Z"
}
```

On failure, the consumer appends:

```json
{
  "job_id": "...",
  "failed_at": "2026-04-24T12:05:30Z",
  "reason": "relay-broker-unreachable",
  "detail": "connect ETIMEDOUT 10.0.0.5:4318"
}
```
