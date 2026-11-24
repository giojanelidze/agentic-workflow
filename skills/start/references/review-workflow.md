# Review workflow

The review stage of `/agentic-workflow:start` (stage `review`). Four read-only reviewers look at the finished change in parallel, an aggregator merges their reports into one verdict, the implementer fixes the blockers (and only the blockers), and after 3 review rounds whatever is still open goes to a human. Suggestions and nits never block and are never auto-fixed: they become one PR comment for the human reviewer.

| Agent | Looks at | Model |
|---|---|---|
| `correctness-reviewer` | Does the change do what the task asks: logic, edge cases, error handling, regressions, tests | opus |
| `conventions-reviewer` | The target project's own documented and established standards, reuse of existing code | sonnet |
| `security-reviewer` | Input validation, auth, secrets, XSS and unsafe HTML, user data, risky dependencies | opus |
| `performance-reviewer` | Change detection, leaks, needless work or requests, bundle impact, hot paths | sonnet |
| `review-aggregator` | Merges the four reports, removes duplicates, decides the verdict. Adds no findings | sonnet |

Models are set in each agent's frontmatter; the orchestrator never passes `model`.

```
checks PASS at HEAD
        |
        v
prepare round n:  diff.patch, changed-files.txt (+ delta.patch from round 2)
        |
        v
  correctness  |  conventions  |  security  |  performance     parallel, fresh context,
        \            \             /            /               read-only, one report each
         \____________\___________/____________/
                          |
                          v
                   review-aggregator  ->  reply; the orchestrator saves
                          |               review/round-<n>/summary.md
                          |
   +----------------------+--------------------------+-----------------------------+
   | approve              | [secret] blocker         | changes_required, n < 3     | changes_required, n = 3
   v                      v                          v                             v
 publish             stop (human)          implementer fixes blockers      escalation (human)
 (checkpoint 2)                            -> checks again -> round n+1
```

## 1. When the stage starts
Only after the deterministic checks are green on the code that will be reviewed: the last `test-runner` check returned `Status: PASS` and `state.json.lastCheckSha` equals `git rev-parse HEAD`, and the working tree is clean. Why: reviewing code that does not build or whose tests fail produces noise, and the reviewers would report what the checks already say. If `lastCheckSha` differs from HEAD (for example after `--from review`), run `test-runner` in `check` mode first; on new failures follow the test loop of the orchestrator, not this stage.

## 2. Prepare the round (orchestrator, round `n`)
Create `<State>/<KEY>/review/round-<n>/` and write, with Bash, to these absolute paths (`LOCKS` stands for the three pathspecs `':(exclude,glob)**/package-lock.json' ':(exclude,glob)**/pnpm-lock.yaml' ':(exclude,glob)**/yarn.lock'`):
- `diff.patch`: `git diff -U10 origin/<base>...HEAD -- . $LOCKS`. Lockfiles are left out because they bury the real change; a dependency change still shows in `package.json` and `changed-files.txt`.
- `changed-files.txt`: `git diff --name-status origin/<base>...HEAD`.
- Round 2 and up, `delta.patch`: `git diff -U10 <sha of round n-1>..HEAD -- . $LOCKS`. It is what the reviewers look at when they re-review.

Record the round in `state.json.reviewRounds` as `{"n": <n>, "sha": "<HEAD>", "verdict": null}`: append it, or replace the entry with the same `n` when a round restarts. The round count is the length of that list. The orchestrator writes these files because the reviewers and the aggregator have no Bash and no Write.

## 3. Run the four reviewers in parallel
In **one message** start `agentic-workflow:correctness-reviewer`, `conventions-reviewer`, `security-reviewer` and `performance-reviewer` (no `model` parameter), all with the same prompt:

```
Review <KEY>, round <n>.
State: <absolute State path>
Reviewed commit: <sha>. Base: origin/<base>.
Files: <State>/<KEY>/review/round-<n>/ (diff.patch, changed-files.txt[, delta.patch]).
[Round 2 and up] Previous blockers: <State>/<KEY>/review/round-<n-1>/summary.md
```

Each reviewer starts with a fresh context and receives only the task description (`brief.md`, `plan.md`, the task specs), the change and read access to the repository. It never gets the implementer's reasoning or `implementation.md`, so that it judges the result independently and does not inherit the implementer's blind spots. It cannot modify anything: its tools are Read, Grep and Glob. This is the one place in `start` where agents run in parallel; wait for all four before going on.

