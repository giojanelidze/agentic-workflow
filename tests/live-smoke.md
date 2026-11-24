# Live smoke tests: OAuth, board access, one real bug

Manual tests against a real Jira site. They come before any mocked eval suite, because mock fixtures must copy the real response shapes.

This file holds the generic cases only. Fill in results in a private notes file outside the repo: real ticket keys, site URLs, account ids and ticket text must not be committed.

Run everything from the **target repo** (the repo you work in), not from this plugin repo: the plugin repo's root `.mcp.json` is also a project-scope server (`atlassian`, "Pending approval"), so working here shows two Atlassian servers. If asked to approve the project `atlassian` server, decline.

Slash commands (`/mcp`, `/agentic-workflow:setup`, `/agentic-workflow:start`) are interactive: the operator runs them in a session started with `claude --plugin-dir "<plugin>"`. Everything marked *checker* can be done from a shell.

## Stage 1: OAuth and board access

| # | Check | Who / how | Pass |
|---|---|---|---|
| L1 | Authorization | Operator: `/mcp` → `plugin:agentic-workflow:atlassian` → Authenticate (browser). Alternative to try: `claude --plugin-dir "<plugin>" mcp login plugin:agentic-workflow:atlassian` | Checker: `claude --plugin-dir "<plugin>" mcp list` shows the server as connected (authorization only: `mcp list` also shows a server that dedup suppresses, so it proves nothing about tools). Then confirm in the `init` event of a headless run (see L3) that tools with the server's prefix exist; if they are absent, apply L14 |
| L2 | Token persistence | Checker: the same `mcp list` in a fresh process after all sessions are closed, and again hours later; repeat the `init` event check from L1 | Still connected, no new authorization, tools with the prefix still present (or still suppressed exactly as in L14) |
| L3 | Tool names | Checker: `claude -p "<prompt>" --plugin-dir … --output-format stream-json --verbose` and read `tools` and `mcp_servers` from the `system`/`init` event (verified shape). Put the prompt **before** `--allowedTools`: that flag is variadic and swallows a trailing prompt. Fallback: operator copies the tool list from the `/mcp` panel | Every tool the agent and the setup skill call (the part after the prefix) exists on the server in use; the server's prefix matches one of the wildcards in `agents/jira-analyst.md` `tools:`; none is misspelled. Check each prefix that appears in `mcp_servers` (the plugin server may be absent, see L14) |
| L14 | Server suppression | Checker: debug log of a headless run with `--debug-file`, search for `Lazy dedup`; compare `mcp list` with the `init` event | If a claude.ai connector has the same URL as the plugin's server, the plugin server is suppressed and only connector prefixes exist. Setup must still find a working prefix and the analyst must work with it |
| L4 | Site | Checker: `getAccessibleAtlassianResources` | Only the expected site; `cloudId` and base URL available. The call lists a site once per product with the same `id`; setup must merge entries by `id` |
| L5 | Setup skill | Operator: `/agentic-workflow:setup` | `.claude/agentic-workflow.json` (`jira` section and `baseBranch`), `.agentic-workflow/local.json` (including `github`) and the exclude entry written; permission rules written only after consent; accountId stored, not a display name; no secrets stored. Checker: `assigneeAccountId` equals `account_id` from `<mcpPrefix>atlassianUserInfo` on the same server and site (an id from another server or account finds no tickets and fails silently); `mcpPrefix` matches a server that appears in the `init` event |
| L6 | Board access | Checker: `searchJiraIssuesUsingJql` with the stored `boardJql` + assignee | Same tickets as the operator sees on the board (count and keys); only `openStatuses` |

## Stage 2: one real bug

| # | Check | Who / how | Pass |
|---|---|---|---|
| L7 | Bug, `--dry-run` | Checker lists the operator's open Bugs read-only; operator picks one and runs `/agentic-workflow:start <KEY> --dry-run` | Valid result JSON; preview `brief.md` with exact headings and `dor`; operator and checker compare the verdict with the ticket and note disagreements; no Jira write; ledger, `pending/` and lock unchanged; `last_run.json` JQL contains the assignee accountId, the board condition and quoted statuses; call and token counts noted |
| L8 | Question loop | Operator, real run with `writeMode: none` (dry-run has no pending file) on a ticket that ends NEEDS_INFO | Questions are specific, in `operatorLanguage`, at most 4 per round, include what was already found; pending file and `rounds` update; no third round (`needs_refinement`) |
| L9 | Controlled write (explicit consent only) | Operator: `writeMode: labels`, one ticket | An `agent-*` label added, existing labels untouched, no comment, no transition; `updated` re-read so the next run does not see the ticket as STALE |
| L10 | Re-run | Operator: `next`, then `analyze <KEY>` | `next` never returns the handed-off ticket and writes no label again; `analyze <KEY>` returns `READY` with the existing brief and writes nothing |
| L11 | Auth failure | Operator: `claude mcp logout …` (or clear in `/mcp`), then run again; re-authorize afterwards | `ERROR auth`, `retryable: false`, message tells to run `/mcp`; lock released |
| L12 | Token lifetime | Checker: `mcp list` the next day | No re-authorization needed; record the observation, do not assume |
| L13 | Install path | Operator: install through a local marketplace (`/plugin marketplace add <path>` + install) and repeat L1–L2 | Authorization works the same as with `--plugin-dir` (unverified) |
| L15 | Assignee mismatch warning | Operator: set `assigneeAccountId` in `.agentic-workflow/local.json` to another valid accountId (note the original first), run `/agentic-workflow:start --dry-run`, then restore the original | Prerequisites show a warning that the account differs from the authenticated one and suggest `/agentic-workflow:setup`; the run continues; with the original id restored there is no warning |

