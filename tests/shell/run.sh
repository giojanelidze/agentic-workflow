#!/bin/sh
# Shell tests for bin/aw-paths and hooks/guard. No network, no claude CLI, no real HOME.
# Run: sh tests/shell/run.sh   (npm test runs it after the plugin validation)

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AW="$ROOT/bin/aw-paths"
GUARD="$ROOT/hooks/guard"

TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
HOME="$TMP/home"; export HOME
mkdir -p "$HOME" "$TMP/bin" "$TMP/work"

# A fake ssh: `ssh -G [--] <alias>` answers like ssh does, so the test needs no ssh config.
cat > "$TMP/bin/ssh" <<'EOF'
#!/bin/sh
[ "$1" = "-G" ] || exit 1
shift
[ "$1" = "--" ] && shift
case "$1" in
  gh-personal) echo "hostname github.com" ;;
  *) echo "hostname $1" ;;
esac
EOF
chmod +x "$TMP/bin/ssh"
PATH="$TMP/bin:$PATH"; export PATH
GIT_CONFIG_NOSYSTEM=1; export GIT_CONFIG_NOSYSTEM

pass=0
fail=0
eq() { # name expected actual
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3" >&2; fi
}
contains() { # name needle haystack
  case "$3" in *"$2"*) pass=$((pass + 1)) ;; *) fail=$((fail + 1)); printf 'FAIL: %s\n  [%s] not in [%s]\n' "$1" "$2" "$3" >&2 ;; esac
}

mkrepo() { # dir origin-url
  mkdir -p "$1"
  git -C "$1" init -q .
  [ -n "$2" ] && git -C "$1" remote add origin "$2"
}

# ---------------------------------------------------------------- aw-paths
R="$TMP/work/repo one"
mkrepo "$R" "https://GitHub.com/Octo/Hello.git"
eq "aw https host lower-cased" github.com "$("$AW" --cwd "$R" --get host)"
eq "aw https owner keeps case" Octo "$("$AW" --cwd "$R" --get owner)"
eq "aw https repo" Hello "$("$AW" --cwd "$R" --get repo)"
eq "aw state path is lower-cased" "$HOME/.claude/agentic-workflow/state/github.com/octo/hello" "$("$AW" --cwd "$R" --get state)"
eq "aw local path" "$HOME/.claude/agentic-workflow/repos/github.com/octo/hello/local.json" "$("$AW" --cwd "$R" --get local)"
eq "aw root with a space" "$(cd "$R" && pwd -P)" "$("$AW" --cwd "$R" --get root)"
eq "aw mode none" none "$("$AW" --cwd "$R" --get mode)"
eq "aw config empty for none" "" "$("$AW" --cwd "$R" --get config)"
eq "aw legacy empty" "" "$("$AW" --cwd "$R" --get legacy)"
eq "aw unknown key" 2 "$("$AW" --cwd "$R" --get nope >/dev/null; echo $?)"
eq "aw subdirectory finds the root" "$(cd "$R" && pwd -P)" "$(mkdir -p "$R/a/b" && "$AW" --cwd "$R/a/b" --get root)"

git -C "$R" remote set-url origin "git@gh-personal:octo/hello.git"
eq "aw scp alias resolved with ssh -G" github.com "$("$AW" --cwd "$R" --get host)"
git -C "$R" remote set-url origin "ssh://git@gh-personal:2222/octo/hello.git"
eq "aw ssh url alias and port" github.com "$("$AW" --cwd "$R" --get host)"
git -C "$R" remote set-url origin "https://user@git.example.com:8443/group/proj.git/"
eq "aw https user, port and trailing slash: host" git.example.com "$("$AW" --cwd "$R" --get host)"
eq "aw https user, port and trailing slash: repo" proj "$("$AW" --cwd "$R" --get repo)"
git -C "$R" remote set-url origin "https://github.com/Octo/Hello"
eq "aw https without .git" Hello "$("$AW" --cwd "$R" --get repo)"

