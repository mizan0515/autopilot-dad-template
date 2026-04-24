---
id: 12-context-summarization-policy
audience: [claude-code, codex]
intent: Keep peer-handoff context under CarryForwardMaxBytes without losing load-bearing facts.
invoke: When a turn needs more than one turn's worth of prior context, or when `handoff.context` is approaching the 2048-byte cap.
---

# Context Summarization Policy

The relay truncates `handoff.context` at `CarryForwardMaxBytes` (default 2048) and appends `…truncated`. If you need more history, read `state.json` + prior `turn-{N}.yaml` directly; do NOT re-request from the relay.

## Hard targets

- `handoff.context` body: keep under **~1.5 KB** (≈1500 bytes) so peers see full text, not a truncation marker.
- Peer prompt overall: keep under **~6 KB** unless the task genuinely requires more.
- If you need more bytes, refactor toward pointers ("see `turn-3.yaml` §evidence") instead of inlining.

## What to keep (load-bearing)

1. **Decisions the peer needs to accept or contest.** If you chose A over B, say why in one line.
2. **Facts the peer cannot easily re-derive.** File paths, exact test names, commit hashes, concrete values (not summaries of summaries).
3. **Open risks / known gaps.** One line each. The peer will read these first.
4. **Checkpoint status.** PASS/FAIL against the active Contract with one-line evidence.
5. **Next-task scope.** What the peer is being asked to do, with the smallest useful specificity.

## What to cut (non-load-bearing)

- Narration of your own thought process.
- Repetition of what's already in `PROJECT-RULES.md`, `AGENTS.md`, or `CLAUDE.md`.
- Verbose copies of things the peer can read themselves (the previous packet, the PRD, the file you edited).
- "Everything I tried" — keep only what changed the outcome.
- Motivational framing, politeness scaffolding, rhetorical hedges.

## Summarization procedure

When your draft `handoff.context` exceeds ~1.5 KB:

1. **Tag each paragraph** with one of: `decision`, `fact`, `risk`, `status`, `scope`. Drop anything that does not fit a tag.
2. **Collapse sequences.** Three bullets of "I tried X, then Y, then Z" become one line: "Chose Z over X/Y because <reason>."
3. **Replace narrative with pointers.** Instead of "Here is the full diff of `Foo.cs`..." write "See diff at `Document/dialogue/sessions/<id>/turn-{N}.yaml § diffs.Foo.cs`."
4. **Prune after pruning.** Read the output once and remove any line that does not help the peer execute the next task or contest your work.
5. **Preserve verbatim** the quoted error messages, command invocations, and test names. These are the evidence; paraphrase kills them.

## Anti-patterns

- Summarizing a summary (lossy cascade).
- Removing the very line the peer needs in order to disagree with you.
- Keeping a long block because "the peer might want context" — if they want more, they'll open the packet.
- Padding to hit a word count.

## Escalation

If you genuinely cannot fit the load-bearing context under the cap:

- State that explicitly in `handoff.context`: "Truncated — see `turn-{N}.yaml` §evidence for full."
- Make sure the pointed-to section exists and is self-contained.
- Mention the truncation in the relay-friendly summary so the peer knows to open the packet.

## Review checkpoint (before emitting)

Before finalizing the peer prompt, re-read `handoff.context` and ask:

- Can the peer execute `handoff.next_task` using only this context + the files it names?
- Are the PASS/FAIL evidence lines concrete (command, line number, error text), not inspirational?
- Did I cut anything the peer needs to disagree with me?

If any answer is "no" or "not sure," revise before sending.
