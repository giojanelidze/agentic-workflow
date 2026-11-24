# State and ownership

Everything the pipeline produces lives in the run folder `State`, **outside the repository**, in the user's own `~/.claude/agentic-workflow/`. Nothing is written into the working tree except the team config that the user chose to share. Each file has exactly one writer.

## Where things live

`bin/aw-paths` is the only place that computes these paths. The folder is keyed by `origin` (host, owner and repository, lower-cased), so every clone and worktree of the same repository shares it.

```
~/.claude/agentic-workflow/
  repos/<host>/<owner>/<repo>/
    local.json    personal values (always); also the ceiling of what the user accepted in setup
    config.json   the repository config, only when the user chose "only on this computer" (personal mode)
  state/<host>/<owner>/<repo>/   the run folder, called State below
<repo>/.claude/agentic-workflow.json   the repository config, only when the user chose to share it with the team (team mode)
```

The run files have a tree of their own on purpose: the one permission rule that lets agents write them, `Edit(~/.claude/agentic-workflow/state/**)`, can then never match `local.json` or `config.json`, whatever a repository or an owner is called (a layout like `repos/<host>/<owner>/<repo>/state/` would be matched by `repos/**/state/**` for a repository named `state`).

Which config applies (`mode`) is derived from which files exist: the repository file means `team`, `config.json` means `personal`, both is a `conflict` that setup resolves, neither is `none`. Two clones of one repository share `State`; `lock.json` allows one run at a time per repository, and a ticket whose `state.json` names a branch missing in this clone is resumed only after the user confirms.

| File (under `State` unless noted) | Writer | Holds |
|---|---|---|
| `ledger.json`, `lock.json`, `last_run.json`, `pending/` | `jira-analyst` | triage state of tickets, run lease, last run report, questions awaiting answers (the user may edit a file in `pending/` and mark it `operator_status: answered`) |
| `local.json` (in `repos/…`, not in `State`) | `/agentic-workflow:setup` | personal Jira and GitHub settings (connector prefix, target user, gh account) and the accepted ceiling (`acceptedWriteMode`, `acceptedOrigins`) |
| `config.json` (in `repos/…`, personal mode) | `/agentic-workflow:setup` | the repository config |
| `<KEY>/brief.md` | `jira-analyst` | handoff to the planner |
| `<KEY>/media/<hash>/raw/`, `view/`, `manifest.json` | `jira-analyst` (through `jira-attachment` and `media-prep`) | the ticket's downloaded attachments, the frames made from them, and the list the viewer reads. `<hash>` identifies the set of attachments (`media-prep hash`), so a changed attachment gives a new folder. A cache of downloads: written also in `--dry-run`, never holds ticket text, and `raw/` keeps only still images (a video is deleted once its frames exist) |
| `<KEY>/media/<hash>/findings-<n>.md` | orchestrator (the `/agentic-workflow:start` and `/agentic-workflow:media` skills) | the verbatim reply of the `media-analyst`, after `media-prep validate`, or the one line `REJECTED: <reason>`. Never overwritten (`--refresh` writes the next number), because a `brief.md` may cite it. Neither the planner nor the implementer opens these files or the frames |
| `<KEY>/state.json` | orchestrator | pipeline progress |
| `<KEY>/plan.md`, `<KEY>/tasks/<n>-<slug>.md` | `implementation-planner` | plan index and one detailed spec per task (the orchestrator may only delete the specs of tasks that are not done, before a re-plan) |
| `<KEY>/baseline-report.md`, `test-report.md` | `test-runner` | check results |
| `<KEY>/implementation.md` | `implementer` | per-task log |
| `<KEY>/review/round-<n>/diff.patch`, `changed-files.txt`, `delta.patch` | orchestrator | the change handed to the reviewers (the reviewers have no Bash or Write) |
| `<KEY>/review/round-<n>/<reviewer>.md` | orchestrator | the verbatim reply of one of the four read-only reviewers |
| `<KEY>/review/round-<n>/summary.md` | `review-aggregator` | merged findings and the verdict of the round |
| `<KEY>/pr.md` | `pr-publisher` | PR URL, body, CI |
| `<KEY>/blocked.md` | orchestrator | why a run stopped |

Permission rules: `Edit(~/.claude/agentic-workflow/state/**)` lets the agents write the run files without a prompt. `local.json` and `config.json` are deliberately **not** covered: the plugin's guard hook trusts them, so only setup, in the main conversation and with the normal permission prompt, may change them.

Not a handoff: `implementer` also keeps repository knowledge (structure, architecture, standards) in its own memory directory under `~/.claude/agent-memory/`, outside the target repo. It holds no ticket data, and no other agent reads it.

