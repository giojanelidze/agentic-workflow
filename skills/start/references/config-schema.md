# Configuration

Written by `/agentic-workflow:setup`. Every field outside `jira` is optional; defaults apply when missing.

## .claude/agentic-workflow.json (target repo, team-shared, may be committed)

```json
{
  "baseBranch": "main",
  "branchPattern": "<type>/<KEY>-<slug>",
  "commitFormat": "<KEY>: <summary>",
  "prTitle": "[<KEY>] <summary>",
  "prDraft": true,
  "reviewers": [],
  "commands": { "lint": null, "typecheck": null, "test": null, "build": null },
  "jira": {
    "cloudId": "…",
    "baseUrl": "https://company.atlassian.net",
    "projectKey": "ABC",
    "boardJql": "project = ABC AND sprint in openSprints()",
    "openStatuses": ["To Do", "Selected for Development"],
    "issueTypes": ["Bug", "Story", "Task"],
    "confluenceSpaces": ["SAM"],
    "confluenceMaxPages": 3,
    "implementerScope": "frontend-angular",
    "writeMode": "labels+comments",
    "transitions": { "onHandoff": null, "onPrOpened": "Code Review" },
    "maxCandidatesPerRun": 5,
    "investigation": {
      "code": true,
      "browser": { "appUrl": "https://staging.example.com", "allowedOrigins": ["https://staging.example.com"] }
    }
  }
}
```

- `boardJql` must contain neither an assignee clause nor an `ORDER BY`; the analyst adds `assignee = <accountId>` and its own ordering.
- `transitions.*` are transition **names**; the analyst resolves them to ids at call time.
- `writeMode`: `none` | `labels` | `labels+comments` | `labels+comments+transition`. Setup mirrors it in the user's permission rules (write tools outside the mode go to `deny`).
- `investigation` (optional): before asking the operator, the analyst looks for the answer in the repo (`code`, default true) and, if `browser` is set, in the running app. The browser is read-only, limited to `allowedOrigins`, and must point at a non-production environment. Without `browser` (or without `browserPrefix` in `local.json`) the browser is not used.
- `baseBranch`: the branch feature branches start from and the pull request targets (`gh pr create --base`). `/agentic-workflow:setup` asks for it and writes it. Without it the orchestrator uses the repository's default branch, and asks if it cannot find one. It applies to the whole repository, not to a single ticket.
- `commands.*` `null` means discover from `package.json`, `nx.json`, `Makefile`, CI config.
- Defaults: `branchPattern` `<type>/<KEY>-<slug>` (`<type>` from the ticket type: `feat`, `fix`, `chore`), `commitFormat` `<KEY>: <summary>`, `prTitle` `[<KEY>] <summary>`, `prDraft` true, `baseBranch` from the repository's default branch (`gh-as … repo view --json defaultBranchRef`, or `git ls-remote --symref origin HEAD` without a GitHub binding).

## .agentic-workflow/local.json (personal, excluded from git)

```json
{
  "assigneeAccountId": "5f1…",
  "operatorLanguage": "ka",
  "mcpPrefix": "mcp__claude_ai_Atlassian_Rovo__",
  "browserPrefix": "mcp__claude-in-chrome__",
  "github": { "host": "github.com", "account": "octocat" }
}
```

`browserPrefix` (optional) is the tool-name prefix of the Claude in Chrome server, found by setup the same way as `mcpPrefix`.

`github` binds this repository to one gh account: `host` is the real GitHub host (an SSH alias such as `github.com-personal` in the remote is resolved with `ssh -G`), `account` is the login whose token every gh call uses. It is personal because each person logs in with their own account. Neither a token nor `<owner>/<repo>` is stored: the repository is read from `origin` on every run. All gh calls go through `bin/gh-as --account <account> --host <host> <gh arguments>`, which hands that account's token (from `gh auth token --user`) to one gh process through `GH_TOKEN` (`GH_ENTERPRISE_TOKEN` for a host that is neither `github.com` nor `*.ghe.com`). gh's active account and config are never changed, so other terminals are not affected. Without a `github` section the publish stage only pushes and writes `pr.md` with a compare URL.

## Supported Atlassian prefixes

`mcpPrefix` must be one of these; they are exactly the Atlassian entries in the `tools:` allowlist of `agents/jira-analyst.md`, which a subagent cannot go beyond. Keep this list and that allowlist identical. Setup offers only these and explains why it does not offer any other prefix it finds.

- `mcp__plugin_agentic-workflow_atlassian__` (the plugin's own server)
- `mcp__claude_ai_Atlassian_Rovo__` (claude.ai connector)
- `mcp__claude_ai_Atlassian_Rovo_2__` (a second claude.ai connector, for example another Atlassian account)

## Connection checks

Setup (when a configured repository is re-run, before it asks what to change) and the preflight of `/agentic-workflow:start` verify the connections, not only that the files exist: the Jira site `jira.cloudId` must be among the sites the stored connector can reach, and the gh account must be logged in with `WRITE`, `MAINTAIN` or `ADMIN` on the repository. A wrong connector or a wrong gh account stops the run; a different `assigneeAccountId` only warns, because it may be another person's id.

`assigneeAccountId` is a Jira accountId, never a display name. `mcpPrefix` is the tool-name prefix of the Atlassian server in use: the plugin's own server (`mcp__plugin_agentic-workflow_atlassian__`) or a claude.ai connector (`mcp__claude_ai_Atlassian_Rovo__`). It is personal because Claude Code hides the plugin's server when a connector with the same URL exists, so it differs per user. Setup stores it; the analyst reads it from here.

## Plugin options (`/plugin configure agentic-workflow`)
`defaultAuto`: skip checkpoints by default.

## Setup stages

`/agentic-workflow:setup` works in three stages and saves each one when it is finished, so an interrupted setup continues at the first stage whose keys are missing. This table says which stage owns which required key and which permission rules it writes. Optional keys (`jira.transitions.*`, `jira.investigation`, `browserPrefix`) never make setup incomplete when absent.

| Stage | Required keys it owns | Permission rules it writes |
|---|---|---|
| 1. Jira | `local.json`: `mcpPrefix`, `assigneeAccountId`. `jira`: `cloudId`, `baseUrl`, `projectKey`, `boardJql`, `openStatuses`, `issueTypes`, `confluenceSpaces`, `confluenceMaxPages`, `writeMode` | the Jira allow/deny rules for `mcpPrefix` (read tools, the write tools `writeMode` permits, the rest denied) and `Bash(wait-mcp *)` |
| 2. GitHub and repo | `local.json`: `github.host`, `github.account`. Top level: `baseBranch`. `jira.implementerScope` | `Bash(gh-as --account <account> --host <host> …)` read rules and `Bash(wait-gh-login *)` |
| 3. Behavior | `local.json`: `operatorLanguage`. `jira.maxCandidatesPerRun` | browser rules (when enabled) and the implementer memory rules |
