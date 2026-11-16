# dev-workflow plugin repo

This repo is a Claude Code plugin (`dev-workflow`) and its own single-plugin marketplace. It is not an application: there is no build step.

## Layout
- `.claude-plugin/plugin.json`, `marketplace.json`: manifests. Keep `version` identical in both and in `package.json`.
- `.mcp.json`: the plugin's own Atlassian MCP server, a fallback for users without an Atlassian connector. Claude Code suppresses it when a claude.ai connector has the same URL, so never assume its tool prefix.
- `agents/*.md`: one agent per pipeline stage (`dev-workflow:<name>`). Never put reference files inside `agents/`: it is scanned recursively and every `.md` there becomes an agent.
- `skills/start/SKILL.md`: the orchestrator, `/dev-workflow:start`. Details live in `skills/start/references/`.
- `skills/setup/SKILL.md`: `/dev-workflow:setup`, collects configuration and permissions up front.
- `README.md`, `CHANGELOG.md`, `LICENSE` (ISC).

## Conventions
- Subagents share no context; every handoff goes through files in `.dev-workflow/` of the target repo. Each file has one writer (see `skills/start/references/state-schema.md`). Report headings are fixed (see `report-formats.md`); change them in the agent and the reference together.
- Only `implementer` has persistent memory (`memory: user`, `model: sonnet`). It holds repository knowledge across runs, never ticket data or handoffs; handoffs still go through `.dev-workflow/`. The orchestrator never passes a `model` to a stage agent.
- Only `jira-analyst` touches Jira and Confluence. Only the main thread (the skills) talks to the user; subagents cannot ask questions.
- Jira tools are called as `<mcpPrefix><tool>` with `mcpPrefix` from `.dev-workflow/local.json` (set by `/dev-workflow:setup`, which is the only place that searches for the server). Never find a tool by its bare name: several Atlassian servers may match. The agent's `tools:` lists the plugin server and the standard claude.ai connector names (`Atlassian_Rovo`, `Atlassian_Rovo_2`) by wildcard.
- Agents must not assume a stack: discover scripts and runners in the target repo.
- `superpowers` is optional, never a dependency.
- Everything in this repo is written in English.

## Checks
- `claude plugin validate . --strict` must pass (`npm test` runs it).
- Test locally with `claude --plugin-dir .`, then `/agents`, `/mcp`, `/dev-workflow:setup`, `/dev-workflow:start --dry-run`.