No field is stored in two places: Jira-side facts (comments, labels, attempts) are in the ledger only; pipeline facts (branch, tasks, counters, PR URL) in `state.json` only.

Older versions kept all of this in `<repo>/.agentic-workflow/`. `/agentic-workflow:setup` offers to move it (see `skills/setup/SKILL.md`); until then `start` stops and asks for setup.

## ledger.json (analyst)

```json
{
  "tickets": {
    "ABC-123": {
      "state": "NEEDS_INFO",
      "url": "https://company.atlassian.net/browse/ABC-123",
      "type": "Bug", "priority": "High",
      "jira_updated_seen": "2026-10-28T10:15:00.000+0000",
      "first_seen": "2026-10-27T09:00:00Z", "last_evaluated": "2026-10-28T10:16:00Z",
      "reason": "Missing repro steps", "attempts": 0, "rounds": 1, "reopens": 0,
      "transitioned_to": null,
      "commentIds": { "NEEDS_INFO#1": "10042" },
      "history": [{ "at": "…", "from": "ANALYZING", "to": "NEEDS_INFO" }]
    }
  }
}
```

States: `DISCOVERED, ANALYZING, READY, NEEDS_INFO, ANSWERED, REJECTED, HANDED_OFF, PR_OPEN, DONE, STALE, CLOSED_EXTERNALLY`. `HANDED_OFF → NEEDS_INFO` happens only through the analyst's `reopen <KEY>` (the planner found a Definition of Ready gap). `reopens` (default 0) counts those reopens, at most 2 per ticket, and is separate from `rounds`; their comment key is `NEEDS_INFO#R<reopens>`. `history` keeps the last 10 entries. Keys in `HANDED_OFF`, `PR_OPEN`, `DONE`, `REJECTED` are never picked up again by `next`. `PR_OPEN` becomes `DONE` only when the ticket reaches a Jira status category `Done` (leaving `openStatuses` is not enough: the analyst's own transitions do that). `rounds` counts question rounds asked; `transitioned_to` is the status the analyst's own transition produced; `commentIds` keys are `NEEDS_INFO#<rounds>`, `HANDED_OFF`, `PR_OPEN`. With `--dry-run` the analyst changes none of this.

## state.json (orchestrator)

```json
{
  "key": "ABC-123",
  "stage": "implement",
  "auto": false,
  "base": "main", "branch": "feat/ABC-123-add-export", "baseSha": "abc1234",
  "github": { "host": "github.com", "repo": "octocat/hello", "account": "octocat" },
  "tasks": [{ "n": 1, "title": "…", "spec": "tasks/1-add-export.md", "status": "pending | in_progress | done | blocked" }],
  "planAnswers": [{ "id": "P1", "tag": "Tech", "question": "…", "answer": "…", "source": "operator | operator-delegated" }],
  "counters": { "testLoop": 0, "implementerRuns": 0, "needsInputTickets": 0, "planRounds": 0, "planEdits": 0 },
  "lastFailureSignature": null,
  "lastPlanQuestions": [],
  "lastCheckSha": null,
  "reviewRounds": [{ "n": 1, "sha": "def5678", "verdict": "changes_required" }],
  "reviewOverride": null,
  "prUrl": null,
  "startedAt": "…", "updatedAt": "…"
}
```

`stage`: `analysis, branch, plan, baseline, implement, review, publish, jira, done`.

`github` is the GitHub binding found by the preflight of the current run (rewritten every time the file is created or loaded, also on a resume): `host` and `account` from `Local`, `repo` (`<owner>/<repo>`) read from `origin`. The orchestrator passes it to `pr-publisher`; it is absent (`null`) when there is no binding or no `gh`, and the publish stage then only pushes and writes `pr.md`.

Planning fields: `planAnswers` holds every question answered in this run (`P<n>` from the planner, `E<n>` for operator edits at checkpoint 1); all of them are passed to each planner run so a question is never asked twice. `planRounds` counts planner re-runs caused by a reopen, a technical question or a spec mismatch (max 3); `planEdits` counts re-runs caused by an edit at checkpoint 1 (max 2). `lastPlanQuestions` keeps the signatures (tag + normalized text) of the previous run's required questions: the same signature twice ends the loop.

Review fields: `lastCheckSha` is HEAD at the last `test-runner` check that returned `PASS`; the review stage starts only when it equals HEAD. `reviewRounds` has one entry per review round (`n`, the reviewed commit `sha`, and the aggregator's `verdict`, `null` until it ran); its length is the round count (max 3) and `delta.patch` of round `n + 1` is taken from the `sha` of round `n`. `reviewOverride` is `publish-with-blockers` when the user chose to publish a draft PR after the escalation, otherwise `null`. See `review-workflow.md`.
