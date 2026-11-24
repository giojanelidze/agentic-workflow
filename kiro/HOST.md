# agentic-workflow on Kiro: host map

This file is loaded by every agentic-workflow agent and prompt on Kiro CLI (kiro-cli 3.x, V3 engine). The shared files (`agents/*.md`, `skills/*/SKILL.md`, `skills/start/references/*.md`) were written for Claude Code. **Where they disagree with this file, this file wins.** Everything this file does not mention works the same on Kiro.

`PLUGIN` means the folder `~/.kiro/agentic-workflow-plugin` (a link to the plugin checkout). Write it with the `~`, exactly like this, in every command and path: Kiro's permission rules match the text of a command.

## Names
- `/agentic-workflow:start`, `/agentic-workflow:setup` and `/agentic-workflow:media` are the prompts `/agentic-workflow-start`, `/agentic-workflow-setup` and `/agentic-workflow-media`. Flags such as `--reconfigure jira` are typed after the prompt as before.
- The agent `agentic-workflow:<a>` (or a bare `<a>`) is the Kiro agent `agentic-workflow-<a>`: `agentic-workflow-jira-analyst`, `agentic-workflow-implementation-planner`, `agentic-workflow-implementer`, `agentic-workflow-test-runner`, `agentic-workflow-correctness-reviewer`, `agentic-workflow-conventions-reviewer`, `agentic-workflow-security-reviewer`, `agentic-workflow-performance-reviewer`, `agentic-workflow-review-aggregator`, `agentic-workflow-pr-publisher`, `agentic-workflow-media-analyst`.
- The main thread is the agent `agentic-workflow` (`kiro-cli --agent agentic-workflow`). `${user_config.defaultAuto}` is `false`.

## Starting an agent
- "Start", "invoke" or "run" an agent is `invoke_sub_agent` with `name` and `prompt` only. The `prompt` is the task prompt the shared file describes (the `State:`, `Config:` and `Local:` lines and the rest). There is no `model` parameter, no background run and no output file.
- The call waits and returns the agent's final message. That message is "the result", "the final line" and "its output file" of the shared files; save a reply verbatim where they say so.
- Several calls in one turn run in parallel (at most 5): start the four reviewers in one message and every other stage alone.
- An agent started this way never asks the user anything; only the main thread does. Every Kiro agent has the built-in tools `user_input`, `disclose_context` and `report_progress` and none of them can be switched off: a stage agent never calls `user_input`.

## Tools
| shared text | Kiro |
|---|---|
| Read | `read_file` (`path`; it returns PNG, JPEG, GIF and WebP files as pictures) |
| Write | `fs_write` (`path`, `text`; it creates missing folders, so never run `mkdir` for run files) |
| Edit | `str_replace` |
| Grep, Glob | `grep_search`, `file_search` |
| Bash | `execute_bash` (`command`, and `timeout` in milliseconds: where the shared text says "the Bash `timeout` parameter", pass `timeout`) |
| Skill, ToolSearch, Monitor, TaskStop | not available |

## Asking the user
There is no question tool. Where the shared text says AskUserQuestion, "ask", checkpoint or "single-select": write **one message** with at most 4 numbered questions; under each, lettered options with the recommended one first and marked "(Recommended)", and say that anything else may be typed. Then end your turn and read the answer from the user's next message ("Other" is a typed answer; a "single-option question" is a message that asks the user to type `done`). The limits on options and header length in the shared text do not apply. Put the values in the question text.

## Waiting for something
Nothing runs in the background and nothing wakes you. Where the shared text starts `wait-mcp` or `wait-gh-login` in the background, or says "continue by yourself when the watcher ends", do this instead: tell the user exactly what to do, end your turn, and continue when they write `done`; then check once, and never assume. Every continuation must be safe to run twice. `!<command>` typed by the user runs a command in this session.

## Running scripts
- The scripts are `PLUGIN/bin/<name>`; there is no PATH entry. Setup's permission rules allow exactly these forms, so use them literally:
  - `PLUGIN/bin/aw-paths --tool kiro` with no other argument. It prints every `key=value` line; read them. Stop with "wrong host" when `state` does not contain `/.kiro/agentic-workflow/`.
  - `PLUGIN/bin/gh-as --account <account> --hostname <host> <subcommand> …`, in exactly that argument order. Wherever the shared text writes `--host <host>` after `--account`, write `--hostname <host>`: Kiro's shell tool refuses any command that contains `--host <word>` or `--port <number>` (it takes it for a dev server), so never put those two flags in a command you run.
  - `PLUGIN/bin/jira-attachment …` and `PLUGIN/bin/media-prep …`.
- A command is one plain command: no `;`, `&&`, `||`, `|`, `$(…)`, backticks, `>`, `>>`, `<`, `&`, `tee`, or a variable assignment in front of it. Kiro's rules cannot see a redirect after an allowed command, so this rule is yours to keep.
- `wait-mcp` and `wait-gh-login` do not exist for you.

