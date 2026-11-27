# Configuration

Written by `/agentic-workflow:setup`. Every field outside `jira` is optional; defaults apply when missing.

## Storage

There are two files. Both are found with `bin/aw-paths`; the agents get their absolute paths from the orchestrator (`Config`, `Local`) and never compute them.

- **Repository config** (`Config`): the settings that describe the project (Jira site and project, `baseBranch`, `jira.*`). The user chooses in setup where it lives, and the plugin derives the choice from the files that exist (`aw-paths` prints it as `mode`):
  - **`team`**: `<repo>/.claude/agentic-workflow.json`, committed and shared with the team. A teammate's change reaches you through `git pull`, but it can never widen what the plugin may do for you: the guard and the preflight apply the lower of the shared `writeMode` and the `acceptedWriteMode` you chose in setup, and only the browser origins you accepted (`acceptedOrigins`, both in `local.json`). Setup does not rewrite keys that already exist in a shared file.
  - **`personal`**: `~/.claude/agentic-workflow/repos/<host>/<owner>/<repo>/config.json`, same schema. Nothing is written into the repository.
  - `none` (not set up) and `conflict` (both files exist) stop `start` and send the user to setup.
- **Personal values** (`Local`): `~/.claude/agentic-workflow/repos/<host>/<owner>/<repo>/local.json`, always outside the repository.
- **On Kiro** (`aw-paths --tool kiro`) the personal config `config.json`, `local.json` and `State` live under `~/.kiro/agentic-workflow/` instead (same layout); the team file in the repository is the same file for both tools. A repository can therefore be set up in both tools with different personal values.

The run files (`State`) are outside the repository in both modes; see `state-schema.md`.

