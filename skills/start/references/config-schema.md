# Configuration

Written by `/dev-workflow:setup`. Every field outside `jira` is optional; defaults apply when missing.

## .claude/dev-workflow.json (target repo, team-shared, may be committed)

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
- `commands.*` `null` means discover from `package.json`, `nx.json`, `Makefile`, CI config.
- Defaults: `branchPattern` `<type>/<KEY>-<slug>` (`<type>` from the ticket type: `feat`, `fix`, `chore`), `commitFormat` `<KEY>: <summary>`, `prTitle` `[<KEY>] <summary>`, `prDraft` true, `baseBranch` from `gh repo view --json defaultBranchRef`.

## .dev-workflow/local.json (personal, excluded from git)

```json
{ "assigneeAccountId": "5f1…", "operatorLanguage": "ka", "mcpPrefix": "mcp__claude_ai_Atlassian_Rovo__", "browserPrefix": "mcp__claude-in-chrome__" }
```

`browserPrefix` (optional) is the tool-name prefix of the Claude in Chrome server, found by setup the same way as `mcpPrefix`.

`assigneeAccountId` is a Jira accountId, never a display name. `mcpPrefix` is the tool-name prefix of the Atlassian server in use: the plugin's own server (`mcp__plugin_dev-workflow_atlassian__`) or a claude.ai connector (`mcp__claude_ai_Atlassian_Rovo__`). It is personal because Claude Code hides the plugin's server when a connector with the same URL exists, so it differs per user. Setup stores it; the analyst reads it from here.

## Plugin options (`/plugin configure dev-workflow`)
`defaultAuto`: skip checkpoints by default.