## Stage 3: investigation (code and browser)

Run L20 first: if the browser tools cannot be used by the subagent, the browser part of the design changes.

| # | Check | Who / how | Pass |
|---|---|---|---|
| L20 | Browser tools inside the subagent | Operator: enable the browser in setup, run `/agentic-workflow:start <KEY> --dry-run` on a bug whose repro is a page | The analyst can call `<browserPrefix>tabs_context_mcp` and `navigate` as a subagent; note any permission prompt, any deferred-tool problem and the exact error. If it cannot, stop and rethink (the browser step may have to move to the main thread) |
| L16 | Question answerable from code | Operator: a ticket whose missing fact is in the repo (for example which component renders a label) | The question is not asked; `brief.md` has `## Evidence` with `path:line`, a quote and the commit; checker runs `git grep -n` on each quote and it exists at that line; `dor` source is `code` |
| L17 | Question not answerable | A ticket whose missing fact is the expected behavior | Still a question; its text ends with `Checked:`; no invented answer; no `## Evidence` entry for that criterion |
| L18 | Browser repro on non-production | A bug reproducible by navigation only, `appUrl` set | Evidence has URL, steps, observed text and time; only allowed origins opened; nothing typed or submitted; the tab is closed afterwards; `last_run.json` has the action counts (≤20) |
| L19 | Browser unavailable | Browser off, or Chrome closed, or a login page | Criterion stays a question that says what failed; open risk added; no `ERROR`; the run continues |
| L21 | Contradiction | A ticket whose description disagrees with the code or the page | Both sides listed in `## Open risks` and asked; the analyst does not choose |
| L22 | Vague ticket | A ticket with a description but no acceptance criteria | `brief.md` contains no acceptance criterion the ticket does not state; either S1 is asked as a question or every criterion names its source; nothing is "completed" by the analyst |
| L23 | Provenance | Checker, on any `READY` brief: every `## Evidence` quote | Code quotes found by `git grep -n -F` at the stated `path:line` and commit; Jira and Confluence quotes found verbatim in the ticket or page; operator answers verbatim; any quote that does not exist fails the run |
| L24 | Pattern is not a decision | A Story without a Figma link, in a repo that has a similar component | S2 stays a question; the similar component appears only as a marked option (`from code: path:line`), never as met |

## Stage 4: one-time setup and connections (Jira and GitHub)

Run from the target repo. Before L26 and L27 note `gh auth status --json hosts` (which account is `active`); L27 compares against it. `bin/gh-as` must be on the Bash tool's PATH (plugin enabled) and executable.