## Repository config (`.claude/agentic-workflow.json` in team mode, `config.json` in personal mode)

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
    },
    "media": { "enabled": true, "auto": true, "maxFiles": 6, "maxBytes": 52428800, "maxImages": 24 }
  }
}
```

- `boardJql` must contain neither an assignee clause nor an `ORDER BY`; the analyst adds `assignee = <accountId>` and its own ordering.
- `transitions.*` are transition **names**; the analyst resolves them to ids at call time.
- `writeMode`: `none` | `labels` | `labels+comments` | `labels+comments+transition`. It is enforced by the plugin's guard hook (`hooks/guard`), per repository and only for the `jira-analyst`: the hook allows a write tool inside the mode and denies the rest. It is never written as a user-level permission rule, because a `deny` rule at user level would apply to every repository and every session at once. The effective mode is the lower of `writeMode` here and `acceptedWriteMode` in `local.json`.
- `investigation` (optional): before asking the operator, the analyst looks for the answer in the repo (`code`, default true) and, if `browser` is set, in the running app. The browser is read-only, limited to `allowedOrigins`, and must point at a non-production environment. Without `browser` (or without `browserPrefix` in `local.json`) the browser is not used.
- `media` (optional): look at the screenshots and screen recordings attached to a ticket (see "Pictures" below). `enabled` switches it on for the repository; the user's own consent is `media` in `local.json`, so a shared file can enable it without anything happening on a computer that has not set it up. `auto` (default true) lets `/agentic-workflow:start` do it when the ticket text is not enough; with false only `/agentic-workflow:media <KEY>` does. `maxFiles` (default 6) is the number of attachments looked at, `maxBytes` (default 52428800, 50 MB) the largest one downloaded, `maxImages` (default 24) the number of pictures (screenshots plus video frames) per ticket.
- `baseBranch`: the branch feature branches start from and the pull request targets (`gh pr create --base`). `/agentic-workflow:setup` asks for it and writes it. Without it the orchestrator uses the repository's default branch, and asks if it cannot find one. It applies to the whole repository, not to a single ticket.
- `commands.*` `null` means discover from `package.json`, `nx.json`, `Makefile`, CI config.
- Defaults: `branchPattern` `<type>/<KEY>-<slug>` (`<type>` from the ticket type: `feat`, `fix`, `chore`), `commitFormat` `<KEY>: <summary>`, `prTitle` `[<KEY>] <summary>`, `prDraft` true, `baseBranch` from the repository's default branch (`gh-as … repo view --json defaultBranchRef`, or `git ls-remote --symref origin HEAD` without a GitHub binding).

## Personal values (`Local`, never in the repository)

```json
{
  "assigneeAccountId": "5f1…",
  "operatorLanguage": "ka",
  "mcpPrefix": "mcp__claude_ai_Atlassian_Rovo__",
  "browserPrefix": "mcp__claude-in-chrome__",
  "github": { "host": "github.com", "account": "octocat" },
  "acceptedWriteMode": "labels+comments",
  "acceptedOrigins": ["https://staging.example.com"],
  "media": { "email": "you@example.com", "gateway": false }
}
```

`browserPrefix` (optional) is the tool-name prefix of the Claude in Chrome server, found by setup the same way as `mcpPrefix`.

`media` (optional) is the user's consent to picture analysis and the account it uses: `email` is the Atlassian account whose API token is in the system keychain (service `agentic-workflow-atlassian`; the token is never in any file), `gateway` is true when that token only works through the `api.atlassian.com` address (tokens with scopes). Without `media.email` no picture is ever downloaded, whatever the shared config says; `media` `{ "enabled": false }` records that this user declined a setting a shared file switched on. The analyst also caps whatever the config asks at 10 files, 100 MB per file and 40 pictures per ticket.

`acceptedWriteMode` and `acceptedOrigins` (the latter only when the browser is on) are the **ceiling**: the limits the user chose in setup. What applies in a run is the lower write mode (`min(jira.writeMode, acceptedWriteMode)`) and the overlap of `allowedOrigins` and `acceptedOrigins`. In team mode the shared file can change without the user (a `git pull`), and a user may deliberately accept less than the team file allows; either way the user's limit wins. The guard hook enforces these values, and the preflight of `start` computes them, says in one line when they differ from the config, and passes them to the analyst as `Write mode:` and `Browser origins:`. Nothing stops: accepting more is a choice made in `/agentic-workflow:setup --reconfigure jira|behavior`. The file is read by the guard line by line: keep the formatting setup writes, with every array of strings (such as `allowedOrigins`) on one line. In the default permission modes an agent cannot change this file without a permission prompt (setup is the only writer, in the main conversation); a mode that skips prompts removes that protection for any file.

`github` binds this repository to one gh account: `host` is the real GitHub host (an SSH alias such as `github.com-personal` in the remote is resolved with `ssh -G`), `account` is the login whose token every gh call uses. It is personal because each person logs in with their own account. Neither a token nor `<owner>/<repo>` is stored: the repository is read from `origin` on every run. All gh calls go through `bin/gh-as --account <account> --host <host> <gh arguments>`, which hands that account's token (from `gh auth token --user`) to one gh process through `GH_TOKEN` (`GH_ENTERPRISE_TOKEN` for a host that is neither `github.com` nor `*.ghe.com`). gh's active account and config are never changed, so other terminals are not affected. Without a `github` section the publish stage only pushes and writes `pr.md` with a compare URL.

## Pictures (images and videos attached to tickets)

The Atlassian MCP servers cannot download attachments, so `bin/jira-attachment` does it with an Atlassian API token that `jira-attachment login` keeps in the system keychain (macOS `security`; Linux `secret-tool` is untested). The URL is built only from `jira.baseUrl`'s host (or `cloudId` for the `gateway` address) and a numeric attachment id, never from a link in a ticket. `bin/media-prep` turns a download into files a model can see: a screenshot as it is (HEIC and TIFF converted), a video into a few JPEG frames chosen at the scene changes (needs `ffmpeg`). The frames are looked at by the `media-analyst` agent, which has only `Read` and sees no ticket text; its reply is saved unchanged as `findings-<n>.md` after `media-prep validate`. What a finding may settle is fixed in `agents/jira-analyst.md` (Media and Investigation): only B4 and the actual side of B2; everything else is offered to the operator as a question option. Files live in `<State>/<KEY>/media/<hash>/` (see `state-schema.md`).

## Supported Atlassian prefixes

`mcpPrefix` must be one of these; they are exactly the Atlassian entries in the `tools:` allowlist of `agents/jira-analyst.md`, which a subagent cannot go beyond. Keep this list, that allowlist and the matcher in `hooks/hooks.json` identical (this is the Claude Code side; Kiro has its own, below). Setup offers only these and explains why it does not offer any other prefix it finds.

- `mcp__plugin_agentic-workflow_atlassian__` (the plugin's own server)
- `mcp__claude_ai_Atlassian_Rovo__` (claude.ai connector)
- `mcp__claude_ai_Atlassian_Rovo_2__` (a second claude.ai connector, for example another Atlassian account)

## Kiro

One server, `agentic-workflow-atlassian` (`https://mcp.atlassian.com/v2/mcp`, added by `bin/kiro-install`, declared again inline in the agents of the analyst and the orchestrator). In the Kiro `local.json`, `mcpPrefix` is `agentic-workflow-atlassian::`: a tool is `<mcpPrefix><tool>`, loaded with `tool_load` and run with `tool_call`. A PreToolUse hook sees the same tool as `mcp_agentic_workflow_atlassian_<tool in lower case>` (Kiro lower-cases the id and turns `-` into `_`), which is what the matcher of `kiro/hooks/agentic-workflow.json` and the guard compare. The Kiro `local.json` never has `browserPrefix` or `acceptedOrigins`, and setup never changes `jira.investigation` in a shared config. Permission rules are one marked block written by `bin/kiro-permissions`, not per stage; see `kiro/HOST.md`.