## Atlassian
- The server is `agentic-workflow-atlassian`, and `mcpPrefix` is `agentic-workflow-atlassian::`. A tool that the shared text calls `<mcpPrefix><tool>` is the id `agentic-workflow-atlassian::<tool>`: load it with `tool_load` (`tool_ids`), then run it with `tool_call` (`tool_id`, `arguments`). Do not look for a tool by its bare name and do not use another Atlassian server.
- Not signed in (the tool cannot be loaded, or answers with an authorization error): this replaces "Waiting for an authorization" and the `authenticate` tools. Ask the user to type `/mcp`, choose `agentic-workflow-atlassian` and sign in with the Atlassian account that has the project, then to write `done`; load the tool again. If the server is missing from `/mcp`, the plugin is not installed: tell the user to run `PLUGIN/bin/kiro-install`.
- Jira writes (`editJiraIssue`, `addCommentToJiraIssue`, `transitionJiraIssue`) pass the plugin's guard, which blocks what the repository's write mode (or what the user accepted in setup) does not reach. Inside the mode Kiro still shows its own approval prompt for every write; tell the user once, before the first write, that this is expected.

## A blocked or declined call
- A message that starts with `agentic-workflow:` after a tool call comes from the guard: that write is not allowed here. It is final: do not retry and do not look for another way; the analyst returns `ERROR` stage `config` with the text, and the user fixes it with `/agentic-workflow-setup --reconfigure jira`.
- A call that the user **declines** at Kiro's approval prompt (the answer says the permission was denied or not answered) is not a configuration error: do not return `config`. Report the call as not done (the analyst: an open risk "write declined by the user") and go on with whatever does not need it.

## Setup and permissions on Kiro
These replace the Claude Code text with the same name:
- `**Tool names.**`, `**Atlassian server.**` and `**Authorization.**`: there is one server (see Atlassian), so skip the question which connector to use; sign in as described there.
- `## Waiting for an authorization`: see Waiting for something and Atlassian.
- `## Permission rules`, the rule lists at the end of each stage, checks 6 and 7, and `## Migration from an older version`: Kiro's file tool may not write `~/.kiro/settings/`, so setup writes **no** rule file. At the end of a stage print one command for the user, for example `! PLUGIN/bin/kiro-permissions apply --github <account>@<host>` (Stage 2; add `--pictures` when pictures are on and `--no-pictures` when they are switched off; Stages 1 and 3 need only `apply`). Say that it adds only read tools and never a Jira write tool, that the block is one for this computer and keeps what other repositories added, and that `print` shows it first. Check 6 is: the block `# >>> agentic-workflow` in `~/.kiro/settings/permissions.yaml` names the current gh account. Check 7 is: no `allow` rule in that file names `editJiraIssue`, `addCommentToJiraIssue` or `transitionJiraIssue`, or covers `fs_write` more widely than `~/.kiro/agentic-workflow/state/**` and `~/.kiro/agentic-workflow/memory/**`; ask the user to remove such a rule by hand. Migration items 1 to 3 do not apply.
- Paths: `~/.claude/agentic-workflow/…` is `~/.kiro/agentic-workflow/…` (`aw-paths --tool kiro` prints them). The team config stays `<repo>/.claude/agentic-workflow.json`, shared with Claude Code users; the personal values, the run files and the implementer's memory are Kiro's own.
- `Local` stores `mcpPrefix` as `agentic-workflow-atlassian::` and never gets `browserPrefix` or `acceptedOrigins`.
- Writing `Config` and `Local`: tell the user to approve each prompt **once** and never to choose "always allow" for them (they are trusted input of the guard).
- Browser: not available on Kiro. Skip check 4 and the browser question of Stage 3, and **never change or remove `jira.investigation` in `Config`** (a Claude Code teammate may use it); store only `investigation.code` when it is missing.
- Preflight `- Hooks:` of `start`: run `PLUGIN/hooks/guard --tool kiro --check-alive`. `alive`: go on. `off`: stop, even with `--auto`: the workspace is not trusted or the hooks are disabled, so the guard is not running; ask the user to restart `kiro-cli` and trust the workspace.
- Preflight `- Jira authorization:`: as in Atlassian above.
- Pictures: `brew`, `pbpaste` and the keychain work as written; "Claude Code asks once" is Kiro's approval prompt.

## Memory
The implementer keeps its repository knowledge in `~/.kiro/agentic-workflow/memory/implementer/` (its wrapper says so); the layout is the one in `implementer.md`.

## Not available on Kiro
Claude in Chrome (so no browser investigation), the `Agent` tool and model overrides, plan mode, the claude.ai connectors, `superpowers`.