| # | Check | Who / how | Pass |
|---|---|---|---|
| L25 | Configured repo: what to change | Operator: `/agentic-workflow:setup` on a repo with a complete setup, answer "Nothing"; run it again and choose "GitHub and repo"; then `/agentic-workflow:setup --reconfigure github` | The first screen shows the current values in its question text and one question "what to change"; "Nothing" ends with the summary and writes nothing. "GitHub and repo" asks only the GitHub screen, then "Anything else?". `--reconfigure github` skips screen 0. Rules that exist only for another prefix count as missing |
| L26 | Account binding | Operator: setup in a repo with two gh accounts on one host where the active one cannot write (or on an SSH-alias remote) | Setup lists both with their permission, proposes the account that can write (and, on SSH, the one `ssh -T` reports), stores `github.host` and `github.account`, and does not store a token or `<owner>/<repo>` |
| L27 | gh state untouched | Checker: `gh auth status --json hosts` before and after setup and after a `/agentic-workflow:start --dry-run` and a full run; in another terminal run `gh auth switch` between two runs | `active` is identical before and after; a switch made in another terminal does not change which account the workflow uses, and the workflow never changes the other terminal's active account |
| L28 | Wrong or missing identity | Operator: set `github.account` to a READ-only or logged-out account (note the original, restore afterwards), run `/agentic-workflow:start --auto` | The run stops in the preflight, `--auto` or not, naming the account and repository and the fix; nothing is pushed; with the original restored the preflight passes |
| L29 | Jira site binding | Operator: set `jira.cloudId` to another site id the connector cannot reach (note the original), run `start --dry-run`; then set `assigneeAccountId` to another valid id | The first stops with the connector/site message; the second only warns (L15 is unchanged) |
| L30 | No preflight prompts | Operator: run `start` right after setup in a fresh session | The preflight (`atlassianUserInfo`, `getAccessibleAtlassianResources`, the `gh-as … repo view` check) runs without a permission prompt for the current prefix and account |
| L31 | SSH-alias remote | Checker: in a repo whose `origin` is `git@<alias>:<owner>/<repo>.git`, run `gh-as --account <a> --host <host> repo view <host>/<owner>/<repo> --json viewerPermission` and `… pr list -R <host>/<owner>/<repo> --head <branch>` | Both work; a publish without a binding prints a compare URL on the real host, not on the alias |
| L32 | Wrapper in a subagent | Checker: `claude -p "<prompt>" --plugin-dir … --allowedTools "Agent" "Bash(command -v gh-as)" "Bash(gh-as --account <a> --host <h> repo view *)"` asking `agentic-workflow:test-runner` to run those two commands | `command -v gh-as` prints the plugin's `bin/gh-as`; the second command returns the permission without a prompt. Repeat with the plugin installed through a local marketplace to confirm the executable bit survives (unverified) |
| L33 | Fresh repo asks | Operator: `/agentic-workflow:setup` in a repo with neither config file | Setup asks (never ends with a status): Jira, board, GitHub and repo, behavior screens, then the final confirm; the detected or stored value is the first, recommended option; a question with one possible answer is skipped and listed in the summary; `.claude/agentic-workflow.json` and `.agentic-workflow/local.json` (including `github`) written after "Write now?" |
| L34 | Older config without `github` | Operator: remove the `github` key from `.agentic-workflow/local.json` (note it first), run `/agentic-workflow:setup` | Setup notices the missing keys, asks only the GitHub screen (and the final confirm), leaves the other values untouched, and does not print a status and stop |
| L35 | Guard against skipped questions | Operator: run a plain `/agentic-workflow:setup` on a fresh repo and decline every screen | The run does not end after only printing a status: it asks again or ends with an explicit "nothing written" the user chose |
| L36 | Authorization by link | Operator: a repo whose Atlassian server is not signed in (for example the plugin's own server before its first login, or after `claude mcp logout`); run `/agentic-workflow:setup`, then `/agentic-workflow:start --dry-run` | Setup finds the server by its `authenticate` tool, shows one clickable link (no instructions to run `/mcp`), and after "done" continues with `atlassianUserInfo`; with the account that lacks the project it reports the site/project mismatch. The `start` preflight does the same on an authorization failure. Declining the `authenticate` call falls back to `/mcp` and the call is not repeated |
| L37 | Authorization event | Operator: a repo whose Atlassian server is not signed in; run `/agentic-workflow:setup`, open the link, approve, and type nothing | `wait-mcp --check` said "not connected"; the watcher was started before `authenticate`; the turn ended with the link as its last text; after approval setup continues with the site question **without** being told "done", and the session really has the server's tools. If the watcher ends but the tools are missing, the one-click question appears |
| L38 | Resume after a stage | Operator: stop setup right after "Jira saved" (Ctrl-C), run it again | Stage 1 is not asked again; setup starts Stage 2; `.claude/agentic-workflow.json` has the `jira` keys of Stage 1 and the Jira permission rules are present |
| L39 | Remote callback | Operator: with remote control on, open the link on another device | The page ends on a `localhost` address that does not load; pasting that address here finishes the authorization through `complete_authentication`, and setup continues |
| L40 | gh login event | Operator: in a repo whose SSH login is not logged in to gh, run setup to Stage 2 and run the proposed `! gh auth login --hostname <host>` as that account | Setup shows exactly one command and had started `wait-gh-login` first; when the account appears Stage 2 continues by itself, and the message about the new active account is correct |
| L41 | Watchers | Checker: `wait-mcp --check` on a connected server, on one that needs authorization, and on an unknown name; `wait-mcp <needs-auth server> --max-seconds 8`; `wait-gh-login --host <host> --login <logged-in login>` and with an unknown login and `--max-seconds 5` | Exit codes 0 / 1 / 2, then 1 ("timeout"); 0 ("login …:success") and 1 ("timeout"); no token is printed; gh's active account is unchanged |

Not testable without a second account and a second site: two Atlassian accounts (second connector) and GitHub Enterprise Server (`GH_ENTERPRISE_TOKEN`); try them by hand.

## Notes
- No agent command removes `agent-*` labels from a ticket after L9; remove the test label by hand in Jira.
- Raw tool responses captured during these runs stay outside the repo; only sanitized copies (no PII, no company names) may become mock fixtures later.