Because reviewers cannot write files (and Claude Code refuses a subagent's Write to a file named `report*`, `summary*`, `findings*` or `analysis*` `.md` in any case), the orchestrator saves each reply **verbatim** as `review/round-<n>/<reviewer-name>.md`, after validating it:
- the first line is `# <reviewer-name> report`, and `**Round:**` equals `<n>`;
- the `**Findings:**` line matches `^\*\*Findings:\*\* (\d+) blocker, (\d+) suggestion, (\d+) nit$` and the counts equal the number of `### [blocker]`, `### [suggestion]` and `### [nit]` headings under `## Findings` (which holds `No findings.` when all three are 0);
- in round 2 and up `## Previous blockers` is present and has a line for every blocker of the previous summary that names this reviewer in `Reported by`;
- the reply contains nothing outside the report.

A malformed reply is re-run once (that reviewer only). A second failure, or a `BLOCKED: <reason>` reply, ends the stage: write `blocked.md` and stop.

## 4. Aggregate
Run `agentic-workflow:review-aggregator` with `<KEY>`, `<n>` and the `State:` line. It reads the four reports (and, from round 2, the previous summary) and **replies with the summary**; it has only Read, because Claude Code refuses a subagent's Write to `summary.md`. The orchestrator saves the reply as `review/round-<n>/summary.md`. That file is the orchestrator's to write, so it never asks the user for permission to do so.
- duplicates are merged: the same file, overlapping lines and the same fix; the higher severity wins and every reporter is listed;
- every previous blocker that a reviewer still reports `unresolved` (or did not mention) stays a blocker of this round, listed once;
- `Verdict` is `changes_required` if at least one blocker exists, otherwise `approve`;
- it adds no findings and does not look at the code.

Before saving, remove harmless wrapping that does not change the content: an outer code fence around the whole reply, text before the `# Review summary` line, and a trailing `STATUS:` line. Only structural errors count as malformed. Validate:
- the first line is `# Review summary`, `**Verdict:**` is `approve` or `changes_required`, and `**Round:**` is `<n> of 3`;
- `**Totals:**` matches `^\*\*Totals:\*\* (\d+) blocker, (\d+) suggestion, (\d+) nit$` and the counts equal the number of `###` headings under `## Blockers`, `## Suggestions` and `## Nits` (a section that holds `None.` counts 0);
- the verdict follows from the blocker count (`changes_required` exactly when there is at least one blocker);
- `## Escalation` is present exactly when `n` is 3 and there is at least one blocker;
- nothing sits outside the summary after the wrapping is removed.

Then save the text verbatim. A malformed reply is re-run once (the aggregator only); a second failure, or a `BLOCKED: <reason>` reply, ends the stage: write `blocked.md` and stop. Set `reviewRounds[n].verdict` from the summary.

## 5. Verdict
- **A `[secret]` blocker** (a credential in the diff): always stop, even with `--auto`. A secret that is committed stays in git history even if the next commit removes it, and the `pr-publisher` scan only looks at the net diff, so a fix loop would not solve it. Write `blocked.md` (file and line, never the value) and tell the user to rewrite the history and rotate the credential.
- **`approve`**: go on to checkpoint 2 and publish.
- **`changes_required`, round 1 or 2**: run `implementer` with `summary.md` (`## Blockers` only). It fixes the blockers, one commit each, and does not touch suggestions or nits. Then `test-runner` in `check` mode (the test loop limits apply and `lastCheckSha` is updated on PASS), then round `n + 1` from step 2. A failure signature that repeats ends the loop as everywhere else.
- **`changes_required`, round 3**: **escalation**. The implementer does not run again. Always stop, even with `--auto`: show the summary's `## Escalation` and ask the user (AskUserQuestion):
  - "I will fix it myself": write `blocked.md` with the blockers and stop. Resume later with `--from review` (a new series of 3 rounds).
  - "Publish a draft PR anyway": set `state.json.reviewOverride` to `publish-with-blockers` and go on to checkpoint 2. `pr-publisher` lists the open blockers at the top of the PR body.
  - "Give up on this ticket": write `blocked.md` and call the analyst `confirm <KEY> failed <reason>`.

The limit is 3 rounds in all: the review runs in rounds 1, 2 and 3, and the implementer fixes after rounds 1 and 2. Each fix run counts in `implementerRuns`.

## 6. Suggestions and nits
They are never auto-fixed. Checkpoint 2 shows how many there are. `pr-publisher` collects the `## Suggestions` and `## Nits` of **every** round's `summary.md` (a suggestion raised in round 1 does not come back in round 2, because the reviewers only look at new changes then), removes duplicates by file and summary, and posts them as one PR comment marked `<!-- agentic-workflow:review -->`. On a re-run it edits that comment instead of adding another. Line numbers in the comment are those of the commit that was reviewed in the round that raised them.

## 7. Files
All under `<State>/<KEY>/review/round-<n>/`, which is outside the repository.

| File | Writer |
|---|---|
| `diff.patch`, `changed-files.txt`, `delta.patch` | orchestrator |
| `<reviewer-name>.md` (four) | orchestrator, verbatim reply of the read-only reviewer |
| `summary.md` | orchestrator, verbatim reply of `review-aggregator` |

Formats: `report-formats.md`. State: `state-schema.md` (`lastCheckSha`, `reviewRounds`, `reviewOverride`).

## 8. Resume
`--from review` deletes `review/`, resets `state.json.reviewRounds` to `[]` and `reviewOverride` to `null`, starts a new series at round 1 and first runs the checks if `lastCheckSha` differs from HEAD. A run interrupted inside a round restarts that round from step 2: its files are overwritten and its `reviewRounds` entry is replaced, not appended.

## Limits worth knowing
- The reviewers judge from the code and the patch: they have no build, profiler or browser, so bundle size and runtime cost are judged statically and reported as such.
- The secret check in review sees the net diff of the branch; a secret added and removed again inside the branch is not visible to it. `pr-publisher` keeps its own scan before the push.
