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
| L5 | Setup skill | Operator: `/agentic-workflow:setup` | `.claude/agentic-workflow.json` (`jira` section), `.agentic-workflow/local.json` and the exclude entry written; permission rules written only after consent; accountId stored, not a display name; no secrets stored. Checker: `assigneeAccountId` equals `account_id` from `<mcpPrefix>atlassianUserInfo` on the same server and site (an id from another server or account finds no tickets and fails silently); `mcpPrefix` matches a server that appears in the `init` event |
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

## Notes
- No agent command removes `agent-*` labels from a ticket after L9; remove the test label by hand in Jira.
- Raw tool responses captured during these runs stay outside the repo; only sanitized copies (no PII, no company names) may become mock fixtures later.
