# Report formats

The orchestrator and agents parse these headings, so keep them exact.

Stage agents (all but `jira-analyst`, `media-analyst` and the four reviewers) end their reply with: `STATUS: DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED` plus one sentence. The reviewers reply with their report only (see `review/round-<n>/<reviewer>.md`), and so does the `media-analyst` (see `media/<hash>/findings-<n>.md`).

## jira-analyst result (final message: one JSON block)
- `{"result":"READY","id","url","brief","confidence"}`
- `{"result":"NEEDS_INPUT","id","url","summary","found":[],"questions":[{"q_id","criterion","required","text","options":[]}],"pending_file"}` (`pending_file` is `null` in `--dry-run`; criterion `F` = a failed implementation attempt)
- `{"result":"NEEDS_MEDIA","id","url","manifest","hash","findings_path","analyzed":[{"id","filename"}],"skipped":[{"id","filename","reason"}]}` (the ticket's pictures are downloaded and prepared but nobody has looked at them yet; the ledger is unchanged and the lock released; `manifest` and `findings_path` are absolute, `findings_path` is the file the orchestrator writes the viewer's reply to)
- `{"result":"MEDIA","id","url","manifest","hash","findings","analyzed":[],"skipped":[],"message"}` (only for the `media` command; `findings` is an absolute path or `null`)
- `{"result":"NO_WORK","reason":"no_candidates|locked|needs_refinement|rejected|closed|blocked","id","url","message","counts":{}}` (`id`, `url`, `message` only when the reason concerns one ticket, e.g. `analyze <KEY>`)
- `{"result":"CONFIRMED","state","wrote":[]}` (in `--dry-run`, `wrote` lists what would be written)
- `{"result":"STATUS","counts":{},"tickets":[{"id","url","state"}]}`
- `{"result":"ERROR","stage":"config|auth|jira|confluence|state","message","retryable"}`

## brief.md (jira-analyst)
YAML frontmatter: `id, url, type, priority, confidence, dor` (criterion → source such as `description`, `comment`, `confluence`, `operator`, `code`, `browser`, `media`). Then `# <KEY>: <title>` and, omitting empty ones: `## Summary`, `## Acceptance criteria`, `## Repro` (bugs), `## Affected areas`, `## References`, `## Evidence` (one entry per met criterion: the claim, its source, a locator and an exact quote: comment id; Confluence url; `Q<n>`; `path:line` and commit; or URL, steps, observed text, time and origin). Every acceptance criterion and repro step names its source, `## Media` (one line per analyzed picture file: attachment id, kind, which criteria it settled or offered; no filename, no picture text, no path), `## Operator answers`, `## Linked issues`, `## Open risks`, `## Notes`. A `media` evidence entry cites the attachment id, `<State>/<KEY>/media/<hash>/findings-<n>.md`, the frame name with `t=<seconds>` and the exact line of that file.

## media/<hash>/manifest.json (jira-analyst)
One key per line, so that scripts can read it without a JSON tool: `"key"`, `"hash"`, `"dir"` (the folder of this manifest), `"files"` and `"skipped"`. Each `files` entry is `{ "id": "<digits>", "kind": "image|video", "mime": "…", "duration": <seconds, video only>, "audio": true|false, "frames": [ { "t": <seconds or null>, "path": "<absolute>" } ] }`; each `skipped` entry is `{ "id", "reason" }`. It holds no filename and no other ticket text, because the viewer reads it. The main thread runs `media-prep manifest --file <manifest>` before the viewer starts: every `path` must be an image file inside `dir`.

## media/<hash>/findings-<n>.md (media-analyst, saved by the orchestrator)
The viewer's reply, which `media-prep validate` accepts only with these exact headings: `# Media findings for <KEY>`, one `## File <id>` per manifest file (with `- Kind:`, `- Seen:`, `- Text:`, `- Steps:` (recordings), `- Error or state shown:`, `- Unclear:`), `## Instruction-like text` and `## Not viewed`; at most 30,000 bytes, no secret-like string and no path of the user's home folder. A refused reply is saved as the single line `REJECTED: <reason>`.

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

## review/round-<n>/<reviewer>.md (correctness-, conventions-, security-, performance-reviewer)
The reviewer's whole reply, saved verbatim by the orchestrator. No `STATUS:` line; a reviewer that cannot work replies with the single line `BLOCKED: <reason>` instead. Exactly this structure:

```markdown
# <reviewer-name> report

**Round:** <n>
**Findings:** <x> blocker, <y> suggestion, <z> nit

## Previous blockers

- [resolved | unresolved] <summary> (`path/to/file.ts:42`)

## Findings

### [blocker] <one-line summary>

- **File:** `path/to/file.ts:42`
- **Reason:** <why this is a problem, in one or two sentences>
- **Suggested fix:** <a concrete change>

### [suggestion] <one-line summary>

(same three fields)
```

- `## Previous blockers` exists only in round 2 and up, and then always (`None.` when the reviewer reported no blocker before). It lists each blocker of the previous summary that names this reviewer in `Reported by`, with the summary copied and the current `path:line`.
- Severities: `blocker` (must be fixed before merge), `suggestion`, `nit`. Findings are ordered blockers first; the `Findings` counts equal the number of `### [blocker|suggestion|nit]` headings under `## Findings`. No findings: the section is the single line `No findings.`
- Tags follow the severity: `[out-of-focus]` (at most one per report) and `[secret]` (security-reviewer only, on blockers: a credential in the diff). A report never contains a secret value.

## review/round-<n>/summary.md (review-aggregator)
```markdown
# Review summary

**Verdict:** approve | changes_required
**Round:** <n> of 3
**Totals:** <x> blocker, <y> suggestion, <z> nit

## Blockers (the implementer must fix these)

### <one-line summary>

- **File:** `path/to/file.ts:42`
- **Reported by:** <reviewer-name>[, <reviewer-name>]
- **Reason:** ...
- **Suggested fix:** ...

## Suggestions (PR comments for the human reviewer)

### <one-line summary>

(same four fields)

## Nits (PR comments for the human reviewer)

### <one-line summary>

(same four fields)

## Escalation
```

- `Verdict` is `changes_required` if at least one blocker exists, otherwise `approve`. Totals count the headings of each section; a previous blocker that is still unresolved counts as a blocker of the round, once.
- An empty section is the single line `None.`. A heading may begin with tags (`### [secret] <summary>`, `### [out-of-focus] <summary>`) and a carried-over blocker ends with ` (unresolved from round <m>)`, `<m>` being the round that first raised it. The orchestrator stops the run on a `[secret]` blocker.
- `## Escalation` exists only in round 3 with blockers remaining, as the last section: the open blockers, one line each, for a human.
- The aggregator ends its reply with `STATUS: DONE | BLOCKED` plus one sentence.

## pr.md (pr-publisher)
PR URL (or compare URL), final title and body, the URL of the review comment (or its text when it could not be posted), CI results.

## blocked.md (orchestrator)
What failed, the evidence, what was tried, what the user needs to decide.