## Connection checks

Setup (when a configured repository is re-run, before it asks what to change) and the preflight of `/agentic-workflow:start` verify the connections, not only that the files exist: the Jira site `jira.cloudId` must be among the sites the stored connector can reach, and the gh account must be logged in with `WRITE`, `MAINTAIN` or `ADMIN` on the repository. A wrong connector or a wrong gh account stops the run; a different `assigneeAccountId` only warns, because it may be another person's id.

`assigneeAccountId` is a Jira accountId, never a display name. `mcpPrefix` is the tool-name prefix of the Atlassian server in use: the plugin's own server (`mcp__plugin_agentic-workflow_atlassian__`) or a claude.ai connector (`mcp__claude_ai_Atlassian_Rovo__`). It is personal because Claude Code hides the plugin's server when a connector with the same URL exists, so it differs per user. Setup stores it; the analyst reads it from here.

## Plugin options (`/plugin configure agentic-workflow`)
`defaultAuto`: skip checkpoints by default.

## Setup stages

`/agentic-workflow:setup` works in three stages and saves each one when it is finished, so an interrupted setup continues at the first stage whose keys are missing. This table says which stage owns which required key and which permission rules it writes. Optional keys (`jira.transitions.*`, `jira.investigation`, `jira.media`, `browserPrefix`, `media`) never make setup incomplete when absent.

| Stage | Required keys it owns | Permission rules it writes (always to the user's `~/.claude/settings.json`, only `allow`) |
|---|---|---|
| 1. Jira | the storage choice (which creates `Config`: the team file or `config.json`). `local.json`: `mcpPrefix`, `assigneeAccountId`, `acceptedWriteMode`. `jira`: `cloudId`, `baseUrl`, `projectKey`, `boardJql`, `openStatuses`, `issueTypes`, `confluenceSpaces`, `confluenceMaxPages`, `writeMode` | read tools of `mcpPrefix`, `Bash(wait-mcp *)`, `Bash(aw-paths)`, `Bash(aw-paths *)`, `Bash(aw-decisions *)`, `Read(~/.claude/agentic-workflow/**)` and `Edit(~/.claude/agentic-workflow/state/**)` |
| 2. GitHub and repo | `local.json`: `github.host`, `github.account`. Top level: `baseBranch`. `jira.implementerScope` | `Bash(gh-as --account <account> --host <host> …)` read rules and `Bash(wait-gh-login *)` |
| 3. Behavior | `local.json`: `operatorLanguage`. `jira.maxCandidatesPerRun`. With the browser on: `browserPrefix` and `acceptedOrigins`. With pictures on: `media` in `local.json` and `jira.media` | the implementer memory rules (`Read` and `Edit` on `~/.claude/agent-memory/**`); with pictures on also `Bash(jira-attachment get *)`, `Bash(jira-attachment check *)` and `Bash(media-prep *)` |

No stage writes a `deny` rule, a rule for a Jira write tool or a browser rule: those depend on the repository and are decided by the guard hook (`hooks/guard`) from the files above. The `Edit` rule is written for the run-file tree `state/` only, never for `local.json` or `config.json`, so a subagent cannot widen its own permissions.