git -C "$R" remote set-url origin "ssh://-oProxyCommand=x/o/r.git"
eq "aw option-like host is refused" 5 "$("$AW" --cwd "$R" >/dev/null 2>&1; echo $?)"
git -C "$R" remote set-url origin "https://github.com/../etc.git"
eq "aw dot-dot owner is refused" 5 "$("$AW" --cwd "$R" >/dev/null 2>&1; echo $?)"
git -C "$R" remote set-url origin "https://github.com/o/r s.git"
eq "aw space in repo name is refused" 5 "$("$AW" --cwd "$R" >/dev/null 2>&1; echo $?)"
git -C "$R" remote set-url origin "/srv/git/repo.git"
eq "aw local path origin is refused" 4 "$("$AW" --cwd "$R" >/dev/null 2>&1; echo $?)"
git -C "$R" remote set-url origin "https://github.com/Octo/Hello.git"

mkdir -p "$TMP/work/plain"
eq "aw not a git repository" 3 "$("$AW" --cwd "$TMP/work/plain" >/dev/null 2>&1; echo $?)"
mkrepo "$TMP/work/noorigin" ""
eq "aw no origin" 4 "$("$AW" --cwd "$TMP/work/noorigin" >/dev/null 2>&1; echo $?)"
eq "aw bad usage" 2 "$("$AW" --bogus >/dev/null 2>&1; echo $?)"

# modes
mkdir -p "$R/.claude"
echo '{}' > "$R/.claude/agentic-workflow.json"
eq "aw mode team" team "$("$AW" --cwd "$R" --get mode)"
eq "aw team config path" "$(cd "$R" && pwd -P)/.claude/agentic-workflow.json" "$("$AW" --cwd "$R" --get config)"
PERS="$("$AW" --cwd "$R" --get personal_config)"
mkdir -p "$(dirname "$PERS")"
echo '{}' > "$PERS"
eq "aw mode conflict" conflict "$("$AW" --cwd "$R" --get mode)"
eq "aw config empty for conflict" "" "$("$AW" --cwd "$R" --get config)"
rm "$R/.claude/agentic-workflow.json"
eq "aw mode personal" personal "$("$AW" --cwd "$R" --get mode)"
eq "aw personal config path" "$PERS" "$("$AW" --cwd "$R" --get config)"
rm "$PERS"
mkdir -p "$R/.agentic-workflow"
eq "aw legacy folder" "$(cd "$R" && pwd -P)/.agentic-workflow" "$("$AW" --cwd "$R" --get legacy)"

# the run files never share a tree with local.json and config.json, whatever the repository is called,
# so one permission rule for <base>/state/** can never cover the trusted files
for pair in "state/state" "state/repos" "repos/state" "o/state" "state/r"; do
  mkrepo "$TMP/work/n-$(printf '%s' "$pair" | tr '/' '-')" "https://github.com/$pair.git"
  d="$TMP/work/n-$(printf '%s' "$pair" | tr '/' '-')"
  st="$("$AW" --cwd "$d" --get state)"; lo="$("$AW" --cwd "$d" --get local)"; pc="$("$AW" --cwd "$d" --get personal_config)"
  case "$st" in "$HOME/.claude/agentic-workflow/state/"*) pass=$((pass + 1)) ;; *) fail=$((fail + 1)); printf 'FAIL: state of %s is not under state/: %s\n' "$pair" "$st" >&2 ;; esac
  case "$lo" in "$HOME/.claude/agentic-workflow/state/"*) fail=$((fail + 1)); printf 'FAIL: local.json of %s is under state/: %s\n' "$pair" "$lo" >&2 ;; *) pass=$((pass + 1)) ;; esac
  case "$pc" in "$HOME/.claude/agentic-workflow/state/"*) fail=$((fail + 1)); printf 'FAIL: config.json of %s is under state/: %s\n' "$pair" "$pc" >&2 ;; *) pass=$((pass + 1)) ;; esac
done

# a second clone and a worktree of the same origin share one state folder
mkrepo "$TMP/work/clone2" "https://github.com/octo/hello.git"
eq "aw two clones share the state" "$("$AW" --cwd "$R" --get state)" "$("$AW" --cwd "$TMP/work/clone2" --get state)"
git -C "$R" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
git -C "$R" worktree add -q "$TMP/work/wt" -b wt-branch
eq "aw worktree shares the state" "$("$AW" --cwd "$R" --get state)" "$("$AW" --cwd "$TMP/work/wt" --get state)"

