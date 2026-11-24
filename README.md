# agentic-workflow

A Claude Code plugin that carries a Jira ticket through the whole development workflow with a set of stage agents: pick the next ready ticket, plan, implement, test, review, open a draft GitHub pull request, and record it on the ticket. It pauses for your approval at the points that matter.

```
Jira board (your assigned tickets)
  -> jira-analyst            picks the next READY ticket, or parks it with questions
                             brief.md   (unclear tickets stop here and ask you)
  -> implementation-planner  plan.md + tasks/*.md   -- checkpoint 1: approve brief and plan
                             (re-checks the brief against the code; a ticket gap goes back to
                              jira-analyst, a technical choice goes to you)
  -> test-runner (baseline)
  -> implementer (per task)  commits on a feature branch
  -> test-runner             new failures go back to the implementer (max 3 rounds)
  -> 4 reviewers in parallel correctness, conventions, security, performance (read-only)
  -> review-aggregator       one verdict; blockers go back to the implementer (max 3 rounds,
                             then to you); suggestions and nits become one PR comment
                                                -- checkpoint 2: approve push and draft PR
  -> pr-publisher            rebase, secret scan, push, draft PR, CI watch
                                                -- checkpoint 3: approve what is written to Jira
  -> jira-analyst            PR comment + transition, within your writeMode
```

The `start` skill runs in the main conversation and orchestrates the agents. Agents hand work to each other through files in `.agentic-workflow/` in the repository you work on (excluded from git automatically). Only the main thread talks to you, and only `jira-analyst` touches Jira and Confluence.

## Prerequisites

