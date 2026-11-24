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

The `start` skill runs in the main conversation and orchestrates the agents. Agents hand work to each other through files in a run folder under `~/.claude/agentic-workflow/` (keyed by the repository's `origin`), outside your repository. Only the main thread talks to you, and only `jira-analyst` touches Jira and Confluence (with picture analysis on it also downloads a ticket's attachments, with your own API token).

## Prerequisites

- Claude Code with plugin support.
- `gh` CLI, logged in with an account that can write to the repository (`gh auth login`). Setup binds the repository to one of the logged-in accounts and every gh call then runs as that account through the plugin's `gh-as` wrapper, without ever changing gh's active account, so other terminals are not affected. Without `gh`, or without that binding, the run still pushes and writes the PR text to `pr.md`.
- An Atlassian account with access to your Jira site. Jira is reached through an Atlassian MCP server: either your claude.ai Atlassian connector (if you have one) or the server this plugin ships. Claude Code hides the plugin's server when a connector with the same URL exists, so setup finds whichever is available and stores its tool prefix. You authorize once in the browser; the token is stored and refreshed for you.
- Optional, for picture analysis: an Atlassian API token of your own (setup stores it in the macOS keychain, never in a file) and `ffmpeg` for screen recordings (`brew install ffmpeg`; screenshots work without it). macOS only in this version.
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
2. Setup goes in three stages and saves each one when it is finished. **Stage 1, Jira:** the connector (with the account and sites each one reaches), project, board, target user, statuses, issue types, Confluence spaces and `writeMode`. **Stage 2, GitHub and repo:** it reads the host and repository from `origin` (an SSH alias is resolved), lists your logged-in gh accounts, checks which can write to the repository, proposes the one your SSH key pushes as, and asks for the base branch. **Stage 3, behavior:** investigation, language and candidate count. Stage 1 starts by asking where the configuration lives (see Storage below). Setup writes the configuration and your personal values (the server's tool prefix, the gh account and the limits you accepted) and registers exact `allow` permission rules in your user settings (`~/.claude/settings.json`), so later runs do not stop to ask. Claude Code asks you to approve the writes to the configuration files: that is intended, see Storage. When an authorization is needed (Jira, or a gh login) setup waits for it by itself and continues as soon as it is done.
3. Run `/agentic-workflow:start`.

Setup is done once per repository. It detects what it can (connectors, sites, projects, your gh accounts, the repository's host and default branch) and then asks a few grouped questions in which the detected value is always the first, recommended choice, so confirming is enough. Running it again on a configured repository shows the current values and asks what to change; `/agentic-workflow:setup --reconfigure jira|github|behavior|storage|permissions` goes straight to one part. Every `start` re-checks that the Jira connector can reach the configured site and that the bound gh account can write to the repository, and stops with the exact fix when it cannot.

## Storage

You choose once, in Stage 1, where the repository's configuration lives:

- **Only on this computer.** Nothing is written into the repository. The configuration and your personal values live in `~/.claude/agentic-workflow/repos/<host>/<owner>/<repo>/` and the run files in `~/.claude/agentic-workflow/state/<host>/<owner>/<repo>/`, both keyed by the repository's `origin` (so another clone of the same repository finds them). Use this when the workflow is adapted to you alone.
- **In the repository, shared with the team.** Setup creates `.claude/agentic-workflow.json` (project, board, base branch, write mode, investigation) and you decide whether to commit it. Your personal values and the run files still stay on your computer. A teammate's later change to the file can never widen what the plugin may do for you: the write mode and the browser origins you accepted in your own setup are a ceiling, the lower value applies, and `start` tells you in one line when the shared file asks for more. You can also accept less than the team file allows. Setup does not rewrite keys that already exist in a shared file.

Either way the run files (briefs, plans, reports, the ticket ledger) are outside the repository, so there is no `.git/info/exclude` entry and nothing to commit by accident. Pending questions you can answer by hand are in `<run folder>/pending/` (the path is printed when a ticket is parked). `/agentic-workflow:setup --reconfigure storage` moves the configuration from one place to the other. Repositories set up by an older version (config in the repository, files in `.agentic-workflow/`) are migrated by running setup again: it offers to move the run files and to remove permission rules that older versions wrote.

Setup is the only writer of the configuration and of your personal values, and Claude Code asks you to approve each write. That prompt is the safeguard: the plugin's guard trusts these files, so no permission rule covers them, and an agent that tries to change them triggers the same prompt. It protects as long as prompts are on: a mode that skips them (such as `bypassPermissions`) or a broad shell allow rule would remove it, as it does for any file.

## Use

```
/agentic-workflow:start                  next ready ticket assigned to the configured user
/agentic-workflow:start ABC-123          a specific ticket
/agentic-workflow:start --auto           skip the checkpoints
/agentic-workflow:start --dry-run        analysis only; nothing is written to Jira
/agentic-workflow:start --status         show where every known ticket stands
/agentic-workflow:media ABC-123          what the screenshots and recordings of a ticket show (Jira is not written)
/agentic-workflow:start ABC-123 --from review
```

- By default the run stops at the three checkpoints above.
- `--auto` skips them. It still stops for blocking ticket questions, required planner questions, a secret found in the diff (including by a reviewer), an exhausted loop limit, blockers still open after the third review round, a rebase conflict, an analyst error, a GitHub account that is not logged in or cannot write to the repository, or a Jira connector that cannot reach the configured site.
- A ticket missing information is parked in `<run folder>/pending/<KEY>.md` with specific questions. Answer in the conversation, or edit the file and mark `operator_status: answered`; the next run picks it up first.
- A ticket that already has a PR is never picked up again.
- Re-running a key offers to resume from `<run folder>/<KEY>/state.json`.

## Write modes

`writeMode` decides what the plugin may change in Jira: `none`, `labels` (only `agent-*` labels), `labels+comments` (adds question and PR comments), `labels+comments+transition` (adds status transitions). The plugin's guard enforces it for this repository only (no permission rules are written for it, so other repositories can use a different mode): it allows the analyst to use a Jira write tool inside the mode and blocks the rest. In a shared configuration it also never goes above the mode you accepted in setup. Note that labels and question comments are written during triage, before the first checkpoint; choose `none` to avoid that.

## Investigation

Before it asks you a question, `jira-analyst` tries to answer it from facts:

- **Code** (on by default): it searches the repository you work in (`git grep`) for what the ticket mentions.
- **Browser** (off by default): with [Claude in Chrome](https://code.claude.com/docs/en/chrome) and a non-production `appUrl` set in `/agentic-workflow:setup`, it opens that app read-only to check a repro or the actual behavior. It never types, logs in, submits forms or leaves the allowed origins.

A fact counts only with evidence: for every criterion it marks as met, `brief.md` carries an `## Evidence` entry with the source and an exact quote (ticket text, comment id, Confluence page, your own answer, `path:line` and commit, or URL, steps and observed text). The analyst never adds acceptance criteria or repro steps the sources do not state, and before every handoff it re-checks each quote against the repo and the fetched text. Code shows what the app does, never what it should do, so expected behavior, acceptance criteria and design decisions are always asked. Anything it cannot prove (including "could not reproduce") comes back to you as a question that ends with a `Checked:` line saying what was tried.

## Pictures and recordings

Bug reports often live in a screenshot or a screen recording attached to the ticket. When you switch picture analysis on in `/agentic-workflow:setup` (it is off by default), the plugin can look at them:

- `/agentic-workflow:media ABC-123` downloads the ticket's images and videos with your own Atlassian API token, splits videos into a few frames taken at the scene changes, and prints what a model sees: the kind of picture, the text it can read, the steps shown in a recording with their times, and an error or state shown. It writes nothing to Jira.
- `/agentic-workflow:start` does the same on its own when the ticket text is not enough to judge the ticket (`jira.media.auto`).
- The Atlassian server cannot download attachments, so `bin/jira-attachment` does it. The token is kept in the system keychain only. The download address is built from your Jira site and a numeric attachment id, never from a link in the ticket, and files are accepted by their real content type, not their name.
- The pictures are looked at by a separate agent, `media-analyst`, that can only read and sees no ticket text. What it reports is data: it never settles more than the existence of evidence (B4) and the actual behavior (B2) when the ticket is silent or agrees; steps seen in a recording and mockups are offered to you as answer options in a question, never taken as facts. The planner and the implementer never open the pictures, and nothing from them goes into Jira comments or the pull request.
- It costs time and tokens: each ticket with pictures needs a second analyst pass and the viewer, and `--dry-run` also downloads and looks at the pictures (it still writes nothing to Jira). The downloads stay in the run folder until you delete the ticket's folder at the end of a run.
- Honest limits: a recording is a sample of frames, not watched in full; sound is not heard; a model can misread small text; recordings need `ffmpeg`; only still images and videos attached to the ticket (not links to Loom or YouTube).

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
- It never stores ticket text or keys, run-folder content, secrets or personal data, and nothing from code the feature branch added.
- Nothing is written into your repository. To reset what it knows about a repo, delete that repo's file under `repos/` in the memory folder.
- If auto memory is disabled (`autoMemoryEnabled`, `CLAUDE_CODE_DISABLE_AUTO_MEMORY`) the agent still works, it just saves nothing.
- `/agentic-workflow:setup` adds the permission rules for the memory folder (in your user settings). After updating the plugin, run it again, otherwise memory writes prompt (or are denied in an unattended run).

## Configure

Personal options (`/plugin configure agentic-workflow`): `defaultAuto`. Everything else is stored by `/agentic-workflow:setup`; see `skills/start/references/config-schema.md`. Without per-repo settings the plugin discovers scripts itself and uses these defaults: branch `feat/ABC-123-short-title`, commit subject `ABC-123: summary`, PR title `[ABC-123] summary`, PR as draft, PR target the repository's default branch (setup asks for `baseBranch` if you want another one, such as `develop`).

## Safety

- No force-push, no push to the base or protected branches.
- Pull requests are drafts by default.
- The diff is scanned for secrets before every push.
- Ticket, comment, Confluence, code and web page text is treated as data, never as instructions.
- The browser, when enabled, is read-only and limited to the origins you allow; the guard allows the analyst only the read tools, and only in repositories where you enabled it.
- Jira writes go through one agent, within the `writeMode` you chose, and are enforced per repository by the plugin's guard hook, never by user-level deny rules. If you disable hooks (`disableAllHooks`), Jira writes and the browser fall back to asking for permission on every call.
- Setup writes only `allow` rules, and only for what is the same in every repository.
- The plugin stores no tokens or secrets in files; authorization is handled by Claude Code. The one exception is opt-in: with picture analysis on, your Atlassian API token lives in the macOS keychain (stored by `jira-attachment login`). Any program that runs on your computer as you can read a keychain item that `security` created, including the commands a run executes, so prefer a token with scopes (read-only) when your Atlassian plan offers it, and remove it any time: `jira-attachment logout --email <you>` (that script is on the Bash tool's `PATH` only while the plugin is enabled), or in any terminal `security delete-generic-password -s agentic-workflow-atlassian -a <you>`; revoke the token itself on the Atlassian account's API-token page.

## Roadmap

- `/agentic-workflow:address-review`: handle PR review comments.
- `--worktree` isolation.
- Repository memory for `implementation-planner` and the reviewers too.
- Plugin evals (`claude plugin eval`): unclear ticket, dirty tree or `main`, resume.
- Optional SessionStart hook.

## License

ISC