# ---------------------------------------------------------------- guard
AN="agentic-workflow:jira-analyst"
P="mcp__claude_ai_Atlassian_Rovo__"
CH="mcp__claude-in-chrome__"
ORIGIN='"https://stg.example.com"'

gin() { # agent_type|- tool_name cwd [tool_input-json]
  at=""
  [ "$1" = "-" ] || at="\"agent_id\":\"a1\",\"agent_type\":\"$1\","
  ti="${4:-}"; [ -n "$ti" ] || ti='{}'
  printf '{"session_id":"s","transcript_path":"/t","cwd":"%s","permission_mode":"default",%s"hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s,"tool_use_id":"u"}' "$3" "$at" "$2" "$ti"
}
dec() { # raw hook input -> allow | deny | none
  out="$(printf '%s' "$1" | (cd / && "$GUARD"))"
  if [ -z "$out" ]; then echo none; else printf '%s' "$out" | sed -n 's/.*"permissionDecision":"\([a-z]*\)".*/\1/p'; fi
}
reason() { printf '%s' "$1" | (cd / && "$GUARD") | sed -n 's/.*"permissionDecisionReason":"\([^"]*\)".*/\1/p'; }

write_team() { # repo writeMode origins-json-list
  mkdir -p "$1/.claude"
  printf '{\n  "jira": {\n    "writeMode": "%s",\n    "investigation": {\n      "code": true,\n      "browser": { "appUrl": "https://stg.example.com", "allowedOrigins": [%s] }\n    }\n  }\n}\n' "$2" "$3" > "$1/.claude/agentic-workflow.json"
}
write_local() { # repo mcpPrefix acceptedWriteMode browserPrefix acceptedOrigins-json-list
  f="$("$AW" --cwd "$1" --get local)"
  mkdir -p "$(dirname "$f")"
  printf '{\n  "mcpPrefix": "%s",\n  "acceptedWriteMode": "%s",\n  "browserPrefix": "%s",\n  "acceptedOrigins": [%s]\n}\n' "$2" "$3" "$4" "$5" > "$f"
}

G="$TMP/work/g repo"
mkrepo "$G" "https://github.com/octo/guarded.git"

# write modes, accepted equal to configured
write_team "$G" labels ""; write_local "$G" "$P" labels "" ""
eq "labels: edit allowed" allow "$(dec "$(gin $AN ${P}editJiraIssue "$G")")"
eq "labels: comment denied" deny "$(dec "$(gin $AN ${P}addCommentToJiraIssue "$G")")"
eq "labels: transition denied" deny "$(dec "$(gin $AN ${P}transitionJiraIssue "$G")")"
write_team "$G" labels+comments ""; write_local "$G" "$P" labels+comments "" ""
eq "labels+comments: comment allowed" allow "$(dec "$(gin $AN ${P}addCommentToJiraIssue "$G")")"
eq "labels+comments: transition denied" deny "$(dec "$(gin $AN ${P}transitionJiraIssue "$G")")"
write_team "$G" labels+comments+transition ""; write_local "$G" "$P" labels+comments+transition "" ""
eq "full: transition allowed" allow "$(dec "$(gin $AN ${P}transitionJiraIssue "$G")")"
write_team "$G" none ""; write_local "$G" "$P" none "" ""
eq "none: edit denied" deny "$(dec "$(gin $AN ${P}editJiraIssue "$G")")"
eq "none: comment denied" deny "$(dec "$(gin $AN ${P}addCommentToJiraIssue "$G")")"

# the team file may narrow but never widen what the user accepted
write_team "$G" labels+comments+transition ""; write_local "$G" "$P" labels+comments "" ""
eq "ceiling: edit allowed" allow "$(dec "$(gin $AN ${P}editJiraIssue "$G")")"
eq "ceiling: comment allowed" allow "$(dec "$(gin $AN ${P}addCommentToJiraIssue "$G")")"
eq "ceiling: transition denied" deny "$(dec "$(gin $AN ${P}transitionJiraIssue "$G")")"
contains "ceiling: the reason says to run setup" "setup --reconfigure jira" "$(reason "$(gin $AN ${P}transitionJiraIssue "$G")")"
write_team "$G" labels ""; write_local "$G" "$P" labels+comments+transition "" ""
eq "narrowed config wins: comment denied" deny "$(dec "$(gin $AN ${P}addCommentToJiraIssue "$G")")"
write_team "$G" labels ""; write_local "$G" "$P" "" "" ""
eq "missing accepted mode: edit denied" deny "$(dec "$(gin $AN ${P}editJiraIssue "$G")")"

