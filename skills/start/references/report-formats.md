# Report formats

The orchestrator and agents parse these headings, so keep them exact.

Stage agents (all but `jira-analyst`) end their reply with: `STATUS: DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED` plus one sentence.

## jira-analyst result (final message: one JSON block)
- `{"result":"READY","id","url","brief","confidence"}`
- `{"result":"NEEDS_INPUT","id","url","summary","found":[],"questions":[{"q_id","criterion","required","text","options":[]}],"pending_file"}` (`pending_file` is `null` in `--dry-run`; criterion `F` = a failed implementation attempt)
- `{"result":"NO_WORK","reason":"no_candidates|locked|needs_refinement|rejected|closed|blocked","id","url","message","counts":{}}` (`id`, `url`, `message` only when the reason concerns one ticket, e.g. `analyze <KEY>`)
- `{"result":"CONFIRMED","state","wrote":[]}` (in `--dry-run`, `wrote` lists what would be written)
- `{"result":"STATUS","counts":{},"tickets":[{"id","url","state"}]}`
- `{"result":"ERROR","stage":"config|auth|jira|confluence|state","message","retryable"}`

## brief.md (jira-analyst)
YAML frontmatter: `id, url, type, priority, confidence, dor` (criterion → source such as `description`, `comment`, `confluence`, `operator`, `code`, `browser`). Then `# <KEY>: <title>` and, omitting empty ones: `## Summary`, `## Acceptance criteria`, `## Repro` (bugs), `## Affected areas`, `## References`, `## Evidence` (one entry per met criterion: the claim, its source, a locator and an exact quote: comment id; Confluence url; `Q<n>`; `path:line` and commit; or URL, steps, observed text, time and origin). Every acceptance criterion and repro step names its source, `## Operator answers`, `## Linked issues`, `## Open risks`, `## Notes`.

## pending/<KEY>.md (jira-analyst; the operator may edit answers)
Frontmatter: `id, url, summary, type, priority, state, operator_status: open|answered, created, updated`. Sections: `## What I found`, `## Open risks` (omitted if empty), `## Questions` (`### Q<n> [<criterion>] (required|optional)`, the question ending with a `Checked:` line that says what was searched in the code or browser and the result, `**Answer:**`), `## Resolved`.

## plan.md (implementation-planner)
Exact headings, in this order:
`# Plan for <KEY>`, `## Approach`, `## Validation`, `## Traceability`, `## Tasks`, `## Decisions`, `## Open questions`, `## Out of scope`, `## Risks and open points`, `## Verification`.
- `## Validation`: one entry per brief `## Evidence` entry of source `code` (verdict `verified | moved | failed`) plus one per `## Affected areas` path, each with a receipt: the exact command and its output (`path:line` or `no match`). A verdict without a receipt counts as unverified. It ends with the exploration counts (searches, files read).
- `## Traceability`: `AC<n> "<quote>" -> Task <n>[, Task <m>]`, one line per acceptance criterion; items added by the operator at a checkpoint are marked `operator-added`.
- `## Tasks`: `### Task <n>: <title>` with `- Spec: tasks/<n>-<slug>.md`, `- Files`, `- Changes` (1-2 lines), `- Tests`, `- Depends on` (lower task numbers only).
- `## Decisions`: operator answers (`P<n>` / `E<n>`) verbatim, and planner decisions with their evidence; a delegated choice is marked `operator-delegated`.
- `## Open questions` (write `None` if empty): `### P<n> [DoR:<code>|Tech] (required|optional)`, matching `^### P(\d+) \[(DoR:(U[1-6]|B[1-4]|S[1-4])|Tech)\] \((required|optional)\)$`, then the question, `Options:` (each marked with its source), and a `Checked:` line. A required question also has `Blocks: Task <n>[, Task <m>]` or `Blocks: planning`. `DoR:<code>` uses the analyst's Definition of Ready codes and only those that apply to the brief `type`.
- Any required question means `NEEDS_CONTEXT`, whatever the STATUS line says.

## tasks/<n>-<slug>.md (implementation-planner)
One spec per task; an implementer run with a fresh context must be able to execute it from this file, `plan.md` and `brief.md`.
Frontmatter: `key, task, title, covers` (acceptance criterion ids), `depends_on`, `commit` (the commit subject to use). Sections: `## Goal` (the acceptance criteria quoted), `## Context` (facts, each with its source: `brief`, `code` as `path:line` + quote, `repo-doc`, or `operator (P<n>)`), `## Files` (`path: modify | new | delete`), `## Changes` (step by step: symbols, signatures, behavior), `## Reuse` (existing utilities as `path:line`), `## Tests` (cases mapped to criteria, the command and where it comes from), `## Done when` (checklist), `## Out of scope`, `## Notes` (hypotheses and unverified APIs, each marked).

## implementation.md (implementer)
One `## Task <n>: <title>` section per run: Commit, Changed, Checks run, Knowledge, Notes. `Knowledge` is one of `learned | used | updated (<sections>) | not saved (<reason>) | unavailable`: what the implementer did with its repository memory (see `agents/implementer.md`).

## baseline-report.md / test-report.md (test-runner)
`Status: PASS | FAIL`, `## Commands run`, `## New failures`, `## Pre-existing`. Each failure carries a signature (command + test name or first error line). `FAIL` only with new failures.

## review.md (code-reviewer)
`Status: APPROVED | CHANGES_REQUESTED`, `## Blocking`, `## Non-blocking`, `## Summary`. Each finding names file:line.

## pr.md (pr-publisher)
PR URL (or compare URL), final title and body, CI results.

## blocked.md (orchestrator)
What failed, the evidence, what was tried, what the user needs to decide.
