# agentic-workflow plugin repo

This repo is a Claude Code plugin (`agentic-workflow`) and its own single-plugin marketplace. It is not an application: there is no build step.

## Layout
- `.claude-plugin/plugin.json`, `marketplace.json`: manifests. Keep `version` identical in both and in `package.json`.
- `.mcp.json`: the plugin's own Atlassian MCP server, a fallback for users without an Atlassian connector. Claude Code suppresses it when a claude.ai connector has the same URL, so never assume its tool prefix.
- `agents/*.md`: one agent per pipeline stage (`agentic-workflow:<name>`); the review stage has four read-only reviewers and `review-aggregator`, described in `skills/start/references/review-workflow.md`. Never put reference files inside `agents/`: it is scanned recursively and every `.md` there becomes an agent.
- `skills/start/SKILL.md`: the orchestrator, `/agentic-workflow:start`. Details live in `skills/start/references/`.
- `skills/setup/SKILL.md`: `/agentic-workflow:setup`, collects configuration, the Jira and GitHub connections and permissions up front, once per repository; setup works in three stages (Jira, GitHub and repo, behavior), each detected, asked and saved on its own and never mentioning the next, with the detected value as the recommended option; re-running it on a configured repository shows the current values and asks what to change.
- `bin/gh-as`: POSIX sh wrapper (on the Bash tool's PATH while the plugin is enabled) that runs `gh` as the account bound in setup, for one process only. Keep it executable (mode `100755`) and free of jq or python.
- `bin/wait-mcp`, `bin/wait-gh-login`: POSIX sh watchers that setup and the `start` preflight run in the background to learn that an authorization has finished (an MCP server became `Connected`, a gh login appeared) instead of asking the user to say so. They only read state. Keep them executable (`100755`).
- `README.md`, `CHANGELOG.md`, `LICENSE` (ISC).

## Conventions
- Subagents share no context; every handoff goes through files in `.agentic-workflow/` of the target repo. Each file has one writer (see `skills/start/references/state-schema.md`). Report headings are fixed (see `report-formats.md`); change them in the agent and the reference together.
- Only `implementer` has persistent memory (`memory: user`, `model: sonnet`). It holds repository knowledge across runs, never ticket data or handoffs; handoffs still go through `.agentic-workflow/`. The orchestrator never passes a `model` to a stage agent.
- Only `jira-analyst` touches Jira and Confluence (the orchestrator's preflight only makes the two read-only connection checks `atlassianUserInfo` and `getAccessibleAtlassianResources`). Only the main thread (the skills) talks to the user; subagents cannot ask questions.
- GitHub is reached only through `gh-as --account <account> --host <host> <subcommand> …` (that argument order exactly, because permission rules match the command text): never plain `gh`, never `gh auth switch` or any other change to gh's active account or config (other terminals must not be affected), never a token in a command, a file or the output. Pull request commands carry `-R <host>/<owner>/<repo>` after the subcommand; `gh repo view` takes it positionally; `gh api` takes an explicit `repos/<owner>/<repo>/…` path. The account lives in `.agentic-workflow/local.json` `github`; `<owner>/<repo>` is read from `origin` on every run and never stored.
- The Atlassian prefixes in `skills/start/references/config-schema.md` ("Supported Atlassian prefixes") and in the `tools:` of `agents/jira-analyst.md` must stay identical; setup offers only those.
- Jira tools are called as `<mcpPrefix><tool>` with `mcpPrefix` from `.agentic-workflow/local.json` (set by `/agentic-workflow:setup`, which is the only place that searches for the server). Never find a tool by its bare name: several Atlassian servers may match. The agent's `tools:` lists the plugin server and the standard claude.ai connector names (`Atlassian_Rovo`, `Atlassian_Rovo_2`) by wildcard.
- Agents must not assume a stack: discover scripts and runners in the target repo.
- `superpowers` is optional, never a dependency.
- Everything in this repo is written in English.

## Checks
- `claude plugin validate . --strict` must pass (`npm test` runs it).
- Test locally with `claude --plugin-dir .`, then `/agents`, `/mcp`, `/agentic-workflow:setup`, `/agentic-workflow:start --dry-run`.