# connector binding
write_team "$G" labels+comments+transition ""; write_local "$G" "$P" labels+comments+transition "" ""
eq "other connector prefix denied" deny "$(dec "$(gin $AN mcp__claude_ai_Atlassian_Rovo_2__editJiraIssue "$G")")"
eq "plugin server prefix denied when bound to the connector" deny "$(dec "$(gin $AN mcp__plugin_agentic-workflow_atlassian__editJiraIssue "$G")")"

# only the analyst is judged
eq "main thread: no opinion" none "$(dec "$(gin - ${P}editJiraIssue "$G")")"
eq "another plugin agent: no opinion" none "$(dec "$(gin agentic-workflow:implementer ${P}editJiraIssue "$G")")"
eq "same name from another plugin: no opinion" none "$(dec "$(gin other:jira-analyst ${P}editJiraIssue "$G")")"
eq "bare agent name: no opinion" none "$(dec "$(gin jira-analyst ${P}editJiraIssue "$G")")"
eq "empty input: no opinion" none "$(dec "")"
eq "tools the hook does not own: no opinion" none "$(dec "$(gin $AN ${P}getJiraIssue "$G")")"

# decoy keys inside tool_input, and a different key order
eq "decoy agent_type in tool_input of the main thread" none "$(dec "$(gin - ${P}editJiraIssue "$G" '{"agent_type":"agentic-workflow:jira-analyst","x":{"agent_type":"agentic-workflow:jira-analyst"}}')")"
eq "decoy cwd in tool_input does not move the repository" allow "$(dec "$(gin $AN ${P}editJiraIssue "$G" '{"cwd":"/nonexistent","labels":["a"]}')")"
write_team "$G" labels ""; write_local "$G" "$P" labels "" ""
eq "decoy tool_name cannot widen" deny "$(dec "$(gin $AN ${P}transitionJiraIssue "$G" '{"tool_name":"'${P}'editJiraIssue"}')")"
eq "decoy tool_name does not change the real tool" allow "$(dec "$(gin $AN ${P}editJiraIssue "$G" '{"tool_name":"'${P}'transitionJiraIssue"}')")"
eq "text with quotes and braces inside tool_input" allow "$(dec "$(gin $AN ${P}editJiraIssue "$G" '{"note":"a \"quoted\" } { , :\" cwd","b":[1,{"c":"d"}]}')")"
RAW='{"tool_input":{"agent_type":"x"},"tool_name":"'${P}'editJiraIssue","hook_event_name":"PreToolUse","agent_type":"agentic-workflow:jira-analyst","cwd":"'$G'"}'
eq "another key order" allow "$(dec "$RAW")"
eq "escaped cwd is unreadable" deny "$(dec '{"cwd":"/tmp/a/b","agent_type":"'$AN'","tool_name":"'${P}'editJiraIssue","tool_input":{}}')"
eq "no cwd" deny "$(dec '{"agent_type":"'$AN'","tool_name":"'${P}'editJiraIssue","tool_input":{}}')"
eq "cwd that is not a repository" deny "$(dec "$(gin $AN ${P}editJiraIssue "$TMP/work/plain")")"
eq "multi-line input" allow "$(dec "$(gin $AN ${P}editJiraIssue "$G" | sed 's/,/,\
/g')")"

