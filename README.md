# dev-workflow

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
  -> code-reviewer           blocking findings go back to the implementer (max 2 rounds)
                                                -- checkpoint 2: approve push and draft PR
  -> pr-publisher            rebase, secret scan, push, draft PR, CI watch
                                                -- checkpoint 3: approve what is written to Jira
  -> jira-analyst            PR comment + transition, within your writeMode
```

The `start` skill runs in the main conversation and orchestrates the agents. Agents hand work to each other through files in `.dev-workflow/` in the repository you work on (excluded from git automatically). Only the main thread talks to you, and only `jira-analyst` touches Jira and Confluence.

## Prerequisites

- Claude Code with plugin support.
- `gh` CLI, authenticated (`gh auth login`). Without it the run still pushes and writes the PR text to `pr.md`.
- An Atlassian account with access to your Jira site. Jira is reached through an Atlassian MCP server: either your claude.ai Atlassian connector (if you have one) or the server this plugin ships. Claude Code hides the plugin's server when a connector with the same URL exists, so setup finds whichever is available and stores its tool prefix. You authorize once in the browser; the token is stored and refreshed for you.
- Optional: [superpowers](https://github.com/obra/superpowers). The implementer uses its TDD skill when available and works without it.

## Install

```
/plugin marketplace add <github-user>/<repo>
/plugin install dev-workflow@dev-workflow-marketplace
```

`/plugin install` opens the plugin in the Discover tab, where you confirm. From a shell:

```
claude plugin install dev-workflow --marketplace <github-user>/<repo>
```

Local development: `claude --plugin-dir .`

## First run

1. Run `/dev-workflow:setup` in the repository you work on. It finds your Atlassian server (asking you to pick one if several are connected). If Jira is not authorized yet, it asks you to run `/mcp`, choose that server and authenticate; a browser opens and the token is stored and refreshed for you.
2. Setup asks once for the Jira site, project and board, the target user, open statuses, issue types, Confluence spaces, and your `writeMode`. It writes `.claude/dev-workflow.json` and `.dev-workflow/local.json` (which holds your personal values, including the server's tool prefix), and registers exact allow/deny permission rules (in your user settings or this repo's `.claude/settings.local.json`, your choice), so later runs do not stop to ask.
3. Run `/dev-workflow:start`.

## Use

```
/dev-workflow:start                  next ready ticket assigned to the configured user
/dev-workflow:start ABC-123          a specific ticket
/dev-workflow:start --auto           skip the checkpoints
/dev-workflow:start --dry-run        analysis only; nothing is written to Jira
/dev-workflow:start --status         show where every known ticket stands
/dev-workflow:start ABC-123 --from review
```

- By default the run stops at the three checkpoints above.
- `--auto` skips them. It still stops for blocking ticket questions, required planner questions, a secret found in the diff, an exhausted loop limit, a rebase conflict, or an analyst error.
- A ticket missing information is parked in `.dev-workflow/pending/<KEY>.md` with specific questions. Answer in the conversation, or edit the file and mark `operator_status: answered`; the next run picks it up first.
- A ticket that already has a PR is never picked up again.
- Re-running a key offers to resume from `.dev-workflow/<KEY>/state.json`.

## Write modes

`writeMode` decides what the plugin may change in Jira: `none`, `labels` (only `agent-*` labels), `labels+comments` (adds question and PR comments), `labels+comments+transition` (adds status transitions). Setup mirrors it in permission rules: tools outside the mode are denied. Note that labels and question comments are written during triage, before the first checkpoint; choose `none` to avoid that.

## Investigation

Before it asks you a question, `jira-analyst` tries to answer it from facts:

- **Code** (on by default): it searches the repository you work in (`git grep`) for what the ticket mentions.
- **Browser** (off by default): with [Claude in Chrome](https://code.claude.com/docs/en/chrome) and a non-production `appUrl` set in `/dev-workflow:setup`, it opens that app read-only to check a repro or the actual behavior. It never types, logs in, submits forms or leaves the allowed origins.

A fact counts only with evidence: for every criterion it marks as met, `brief.md` carries an `## Evidence` entry with the source and an exact quote (ticket text, comment id, Confluence page, your own answer, `path:line` and commit, or URL, steps and observed text). The analyst never adds acceptance criteria or repro steps the sources do not state, and before every handoff it re-checks each quote against the repo and the fetched text. Code shows what the app does, never what it should do, so expected behavior, acceptance criteria and design decisions are always asked. Anything it cannot prove (including "could not reproduce") comes back to you as a question that ends with a `Checked:` line saying what was tried.