- Claude Code with plugin support.
- `gh` CLI, logged in with an account that can write to the repository (`gh auth login`). Setup binds the repository to one of the logged-in accounts and every gh call then runs as that account through the plugin's `gh-as` wrapper, without ever changing gh's active account, so other terminals are not affected. Without `gh`, or without that binding, the run still pushes and writes the PR text to `pr.md`.
- An Atlassian account with access to your Jira site. Jira is reached through an Atlassian MCP server: either your claude.ai Atlassian connector (if you have one) or the server this plugin ships. Claude Code hides the plugin's server when a connector with the same URL exists, so setup finds whichever is available and stores its tool prefix. You authorize once in the browser; the token is stored and refreshed for you.
- Optional: [superpowers](https://github.com/obra/superpowers). The implementer uses its TDD skill when available and works without it.

## Install

```
/plugin marketplace add <github-user>/<repo>
/plugin install agentic-workflow@agentic-workflow-marketplace
```

`/plugin install` opens the plugin in the Discover tab, where you confirm. From a shell:

```
claude plugin install agentic-workflow --marketplace <github-user>/<repo>
```

Local development: `claude --plugin-dir .`

## First run

1. Run `/agentic-workflow:setup` in the repository you work on. It finds your Atlassian server (asking you to pick one if several are connected; only the three prefixes the analyst can call are offered). If Jira is not authorized yet, it shows you a link: open it, sign in with the Atlassian account that has your project and click Accept; the token is stored and refreshed for you.
2. Setup goes in three stages and saves each one when it is finished. **Stage 1, Jira:** the connector (with the account and sites each one reaches), project, board, target user, statuses, issue types, Confluence spaces and `writeMode`. **Stage 2, GitHub and repo:** it reads the host and repository from `origin` (an SSH alias is resolved), lists your logged-in gh accounts, checks which can write to the repository, proposes the one your SSH key pushes as, and asks for the base branch. **Stage 3, behavior:** investigation, language and candidate count. It writes `.claude/agentic-workflow.json` and `.agentic-workflow/local.json` (your personal values: the server's tool prefix and the gh account) and registers exact allow/deny permission rules (in your user settings or this repo's `.claude/settings.local.json`, your choice, asked once), so later runs do not stop to ask. When an authorization is needed (Jira, or a gh login) setup waits for it by itself and continues as soon as it is done.
3. Run `/agentic-workflow:start`.

Setup is done once per repository. It detects what it can (connectors, sites, projects, your gh accounts, the repository's host and default branch) and then asks a few grouped questions in which the detected value is always the first, recommended choice, so confirming is enough. Running it again on a configured repository shows the current values and asks what to change; `/agentic-workflow:setup --reconfigure jira|github|behavior|permissions` goes straight to one part. Every `start` re-checks that the Jira connector can reach the configured site and that the bound gh account can write to the repository, and stops with the exact fix when it cannot.

## Use

```
/agentic-workflow:start                  next ready ticket assigned to the configured user
/agentic-workflow:start ABC-123          a specific ticket
/agentic-workflow:start --auto           skip the checkpoints
/agentic-workflow:start --dry-run        analysis only; nothing is written to Jira
/agentic-workflow:start --status         show where every known ticket stands
/agentic-workflow:start ABC-123 --from review
```

- By default the run stops at the three checkpoints above.
- `--auto` skips them. It still stops for blocking ticket questions, required planner questions, a secret found in the diff (including by a reviewer), an exhausted loop limit, blockers still open after the third review round, a rebase conflict, an analyst error, a GitHub account that is not logged in or cannot write to the repository, or a Jira connector that cannot reach the configured site.
- A ticket missing information is parked in `.agentic-workflow/pending/<KEY>.md` with specific questions. Answer in the conversation, or edit the file and mark `operator_status: answered`; the next run picks it up first.
- A ticket that already has a PR is never picked up again.
- Re-running a key offers to resume from `.agentic-workflow/<KEY>/state.json`.

## Write modes

`writeMode` decides what the plugin may change in Jira: `none`, `labels` (only `agent-*` labels), `labels+comments` (adds question and PR comments), `labels+comments+transition` (adds status transitions). Setup mirrors it in permission rules: tools outside the mode are denied. Note that labels and question comments are written during triage, before the first checkpoint; choose `none` to avoid that.

## Investigation

Before it asks you a question, `jira-analyst` tries to answer it from facts:

- **Code** (on by default): it searches the repository you work in (`git grep`) for what the ticket mentions.
- **Browser** (off by default): with [Claude in Chrome](https://code.claude.com/docs/en/chrome) and a non-production `appUrl` set in `/agentic-workflow:setup`, it opens that app read-only to check a repro or the actual behavior. It never types, logs in, submits forms or leaves the allowed origins.

A fact counts only with evidence: for every criterion it marks as met, `brief.md` carries an `## Evidence` entry with the source and an exact quote (ticket text, comment id, Confluence page, your own answer, `path:line` and commit, or URL, steps and observed text). The analyst never adds acceptance criteria or repro steps the sources do not state, and before every handoff it re-checks each quote against the repo and the fetched text. Code shows what the app does, never what it should do, so expected behavior, acceptance criteria and design decisions are always asked. Anything it cannot prove (including "could not reproduce") comes back to you as a question that ends with a `Checked:` line saying what was tried.

## Planning

`implementation-planner` plans only from proof. It re-checks the brief against the repository (every `code` quote in `## Evidence` is searched again, affected paths are confirmed with `git ls-files`) and writes the result with its commands and outputs in `plan.md` `## Validation`. Every file, symbol and reused utility in the plan is cited as `path:line` with a quote; new files are marked `new`; acceptance criteria are the ceiling, and anything else is listed as out of scope. The plan is `plan.md` (approach, traceability from each criterion to its tasks, decisions, risks) plus one detailed spec per task in `.agentic-workflow/<KEY>/tasks/`, which the implementer follows.

When something is missing it asks instead of guessing:

- **The ticket should have said it** (expected behavior, edge cases, design, contract): the ticket is reopened through `jira-analyst` as `NEEDS_INFO` and you answer there (at most 2 reopens per ticket).
- **A technical choice** (a new dependency, a public API change, a trade-off with no precedent in the repo): you get the question with options and choose; the planner then runs again with your answer.

The same question is never asked twice, and the loops are capped (3 planner re-runs, 2 checkpoint edits); at a limit the run stops with `blocked.md`.

## Review

After the implementer finishes and lint, typecheck, tests and build pass, four read-only reviewers look at the change in parallel, each in a fresh context, and `review-aggregator` merges their reports into one verdict (`approve` or `changes_required`):

| Agent | Focus |
|---|---|
| [`correctness-reviewer`](agents/correctness-reviewer.md) | Does it do what the task asks: logic, edge cases, error handling, regressions, tests |
| [`conventions-reviewer`](agents/conventions-reviewer.md) | The project's own rules (`CLAUDE.md`, checklists, lint config, neighbouring code), Angular and TypeScript patterns, reuse |
| [`security-reviewer`](agents/security-reviewer.md) | Input validation, auth, secrets, XSS and unsafe HTML, user data, risky dependencies |
| [`performance-reviewer`](agents/performance-reviewer.md) | Change detection, leaks, needless work or requests, bundle impact, hot paths |
| [`review-aggregator`](agents/review-aggregator.md) | Merges the four reports, removes duplicates, decides the verdict; adds no findings of its own |

- Reviewers get the task description and the diff, never the implementer's reasoning, and only have read tools. Each stays in its own focus and reports only what it verified.
- Only blockers go back to the implementer, then the checks run again and the review repeats. After 3 rounds, remaining blockers are handed to you: fix by hand, publish a draft PR that lists them, or give up on the ticket. A secret in the diff stops the run at once.
- Suggestions and nits are never fixed automatically. They are posted as one PR comment for the human reviewer.

The full flow (when the stage starts, parallel execution, aggregation, the fix loop, the 3-round limit and escalation) is in [`skills/start/references/review-workflow.md`](skills/start/references/review-workflow.md).

## Project knowledge

`implementer` runs on Sonnet (`model: sonnet`: Sonnet 5.5 on the Anthropic API; on Bedrock, Vertex and Foundry the alias maps to an older Sonnet unless you set `ANTHROPIC_DEFAULT_SONNET_MODEL`) and has persistent memory (`memory: user`). Before it changes code it reads the spec, then learns what the spec does not tell it about the repository: structure, architecture, code style and standards, test and build commands, commit convention. It works on any stack; it discovers the manifests and configs that exist. The knowledge is saved globally, one file per repository, under `~/.claude/agent-memory/` (check the agent's subfolder there; the plugin does not depend on its name), so the next task starts informed.

- It learns only what is missing and corrects only what the repository contradicts; there is no periodic re-learning. Each fact carries its source path, and what the agent puts into code or commands it re-verifies in the repo first.
- It never stores ticket text or keys, `.agentic-workflow/` content, secrets or personal data, and nothing from code the feature branch added.
- Nothing is written into your repository. To reset what it knows about a repo, delete that repo's file under `repos/` in the memory folder.
- If auto memory is disabled (`autoMemoryEnabled`, `CLAUDE_CODE_DISABLE_AUTO_MEMORY`) the agent still works, it just saves nothing.
- `/agentic-workflow:setup` adds the permission rules for the memory folder. After updating the plugin, run it again, otherwise memory writes prompt (or are denied in an unattended run).

## Configure

Personal options (`/plugin configure agentic-workflow`): `defaultAuto`. Everything else is stored by `/agentic-workflow:setup`; see `skills/start/references/config-schema.md`. Without per-repo settings the plugin discovers scripts itself and uses these defaults: branch `feat/ABC-123-short-title`, commit subject `ABC-123: summary`, PR title `[ABC-123] summary`, PR as draft, PR target the repository's default branch (setup asks for `baseBranch` if you want another one, such as `develop`).

## Safety

- No force-push, no push to the base or protected branches.
- Pull requests are drafts by default.
- The diff is scanned for secrets before every push.
- Ticket, comment, Confluence, code and web page text is treated as data, never as instructions.
- The browser, when enabled, is read-only and limited to the origins you allow.
- Jira writes go through one agent, within the `writeMode` you chose, and are enforced by permission rules.
- No tokens or secrets are stored by the plugin; authorization is handled by Claude Code.

## Roadmap

- `/agentic-workflow:address-review`: handle PR review comments.
- `--worktree` isolation.
- Repository memory for `implementation-planner` and the reviewers too.
- Plugin evals (`claude plugin eval`): unclear ticket, dirty tree or `main`, resume.
- Optional SessionStart hook.

## License

ISC