# configuration modes
rm -f "$G/.claude/agentic-workflow.json"
eq "mode none: denied" deny "$(dec "$(gin $AN ${P}editJiraIssue "$G")")"
write_team "$G" labels ""; PERS="$("$AW" --cwd "$G" --get personal_config)"; mkdir -p "$(dirname "$PERS")"; cp "$G/.claude/agentic-workflow.json" "$PERS"
eq "mode conflict: denied" deny "$(dec "$(gin $AN ${P}editJiraIssue "$G")")"
rm "$G/.claude/agentic-workflow.json"
eq "mode personal: allowed" allow "$(dec "$(gin $AN ${P}editJiraIssue "$G")")"
rm "$PERS"; write_team "$G" labels ""
rm -f "$("$AW" --cwd "$G" --get local)"
eq "no local.json: denied" deny "$(dec "$(gin $AN ${P}editJiraIssue "$G")")"

# browser
write_team "$G" none "$ORIGIN"; write_local "$G" "$P" none "$CH" "$ORIGIN"
for t in tabs_context_mcp tabs_create_mcp tabs_close_mcp navigate get_page_text read_page find computer; do
  eq "browser on: $t allowed" allow "$(dec "$(gin $AN ${CH}$t "$G")")"
done
for t in javascript_tool form_input file_upload shortcuts_execute upload_image resize_window; do
  eq "browser on: $t denied" deny "$(dec "$(gin $AN ${CH}$t "$G")")"
done
write_team "$G" none "$ORIGIN,\"https://other.example.com\""; write_local "$G" "$P" none "$CH" "$ORIGIN"
eq "browser: an extra, unaccepted origin does not switch it off (the overlap counts)" allow "$(dec "$(gin $AN ${CH}navigate "$G")")"
write_team "$G" none '"https://other.example.com"'; write_local "$G" "$P" none "$CH" "$ORIGIN"
eq "browser: no configured origin is accepted means off" deny "$(dec "$(gin $AN ${CH}navigate "$G")")"
write_team "$G" none "$ORIGIN,\"https://other.example.com\""; write_local "$G" "$P" none "$CH" "$ORIGIN"
write_local "$G" "$P" none "$CH" "$ORIGIN,\"https://other.example.com\",\"https://third.example.com\""
eq "browser: accepted superset keeps it on" allow "$(dec "$(gin $AN ${CH}navigate "$G")")"
write_team "$G" none "$ORIGIN"; write_local "$G" "$P" none "" "$ORIGIN"
eq "browser: no browserPrefix means off" deny "$(dec "$(gin $AN ${CH}navigate "$G")")"
write_team "$G" none ""; write_local "$G" "$P" none "$CH" "$ORIGIN"
eq "browser: no allowedOrigins means off" deny "$(dec "$(gin $AN ${CH}navigate "$G")")"
write_team "$G" none "$ORIGIN"; write_local "$G" "$P" none "$CH" ""
eq "browser: nothing accepted means off" deny "$(dec "$(gin $AN ${CH}navigate "$G")")"
write_local "$G" "$P" none "$CH" "$ORIGIN"
eq "browser: another agent gets no opinion" none "$(dec "$(gin agentic-workflow:implementer ${CH}javascript_tool "$G")")"
eq "browser: main thread gets no opinion" none "$(dec "$(gin - ${CH}javascript_tool "$G")")"

# the answer is one line of valid-looking JSON
out="$(gin $AN ${P}editJiraIssue "$G" | (cd / && "$GUARD"))"
case "$out" in '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"'*'"}}') pass=$((pass + 1)) ;; *) fail=$((fail + 1)); printf 'FAIL: output shape [%s]\n' "$out" >&2 ;; esac
eq "answer is a single line" 1 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"

# permissions of the shipped scripts
for f in bin/aw-paths bin/gh-as bin/wait-gh-login bin/wait-mcp hooks/guard; do
  if [ -x "$ROOT/$f" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL: %s is not executable\n' "$f" >&2; fi
done
# the hook matcher must name exactly the Atlassian prefixes the analyst may use
for p in plugin_agentic-workflow_atlassian claude_ai_Atlassian_Rovo claude_ai_Atlassian_Rovo_2; do
  grep -q "mcp__${p}__" "$ROOT/agents/jira-analyst.md" && grep -q "$p" "$ROOT/hooks/hooks.json" && pass=$((pass + 1)) || { fail=$((fail + 1)); printf 'FAIL: prefix %s missing from jira-analyst tools or hooks.json\n' "$p" >&2; }
done

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