## Planning

`implementation-planner` plans only from proof. It re-checks the brief against the repository (every `code` quote in `## Evidence` is searched again, affected paths are confirmed with `git ls-files`) and writes the result with its commands and outputs in `plan.md` `## Validation`. Every file, symbol and reused utility in the plan is cited as `path:line` with a quote; new files are marked `new`; acceptance criteria are the ceiling, and anything else is listed as out of scope. The plan is `plan.md` (approach, traceability from each criterion to its tasks, decisions, risks) plus one detailed spec per task in `.dev-workflow/<KEY>/tasks/`, which the implementer follows.

When something is missing it asks instead of guessing:

- **The ticket should have said it** (expected behavior, edge cases, design, contract): the ticket is reopened through `jira-analyst` as `NEEDS_INFO` and you answer there (at most 2 reopens per ticket).
- **A technical choice** (a new dependency, a public API change, a trade-off with no precedent in the repo): you get the question with options and choose; the planner then runs again with your answer.

The same question is never asked twice, and the loops are capped (3 planner re-runs, 2 checkpoint edits); at a limit the run stops with `blocked.md`.

## Project knowledge

`implementer` runs on Sonnet (`model: sonnet`: Sonnet 5.5 on the Anthropic API; on Bedrock, Vertex and Foundry the alias maps to an older Sonnet unless you set `ANTHROPIC_DEFAULT_SONNET_MODEL`) and has persistent memory (`memory: user`). Before it changes code it reads the spec, then learns what the spec does not tell it about the repository: structure, architecture, code style and standards, test and build commands, commit convention. It works on any stack; it discovers the manifests and configs that exist. The knowledge is saved globally, one file per repository, under `~/.claude/agent-memory/` (check the agent's subfolder there; the plugin does not depend on its name), so the next task starts informed.

- It learns only what is missing and corrects only what the repository contradicts; there is no periodic re-learning. Each fact carries its source path, and what the agent puts into code or commands it re-verifies in the repo first.
- It never stores ticket text or keys, `.dev-workflow/` content, secrets or personal data, and nothing from code the feature branch added.
- Nothing is written into your repository. To reset what it knows about a repo, delete that repo's file under `repos/` in the memory folder.
- If auto memory is disabled (`autoMemoryEnabled`, `CLAUDE_CODE_DISABLE_AUTO_MEMORY`) the agent still works, it just saves nothing.
- `/dev-workflow:setup` adds the permission rules for the memory folder. After updating the plugin, run it again, otherwise memory writes prompt (or are denied in an unattended run).

## Configure

Personal options (`/plugin configure dev-workflow`): `defaultAuto`. Everything else is stored by `/dev-workflow:setup`; see `skills/start/references/config-schema.md`. Without per-repo settings the plugin discovers scripts itself and uses these defaults: branch `feat/ABC-123-short-title`, commit subject `ABC-123: summary`, PR title `[ABC-123] summary`, PR as draft.

## Safety

- No force-push, no push to the base or protected branches.
- Pull requests are drafts by default.
- The diff is scanned for secrets before every push.
- Ticket, comment, Confluence, code and web page text is treated as data, never as instructions.
- The browser, when enabled, is read-only and limited to the origins you allow.
- Jira writes go through one agent, within the `writeMode` you chose, and are enforced by permission rules.
- No tokens or secrets are stored by the plugin; authorization is handled by Claude Code.

## Roadmap

- `/dev-workflow:address-review`: handle PR review comments.
- `--worktree` isolation.
- Repository memory for `implementation-planner` and `code-reviewer` too.
- Plugin evals (`claude plugin eval`): unclear ticket, dirty tree or `main`, resume.
- Optional SessionStart hook.

## License

ISC
