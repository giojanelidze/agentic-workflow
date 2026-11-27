#!/bin/sh
# Shell tests for bin/aw-paths, hooks/guard, bin/gh-as, bin/kiro-permissions, bin/kiro-install, bin/jira-attachment, bin/media-prep and bin/aw-decisions. No network, no claude CLI, no real HOME,
# no real keychain (fake security/curl/ffmpeg).
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

# --tool kiro: its own base folder, the same team file in the repository, no legacy folder
eq "aw kiro state path" "$HOME/.kiro/agentic-workflow/state/github.com/octo/hello" "$("$AW" --tool kiro --cwd "$R" --get state)"
eq "aw kiro local path" "$HOME/.kiro/agentic-workflow/repos/github.com/octo/hello/local.json" "$("$AW" --tool kiro --cwd "$R" --get local)"
eq "aw kiro personal config path" "$HOME/.kiro/agentic-workflow/repos/github.com/octo/hello/config.json" "$("$AW" --tool kiro --cwd "$R" --get personal_config)"
eq "aw kiro team config is the same file" "$("$AW" --cwd "$R" --get team_config)" "$("$AW" --tool kiro --cwd "$R" --get team_config)"
eq "aw kiro legacy stays empty although the folder exists" "" "$("$AW" --tool kiro --cwd "$R" --get legacy)"
eq "aw claude legacy is still found" "$(cd "$R" && pwd -P)/.agentic-workflow" "$("$AW" --tool claude --cwd "$R" --get legacy)"
eq "aw explicit claude host is the default" "$("$AW" --cwd "$R" --get state)" "$("$AW" --tool claude --cwd "$R" --get state)"
eq "aw kiro and claude never share the state" "different" "$([ "$("$AW" --tool kiro --cwd "$R" --get state)" = "$("$AW" --tool claude --cwd "$R" --get state)" ] && echo same || echo different)"
eq "aw kiro and claude never share local.json" "different" "$([ "$("$AW" --tool kiro --cwd "$R" --get local)" = "$("$AW" --tool claude --cwd "$R" --get local)" ] && echo same || echo different)"
eq "aw unknown host" 2 "$("$AW" --tool nope --cwd "$R" >/dev/null 2>&1; echo $?)"
eq "aw host without a value" 2 "$("$AW" --tool >/dev/null 2>&1; echo $?)"
KP="$("$AW" --tool kiro --cwd "$R" --get personal_config)"
mkdir -p "$(dirname "$KP")"; echo '{}' > "$KP"
eq "aw kiro mode personal" personal "$("$AW" --tool kiro --cwd "$R" --get mode)"
eq "aw a kiro personal config does not change the claude mode" none "$("$AW" --tool claude --cwd "$R" --get mode)"
echo '{}' > "$R/.claude/agentic-workflow.json"
eq "aw kiro mode conflict" conflict "$("$AW" --tool kiro --cwd "$R" --get mode)"
eq "aw the claude side sees the shared team file alone" team "$("$AW" --tool claude --cwd "$R" --get mode)"
rm "$KP" "$R/.claude/agentic-workflow.json"

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
write_team "$G" labels ""; write_local "$G" "$P" labels "" ""
out="$(gin $AN ${P}editJiraIssue "$G" | (cd / && "$GUARD" --tool claude))"
eq "an explicit --tool claude answers like the default" "$(gin $AN ${P}editJiraIssue "$G" | (cd / && "$GUARD"))" "$out"
case "$out" in *'"permissionDecision":"allow"'*) pass=$((pass + 1)) ;; *) fail=$((fail + 1)); printf 'FAIL: --tool claude must allow an edit in labels mode [%s]\n' "$out" >&2 ;; esac

# ---------------------------------------------------------------- guard on Kiro (--tool kiro)
# Kiro names no agent and a global hook fires for every caller, so the guard never answers "allow": it
# stays silent inside the accepted mode and blocks (exit 2, reason on stderr) everywhere else.
KSRV="agentic-workflow-atlassian"
KP="${KSRV}::"
KT="mcp_agentic_workflow_atlassian_"
kin() { # tool_name cwd [tool_input-json]
  ti="${3:-}"; [ -n "$ti" ] || ti='{}'
  printf '{"session_id":"sess_x","hook_event_name":"PreToolUse","cwd":"%s","tool_name":"%s","tool_input":%s}' "$2" "$1" "$ti"
}
kdec() { # raw hook input -> none (exit 0, silent) | block (exit 2, stderr only) | other:<rc>:<stdout>
  out="$(printf '%s' "$1" | (cd / && "$GUARD" --tool kiro) 2>"$TMP/kerr")"; rc=$?
  if [ "$rc" = 2 ] && [ -z "$out" ] && [ -s "$TMP/kerr" ]; then echo block
  elif [ "$rc" = 0 ] && [ -z "$out" ] && [ ! -s "$TMP/kerr" ]; then echo none
  else echo "other:$rc:$out"; fi
}
kreason() { printf '%s' "$1" | (cd / && "$GUARD" --tool kiro) 2>&1 >/dev/null; }
write_klocal() { # repo mcpPrefix acceptedWriteMode
  f="$("$AW" --tool kiro --cwd "$1" --get local)"
  mkdir -p "$(dirname "$f")"
  printf '{\n  "mcpPrefix": "%s",\n  "acceptedWriteMode": "%s"\n}\n' "$2" "$3" > "$f"
}
KR="$TMP/work/k repo"
mkrepo "$KR" "https://github.com/octo/kguarded.git"

# the write-mode matrix, accepted equal to configured: silent when the mode reaches the tool, a block otherwise
write_team "$KR" labels ""; write_klocal "$KR" "$KP" labels
eq "kiro labels: edit is silent" none "$(kdec "$(kin ${KT}editjiraissue "$KR")")"
eq "kiro labels: comment blocked" block "$(kdec "$(kin ${KT}addcommenttojiraissue "$KR")")"
eq "kiro labels: transition blocked" block "$(kdec "$(kin ${KT}transitionjiraissue "$KR")")"
write_team "$KR" labels+comments ""; write_klocal "$KR" "$KP" labels+comments
eq "kiro labels+comments: comment is silent" none "$(kdec "$(kin ${KT}addcommenttojiraissue "$KR")")"
eq "kiro labels+comments: transition blocked" block "$(kdec "$(kin ${KT}transitionjiraissue "$KR")")"
write_team "$KR" labels+comments+transition ""; write_klocal "$KR" "$KP" labels+comments+transition
eq "kiro full: edit is silent" none "$(kdec "$(kin ${KT}editjiraissue "$KR")")"
eq "kiro full: comment is silent" none "$(kdec "$(kin ${KT}addcommenttojiraissue "$KR")")"
eq "kiro full: transition is silent" none "$(kdec "$(kin ${KT}transitionjiraissue "$KR")")"
write_team "$KR" none ""; write_klocal "$KR" "$KP" none
eq "kiro none: edit blocked" block "$(kdec "$(kin ${KT}editjiraissue "$KR")")"
eq "kiro none: comment blocked" block "$(kdec "$(kin ${KT}addcommenttojiraissue "$KR")")"

# the accepted ceiling: a config that grew through a pull never widens what the user accepted
write_team "$KR" labels+comments+transition ""; write_klocal "$KR" "$KP" labels
eq "kiro ceiling: edit is silent" none "$(kdec "$(kin ${KT}editjiraissue "$KR")")"
eq "kiro ceiling: comment blocked" block "$(kdec "$(kin ${KT}addcommenttojiraissue "$KR")")"
eq "kiro ceiling: transition blocked" block "$(kdec "$(kin ${KT}transitionjiraissue "$KR")")"
contains "kiro ceiling: the reason names the Kiro setup command" "/agentic-workflow-setup --reconfigure jira" "$(kreason "$(kin ${KT}addcommenttojiraissue "$KR")")"
contains "kiro ceiling: the reason says the accepted limit is lower" "wider write mode than you accepted" "$(kreason "$(kin ${KT}addcommenttojiraissue "$KR")")"
write_team "$KR" labels ""; write_klocal "$KR" "$KP" labels+comments+transition
eq "kiro narrowed config wins: comment blocked" block "$(kdec "$(kin ${KT}addcommenttojiraissue "$KR")")"
write_team "$KR" labels+comments+transition ""; write_klocal "$KR" "$KP" ""
eq "kiro missing accepted mode: edit blocked" block "$(kdec "$(kin ${KT}editjiraissue "$KR")")"

# the server the repository is bound to
write_team "$KR" labels+comments+transition ""; write_klocal "$KR" "other-server::" labels+comments+transition
eq "kiro another server: edit blocked" block "$(kdec "$(kin ${KT}editjiraissue "$KR")")"
write_klocal "$KR" "mcp__claude_ai_Atlassian_Rovo__" labels+comments+transition
eq "kiro a Claude-style prefix is not a Kiro binding: blocked" block "$(kdec "$(kin ${KT}editjiraissue "$KR")")"
write_klocal "$KR" "Agentic Workflow-Atlassian::" labels+comments+transition
eq "kiro the server name is folded like Kiro folds it" none "$(kdec "$(kin ${KT}editjiraissue "$KR")")"
write_klocal "$KR" "$KP" labels+comments+transition

# a repository that is not set up, a conflict, a missing personal file: all blocked, never silent
KN="$TMP/work/k none"; mkrepo "$KN" "https://github.com/octo/knone.git"
eq "kiro mode none: blocked" block "$(kdec "$(kin ${KT}editjiraissue "$KN")")"
KC="$TMP/work/k conflict"; mkrepo "$KC" "https://github.com/octo/kconflict.git"
write_team "$KC" labels ""; write_klocal "$KC" "$KP" labels
kcfg="$("$AW" --tool kiro --cwd "$KC" --get personal_config)"; mkdir -p "$(dirname "$kcfg")"; echo '{}' > "$kcfg"
eq "kiro mode conflict: blocked" block "$(kdec "$(kin ${KT}editjiraissue "$KC")")"
KL="$TMP/work/k nolocal"; mkrepo "$KL" "https://github.com/octo/knolocal.git"; write_team "$KL" labels ""
eq "kiro no local.json: blocked" block "$(kdec "$(kin ${KT}editjiraissue "$KL")")"
eq "kiro the Claude personal values are not read on Kiro" block "$(write_local "$KL" "$P" labels "" ""; kdec "$(kin ${KT}editjiraissue "$KL")")"
eq "kiro cwd that is not a repository: blocked" block "$(kdec "$(kin ${KT}editjiraissue "$TMP/work/plain")")"
eq "kiro no cwd: blocked" block "$(kdec '{"hook_event_name":"PreToolUse","tool_name":"'"${KT}"'editjiraissue","tool_input":{}}')"
eq "kiro empty input: blocked" block "$(kdec '')"
eq "kiro no tool name: blocked" block "$(kdec "{\"cwd\":\"$KR\",\"tool_input\":{}}")"
ESC='{"cwd":"/tmp/a\"b","tool_name":"'"${KT}"'editjiraissue","tool_input":{}}'
eq "kiro escaped cwd is unreadable: blocked" block "$(kdec "$ESC")"
contains "kiro escaped cwd: the reason" "could not be read safely" "$(kreason "$ESC")"

# only the three write tools are judged; everything else gets no opinion, whether or not the repository is set up
eq "kiro a read tool: no opinion" none "$(kdec "$(kin ${KT}getjiraissue "$KR")")"
eq "kiro a read tool in an unset repository: no opinion" none "$(kdec "$(kin ${KT}getjiraissue "$KN")")"
eq "kiro the shell tool: no opinion" none "$(kdec "$(kin execute_bash "$KN")")"
eq "kiro a Claude-style tool name: no opinion" none "$(kdec "$(kin mcp__claude_ai_Atlassian_Rovo__editJiraIssue "$KN")")"
eq "kiro a browser tool: no opinion" none "$(kdec "$(kin mcp__claude-in-chrome__navigate "$KN")")"
eq "kiro the tool id is judged as Kiro writes it (lower case)" none "$(kdec "$(kin ${KT}editJiraIssue "$KN")")"

# the agent name in a Claude-shaped input changes nothing: Kiro does not use it
eq "kiro ignores agent_type" none "$(kdec "$(gin $AN ${KT}editjiraissue "$KR")")"
eq "kiro the main thread is judged like any caller" block "$(write_klocal "$KR" "$KP" none; kdec "$(gin - ${KT}editjiraissue "$KR")")"
write_klocal "$KR" "$KP" labels+comments+transition

# decoy keys inside tool_input never move the decision
eq "kiro decoy cwd in tool_input does not move the repository" none "$(kdec "$(kin ${KT}editjiraissue "$KR" '{"cwd":"/nonexistent"}')")"
eq "kiro decoy tool_name in tool_input cannot silence a write tool" block "$(write_klocal "$KR" "$KP" none; kdec "$(kin ${KT}editjiraissue "$KR" '{"tool_name":"mcp_x_getjiraissue"}')")"
write_klocal "$KR" "$KP" labels+comments+transition
eq "kiro decoy tool_name in tool_input cannot make a read tool a write tool" none "$(kdec "$(kin ${KT}getjiraissue "$KR" '{"tool_name":"'"${KT}"'transitionjiraissue"}')")"
eq "kiro text with quotes and braces inside tool_input" none "$(kdec "$(kin ${KT}editjiraissue "$KR" '{"text":"a \" } { , \"cwd\": \"/x\""}')")"
eq "kiro multi-line input" none "$(kdec "$(printf '{\n"cwd": "%s",\n"hook_event_name": "PreToolUse",\n"tool_name": "%seditjiraissue",\n"tool_input": {}\n}\n' "$KR" "$KT")")"

# an environment that breaks the guard (no awk, sed or tr on PATH) blocks the call instead of letting it through
write_team "$KR" labels+comments+transition ""; write_klocal "$KR" "$KP" labels+comments+transition
eq "kiro a broken environment blocks (exit 2)" 2 "$(printf '%s' "$(kin ${KT}editjiraissue "$KR")" | (cd / && env PATH=/nonexistent "$GUARD" --tool kiro >/dev/null 2>&1); echo $?)"

# it never prints an allow: not in any mode, for any of the three tools
for m in labels labels+comments labels+comments+transition; do
  write_team "$KR" "$m" ""; write_klocal "$KR" "$KP" "$m"
  for t in editjiraissue addcommenttojiraissue transitionjiraissue; do
    o="$(printf '%s' "$(kin ${KT}$t "$KR")" | (cd / && "$GUARD" --tool kiro) 2>/dev/null)"
    case "$o" in *allow*) fail=$((fail + 1)); printf 'FAIL: kiro printed an allow for %s in %s\n' "$t" "$m" >&2 ;; *) pass=$((pass + 1)) ;; esac
  done
done

# usage
eq "guard unknown host" 2 "$(printf '' | "$GUARD" --tool nope >/dev/null 2>&1; echo $?)"
eq "guard unknown option" 2 "$(printf '' | "$GUARD" --bogus >/dev/null 2>&1; echo $?)"
eq "guard --marker needs --tool kiro" 2 "$(printf '' | "$GUARD" --marker >/dev/null 2>&1; echo $?)"
eq "guard --check-alive needs --tool kiro" 2 "$("$GUARD" --check-alive >/dev/null 2>&1; echo $?)"
eq "guard --marker and --check-alive together" 2 "$("$GUARD" --tool kiro --marker --check-alive >/dev/null 2>&1 </dev/null; echo $?)"

# the SessionStart marker and the check the start preflight runs
KM="$HOME/.kiro/agentic-workflow/hooks-alive"
eq "kiro marker: hooks are not alive before any session" off "$(KIRO_SESSION_ID=sess_t1 "$GUARD" --tool kiro --check-alive)"
mout="$(printf '{"hook_event_name":"SessionStart"}' | KIRO_SESSION_ID=sess_t1 "$GUARD" --tool kiro --marker 2>&1)"; mrc=$?
eq "kiro marker: SessionStart exits 0" 0 "$mrc"
eq "kiro marker: SessionStart prints nothing" "" "$mout"
eq "kiro marker: the file is named after the session" yes "$([ -f "$KM/sess_t1" ] && echo yes || echo no)"
eq "kiro marker: this session is alive" alive "$(KIRO_SESSION_ID=sess_t1 "$GUARD" --tool kiro --check-alive)"
eq "kiro marker: another session is not" off "$(KIRO_SESSION_ID=sess_t2 "$GUARD" --tool kiro --check-alive)"
eq "kiro marker: no session id is off" off "$(env -u KIRO_SESSION_ID "$GUARD" --tool kiro --check-alive)"
eq "kiro marker: an unsafe session id is off" off "$(KIRO_SESSION_ID='../x' "$GUARD" --tool kiro --check-alive)"
printf '{}' | KIRO_SESSION_ID='../evil' "$GUARD" --tool kiro --marker >/dev/null 2>&1
eq "kiro marker: an unsafe session id creates no file" no "$([ -e "$HOME/.kiro/agentic-workflow/evil" ] || [ -e "$KM/../evil" ] && echo yes || echo no)"
touch -t 200001010000 "$KM/sess_old"
printf '{}' | KIRO_SESSION_ID=sess_t3 "$GUARD" --tool kiro --marker >/dev/null 2>&1
eq "kiro marker: a week-old marker is pruned" no "$([ -e "$KM/sess_old" ] && echo yes || echo no)"
eq "kiro marker: a fresh marker stays" yes "$([ -f "$KM/sess_t1" ] && echo yes || echo no)"

# ---------------------------------------------------------------- gh-as (fake gh)
GA="$ROOT/bin/gh-as"
GFB="$TMP/ghfake"; mkdir -p "$GFB"
cat > "$GFB/gh" <<'FAKE_GH'
#!/bin/sh
# a fake gh: `auth token` answers for every account but "ghost"; any other call shows what gh-as handed to it
if [ "$1 $2" = "auth token" ]; then
  shift 2; h=""; u=""
  while [ $# -gt 0 ]; do case "$1" in --hostname) h="$2"; shift 2 ;; --user) u="$2"; shift 2 ;; *) shift ;; esac; done
  [ "$u" = ghost ] && exit 1
  printf 'tok-%s-%s\n' "$u" "$h"; exit 0
fi
printf 'ARGS=%s|HOST=%s|TOKEN=%s|ETOKEN=%s\n' "$*" "${GH_HOST:-}" "${GH_TOKEN:-}" "${GH_ENTERPRISE_TOKEN:-}"
FAKE_GH
chmod +x "$GFB/gh"
gha() { PATH="$GFB:$PATH" "$GA" "$@"; }
eq "gha --host: the token of that account, for github.com" "ARGS=repo view o/r|HOST=github.com|TOKEN=tok-octo-github.com|ETOKEN=" "$(gha --account octo --host github.com repo view o/r)"
eq "gha --hostname is the same spelling" "ARGS=repo view o/r|HOST=github.com|TOKEN=tok-octo-github.com|ETOKEN=" "$(gha --account octo --hostname github.com repo view o/r)"
eq "gha a self-hosted host gets the enterprise token" "ARGS=pr list|HOST=git.example.com|TOKEN=|ETOKEN=tok-octo-git.example.com" "$(gha --account octo --hostname git.example.com pr list)"
eq "gha an account without a login" 3 "$(gha --account ghost --hostname github.com repo view >/dev/null 2>&1; echo $?)"
eq "gha --hostname needs a value" 2 "$(gha --account octo --hostname >/dev/null 2>&1; echo $?)"
eq "gha --host needs a value" 2 "$(gha --account octo --host >/dev/null 2>&1; echo $?)"
eq "gha without gh arguments" 2 "$(gha --account octo --hostname github.com >/dev/null 2>&1; echo $?)"
eq "gha without an account" 2 "$(gha --hostname github.com repo view >/dev/null 2>&1; echo $?)"
eq "gha the token never reaches the output of a failure" "" "$(gha --account ghost --hostname github.com repo view 2>&1 | grep -c 'tok-' | sed 's/^0$//')"

# ---------------------------------------------------------------- kiro-permissions
KPM="$ROOT/bin/kiro-permissions"
KPL="$TMP/kplug"; mkdir -p "$KPL/kiro/agents"
touch "$KPL/kiro/agents/agentic-workflow.md" "$KPL/kiro/agents/agentic-workflow-test-runner.md"
kp() { sub="$1"; shift; "$KPM" "$sub" --plugin-dir "$KPL" "$@"; }
printed="$(kp print --github octo@github.com)"
contains "kp the block starts with a marker" "# >>> agentic-workflow" "$printed"
contains "kp the block ends with a marker" "# <<< agentic-workflow" "$printed"
contains "kp aw-paths is an exact command, no star" '- "~/.kiro/agentic-workflow-plugin/bin/aw-paths --tool kiro"' "$printed"
contains "kp aw-decisions" '- "~/.kiro/agentic-workflow-plugin/bin/aw-decisions *"' "$printed"
contains "kp the alive check is an exact command" '- "~/.kiro/agentic-workflow-plugin/hooks/guard --tool kiro --check-alive"' "$printed"
contains "kp read-only gh-as with the account and the host" '- "~/.kiro/agentic-workflow-plugin/bin/gh-as --account octo --hostname github.com repo view *"' "$printed"
contains "kp gh-as pr checks" '--account octo --hostname github.com pr checks *"' "$printed"
contains "kp an Atlassian read tool as server/tool" '- "agentic-workflow-atlassian/getJiraIssue"' "$printed"
contains "kp the plugin folder is read by the path it was given" "- \"$KPL/**\"" "$printed"
contains "kp the data tree is readable" '- "~/.kiro/agentic-workflow/**"' "$printed"
contains "kp subagent names come from kiro/agents" '- "agentic-workflow-test-runner"' "$printed"
for bad in deny editJiraIssue addCommentToJiraIssue transitionJiraIssue claude-in-chrome "jira-attachment login" repos local.json config.json; do
  case "$printed" in *"$bad"*) fail=$((fail + 1)); printf 'FAIL: kiro-permissions printed [%s]\n' "$bad" >&2 ;; *) pass=$((pass + 1)) ;; esac
done
case "$printed" in *jira-attachment*|*media-prep*) fail=$((fail + 1)); echo "FAIL: kp pictures rules without --pictures" >&2 ;; *) pass=$((pass + 1)) ;; esac
pics="$(kp print --pictures)"
contains "kp --pictures adds jira-attachment get" 'bin/jira-attachment get *"' "$pics"
contains "kp --pictures adds jira-attachment check" 'bin/jira-attachment check *"' "$pics"
contains "kp --pictures adds media-prep" 'bin/media-prep *"' "$pics"
case "$pics" in *"jira-attachment login"*|*"jira-attachment *"*) fail=$((fail + 1)); echo "FAIL: kp must never allow jira-attachment login" >&2 ;; *) pass=$((pass + 1)) ;; esac
eq "kp every rule is an allow rule" "$(printf '%s\n' "$printed" | grep -c '^  - capability:')" "$(printf '%s\n' "$printed" | grep -c '^    effect: allow$')"
eq "kp fs_write covers exactly state/** and memory/**" "- \"~/.kiro/agentic-workflow/state/**\"|- \"~/.kiro/agentic-workflow/memory/**\"" "$(printf '%s\n' "$printed" | awk '/capability:/ { w = ($0 ~ /fs_write/) } w && /^      - / { sub(/^ +/, ""); a = a (a ? "|" : "") $0 } END { print a }')"
eq "kp every shell rule runs through the plugin link" 0 "$(printf '%s\n' "$printed" | awk '/capability:/ { s = ($0 ~ /shell/) } s && /^      - / && $0 !~ /"~\/.kiro\/agentic-workflow-plugin\// { n++ } END { print n + 0 }')"
eq "kp two accounts give two sets" 8 "$(kp print --github a@github.com --github b@git.example.com | grep -c -- '--account')"
eq "kp a bad --github is refused" 2 "$(kp print --github 'a b@github.com' >/dev/null 2>&1; echo $?)"
eq "kp --github without a host is refused" 2 "$(kp print --github octo >/dev/null 2>&1; echo $?)"
eq "kp an unsafe server name is refused" 2 "$(kp print --server 'x"y' >/dev/null 2>&1; echo $?)"
eq "kp no subcommand" 2 "$("$KPM" >/dev/null 2>&1; echo $?)"
eq "kp unknown option" 2 "$(kp apply --bogus >/dev/null 2>&1; echo $?)"
eq "kp a plugin folder without kiro/agents" 4 "$("$KPM" print --plugin-dir "$TMP/work" >/dev/null 2>&1; echo $?)"

PD="$TMP/perm"; mkdir -p "$PD"
# a new file
PF="$PD/new/permissions.yaml"
kp apply --file "$PF" >/dev/null
eq "kp apply creates the file with rules: first" "rules:" "$(sed -n 1p "$PF")"
eq "kp apply writes the begin marker once" 1 "$(grep -c '# >>> agentic-workflow' "$PF")"
eq "kp apply writes the end marker once" 1 "$(grep -c '# <<< agentic-workflow' "$PF")"
kp remove --file "$PF" >/dev/null
eq "kp remove deletes a file the script created" no "$([ -e "$PF" ] && echo yes || echo no)"
# a file with the usual two-space list
PF="$PD/two.yaml"
printf 'rules:\n  - capability: shell\n    effect: allow\n    match:\n      - git *\n' > "$PF"; cp "$PF" "$PD/two.orig"
kp apply --file "$PF" >/dev/null
contains "kp apply keeps the user's rules" "      - git *" "$(cat "$PF")"
eq "kp apply puts the block under rules: with the same indent" "  - capability: mcp" "$(sed -n 3p "$PF")"
eq "kp apply keeps a copy of the original once" yes "$(cmp -s "$PF.agentic-workflow.bak" "$PD/two.orig" && echo yes || echo no)"
cp "$PF" "$PD/two.after"
kp apply --file "$PF" >/dev/null
eq "kp apply is idempotent" yes "$(cmp -s "$PF" "$PD/two.after" && echo yes || echo no)"
kp apply --file "$PF" --github other@github.com >/dev/null
contains "kp apply replaces its own block" "--account other " "$(cat "$PF")"
eq "kp apply replaces, never duplicates" 1 "$(grep -c '# >>> agentic-workflow' "$PF")"
kp apply --file "$PF" --github third@git.example.com --pictures >/dev/null
contains "kp a second repository keeps the first account" "--account other --hostname github.com repo view" "$(cat "$PF")"
contains "kp a second repository adds its account" "--account third --hostname git.example.com repo view" "$(cat "$PF")"
contains "kp --pictures adds the picture rules" "bin/media-prep *" "$(cat "$PF")"
kp apply --file "$PF" --github third@git.example.com >/dev/null
contains "kp the picture rules stay when a later apply does not name them" "bin/media-prep *" "$(cat "$PF")"
kp apply --file "$PF" --no-pictures >/dev/null
case "$(cat "$PF")" in *media-prep*|*jira-attachment*) fail=$((fail + 1)); echo "FAIL: kp --no-pictures must take the picture rules out" >&2 ;; *) pass=$((pass + 1)) ;; esac
contains "kp --no-pictures keeps the accounts" "--account other --hostname github.com repo view" "$(cat "$PF")"
eq "kp --pictures with --no-pictures is a usage error" 2 "$(kp apply --file "$PF" --pictures --no-pictures >/dev/null 2>&1; echo $?)"
kp remove --file "$PF" >/dev/null
eq "kp remove restores the original file" yes "$(cmp -s "$PF" "$PD/two.orig" && echo yes || echo no)"
eq "kp remove without a block is a no-op" 0 "$(kp remove --file "$PF" >/dev/null 2>&1; echo $?)"
# a list without indentation
PF="$PD/zero.yaml"
printf 'rules:\n- capability: shell\n  effect: allow\n  match:\n  - "echo *"\n' > "$PF"
kp apply --file "$PF" >/dev/null
eq "kp apply follows a list without indentation" 1 "$(grep -c '^- capability: mcp$' "$PF")"
# a layout it will not edit
PF="$PD/flow.yaml"; printf 'rules: []\n' > "$PF"
eq "kp refuses rules: []" 3 "$(kp apply --file "$PF" >/dev/null 2>&1; echo $?)"
eq "kp leaves a refused file unchanged" "rules: []" "$(cat "$PF")"
contains "kp says what to add by hand" "by hand" "$(kp apply --file "$PF" 2>&1 >/dev/null)"
# a file without rules:
PF="$PD/norules.yaml"; printf 'version: 1\n' > "$PF"
kp apply --file "$PF" >/dev/null
eq "kp appends rules: to a file that has none" "version: 1|rules:" "$(sed -n 1,2p "$PF" | tr '\n' '|' | sed 's/|$//')"

# ---------------------------------------------------------------- kiro-install
KI_SRC="$TMP/work/i plug"
mkdir -p "$KI_SRC/bin" "$KI_SRC/hooks" "$KI_SRC/kiro/agents" "$KI_SRC/kiro/prompts" "$KI_SRC/kiro/hooks"
cp "$ROOT/bin/kiro-install" "$KI_SRC/bin/kiro-install"; chmod +x "$KI_SRC/bin/kiro-install"
printf '#!/bin/sh\nexit 0\n' > "$KI_SRC/hooks/guard"; chmod +x "$KI_SRC/hooks/guard"
printf -- '---\nname: agentic-workflow\n---\nbody\n' > "$KI_SRC/kiro/agents/agentic-workflow.md"
printf -- '---\nname: agentic-workflow-x\n---\nbody\n' > "$KI_SRC/kiro/agents/agentic-workflow-x.md"
printf 'Arguments: $ARGUMENTS\n' > "$KI_SRC/kiro/prompts/agentic-workflow-start.md"
printf '{"version":"v1","hooks":[]}\n' > "$KI_SRC/kiro/hooks/agentic-workflow.json"
KI="$KI_SRC/bin/kiro-install"
KFB="$TMP/kfakebin"; mkdir -p "$KFB"
# a fake kiro-cli: logs its arguments and keeps a global mcp.json like the real one
cat > "$KFB/kiro-cli" <<'FAKE_KIRO'
#!/bin/sh
echo "$*" >> "$KFAKE_LOG"
if [ "$1 $2" = "mcp add" ]; then
  mkdir -p "$HOME/.kiro/settings"
  printf '{"mcpServers":{"agentic-workflow-atlassian":{"url":"x"}}}\n' > "$HOME/.kiro/settings/mcp.json"
elif [ "$1 $2" = "mcp remove" ]; then
  rm -f "$HOME/.kiro/settings/mcp.json"
fi
exit 0
FAKE_KIRO
chmod +x "$KFB/kiro-cli"
KFAKE_LOG="$TMP/kiro-cli.log"; export KFAKE_LOG
KH="$TMP/khome"; mkdir -p "$KH"
ki() { HOME="$KH" PATH="$KFB:$PATH" "$KI" "$@" </dev/null; }
kiq() { ki "$@" >/dev/null 2>&1; echo $?; }
K="$KH/.kiro"

eq "ki install exits 0" 0 "$(kiq --yes)"
eq "ki the plugin link points to the checkout" "$(cd "$KI_SRC" && pwd -P)" "$(readlink "$K/agentic-workflow-plugin")"
eq "ki an agent is a link to the checkout file" "$(cd "$KI_SRC" && pwd -P)/kiro/agents/agentic-workflow-x.md" "$(readlink "$K/agents/agentic-workflow-x.md")"
eq "ki a prompt is a copy, not a link" yes "$([ -f "$K/prompts/agentic-workflow-start.md" ] && [ ! -L "$K/prompts/agentic-workflow-start.md" ] && cmp -s "$K/prompts/agentic-workflow-start.md" "$KI_SRC/kiro/prompts/agentic-workflow-start.md" && echo yes || echo no)"
eq "ki the hook is a copy, not a link" yes "$([ -f "$K/hooks/agentic-workflow.json" ] && [ ! -L "$K/hooks/agentic-workflow.json" ] && cmp -s "$K/hooks/agentic-workflow.json" "$KI_SRC/kiro/hooks/agentic-workflow.json" && echo yes || echo no)"
eq "ki the files it made are listed" 5 "$(wc -l < "$K/agentic-workflow/installed-files" | tr -d ' ')"
contains "ki the Atlassian server is added with the v2 address" "mcp add --name agentic-workflow-atlassian --url https://mcp.atlassian.com/v2/mcp --scope global" "$(cat "$KFAKE_LOG")"
eq "ki a second install exits 0" 0 "$(kiq --yes)"
eq "ki the server is added only once" 1 "$(grep -c 'mcp add' "$KFAKE_LOG")"
eq "ki --check passes after an install" 0 "$(kiq --check)"
printf 'edited\n' >> "$K/prompts/agentic-workflow-start.md"
eq "ki --check sees a changed copy" 1 "$(kiq --check)"
contains "ki --check names the changed copy" "changed: $K/prompts/agentic-workflow-start.md" "$(ki --check 2>&1)"
eq "ki an update overwrites a copy it made" 0 "$(kiq --yes)"
eq "ki the update restored the copy" yes "$(cmp -s "$K/prompts/agentic-workflow-start.md" "$KI_SRC/kiro/prompts/agentic-workflow-start.md" && echo yes || echo no)"
rm "$K/hooks/agentic-workflow.json"
eq "ki --check sees a missing hook" 1 "$(kiq --check)"
kiq --yes >/dev/null
eq "ki an install puts a missing hook back" 0 "$(kiq --check)"

# a file that is not ours is never overwritten
KH2="$TMP/khome2"; mkdir -p "$KH2/.kiro/prompts"; printf 'mine\n' > "$KH2/.kiro/prompts/agentic-workflow-start.md"
out2="$(HOME="$KH2" PATH="$KFB:$PATH" "$KI" --no-mcp </dev/null 2>&1)"; rc2=$?
eq "ki a foreign prompt: exit 1" 1 "$rc2"
eq "ki a foreign prompt is left alone" "mine" "$(cat "$KH2/.kiro/prompts/agentic-workflow-start.md")"
contains "ki a foreign prompt is reported" "was not installed by kiro-install" "$out2"
eq "ki the other items are still installed" yes "$([ -L "$KH2/.kiro/agents/agentic-workflow.md" ] && echo yes || echo no)"
KH3="$TMP/khome3"; mkdir -p "$KH3/.kiro/agents"; printf 'x\n' > "$KH3/.kiro/agents/agentic-workflow.md"
eq "ki a foreign agent file is refused" 1 "$(HOME="$KH3" PATH="$KFB:$PATH" "$KI" --no-mcp </dev/null >/dev/null 2>&1; echo $?)"
eq "ki a foreign agent file is left alone" "x" "$(cat "$KH3/.kiro/agents/agentic-workflow.md")"

# the server question: not without a yes, never with --no-mcp
: > "$KFAKE_LOG"
KH4="$TMP/khome4"; mkdir -p "$KH4"
HOME="$KH4" PATH="$KFB:$PATH" "$KI" </dev/null >/dev/null 2>&1
eq "ki without a terminal and without --yes the server is not added" "" "$(cat "$KFAKE_LOG")"
HOME="$KH4" PATH="$KFB:$PATH" "$KI" --no-mcp --yes </dev/null >/dev/null 2>&1
eq "ki --no-mcp never calls kiro-cli" "" "$(cat "$KFAKE_LOG")"

# another checkout takes the plugin link over
KI_SRC2="$TMP/work/i plug two"; cp -R "$KI_SRC" "$KI_SRC2"
HOME="$KH" PATH="$KFB:$PATH" "$KI_SRC2/bin/kiro-install" --no-mcp </dev/null >/dev/null 2>&1
eq "ki another checkout re-points the plugin link" "$(cd "$KI_SRC2" && pwd -P)" "$(readlink "$K/agentic-workflow-plugin")"

# refusals
eq "ki another KIRO_HOME is not supported" 3 "$(KIRO_HOME="$TMP/elsewhere" HOME="$KH" "$KI" --check >/dev/null 2>&1 </dev/null; echo $?)"
eq "ki the default KIRO_HOME is fine" 0 "$(KIRO_HOME="$KH4/.kiro" HOME="$KH4" PATH="$KFB:$PATH" "$KI" --no-mcp >/dev/null 2>&1 </dev/null; echo $?)"
mkdir -p "$TMP/nokiro/bin"; cp "$ROOT/bin/kiro-install" "$TMP/nokiro/bin/"
eq "ki a checkout without kiro/ is refused" 3 "$(HOME="$KH" "$TMP/nokiro/bin/kiro-install" --check >/dev/null 2>&1 </dev/null; echo $?)"
eq "ki --check and --uninstall together" 2 "$(kiq --check --uninstall)"
eq "ki unknown option" 2 "$(kiq --bogus)"

# uninstall: only what it made, and it says what it leaves
mkdir -p "$K/agentic-workflow/state"; printf 'run\n' > "$K/agentic-workflow/state/keep"
printf 'edited\n' >> "$K/prompts/agentic-workflow-start.md"
: > "$KFAKE_LOG"
HOME="$KH" PATH="$KFB:$PATH" "$KI_SRC2/bin/kiro-install" --uninstall --yes </dev/null > "$TMP/ki-un.out" 2>&1
eq "ki uninstall removes the plugin link" no "$([ -e "$K/agentic-workflow-plugin" ] || [ -L "$K/agentic-workflow-plugin" ] && echo yes || echo no)"
eq "ki uninstall removes the agent links" no "$([ -L "$K/agents/agentic-workflow-x.md" ] && echo yes || echo no)"
eq "ki uninstall removes the hook copy" no "$([ -e "$K/hooks/agentic-workflow.json" ] && echo yes || echo no)"
eq "ki uninstall leaves a copy that was edited" yes "$([ -f "$K/prompts/agentic-workflow-start.md" ] && echo yes || echo no)"
contains "ki uninstall says why it left it" "left: $K/prompts/agentic-workflow-start.md" "$(cat "$TMP/ki-un.out")"
eq "ki uninstall leaves the data folder" run "$(cat "$K/agentic-workflow/state/keep")"
contains "ki uninstall removes the server after a yes" "mcp remove --name agentic-workflow-atlassian --scope global" "$(cat "$KFAKE_LOG")"
contains "ki uninstall names the permission rules it did not touch" "kiro-permissions remove" "$(cat "$TMP/ki-un.out")"

# ---------------------------------------------------------------- jira-attachment (fake keychain and curl)
JA="$ROOT/bin/jira-attachment"
MP="$ROOT/bin/media-prep"
FB="$TMP/fakebin"; mkdir -p "$FB"
FAKE_KC="$TMP/kc"; FAKE_CURL="$TMP/curl"; export FAKE_KC FAKE_CURL
cat > "$FB/uname" <<'EOF'
#!/bin/sh
[ "$1" = "-s" ] && { echo Darwin; exit 0; }
exec /usr/bin/uname "$@"
EOF
cat > "$FB/security" <<'EOF'
#!/bin/sh
# a fake keychain: one file per account under $FAKE_KC; every argv is logged (stdin is not)
echo "security $*" >> "$FAKE_KC.argv"
acct=""
case "$1" in
  -i)
    while IFS= read -r line; do
      case "$line" in
        add-generic-password*) tok="${line##* -w }"; a="${line#* -a }"; a="${a%% *}"; printf '%s' "$tok" > "$FAKE_KC.$a" ;;
      esac
    done ;;
  find-generic-password)
    while [ $# -gt 0 ]; do [ "$1" = -a ] && acct="$2"; shift; done
    if [ -f "$FAKE_KC.$acct" ]; then cat "$FAKE_KC.$acct"; echo; else exit 44; fi ;;
  delete-generic-password)
    while [ $# -gt 0 ]; do [ "$1" = -a ] && acct="$2"; shift; done
    rm -f "$FAKE_KC.$acct" ;;
esac
exit 0
EOF
cat > "$FB/curl" <<'EOF'
#!/bin/sh
# a fake curl: logs argv, the config read from stdin and the URL; the answer depends on $FAKE_CURL_MODE
{ printf 'curl'; for a in "$@"; do printf ' [%s]' "$a"; done; echo; } >> "$FAKE_CURL.argv"
out=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -K) cat > "$FAKE_CURL.stdin"; shift 2 ;;
    -w|--max-filesize|--max-redirs|--proto|--proto-redir|--max-time) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
echo "$url" > "$FAKE_CURL.url"
case "${FAKE_CURL_MODE:-png}" in
  png) printf '\211PNG\r\n\032\n\000\000\000\rIHDR\000\000\000\001\000\000\000\001\010\006\000\000\000\037\025\304\211' > "$out"; printf 200 ;;
  html) printf '<html><body>log in</body></html>' > "$out"; printf 200 ;;
  zip) printf 'PK\003\004\024\000\000\000\010\000' > "$out"; printf 200 ;;
  me) printf '{"accountId":"abc123","emailAddress":"x"}' > "$out"; printf 200 ;;
  401) : > "$out"; printf 401 ;;
  404) : > "$out"; printf 404 ;;
  big) printf 000; exit 63 ;;
esac
exit 0
EOF
chmod +x "$FB/uname" "$FB/security" "$FB/curl"
ja() { PATH="$FB:$PATH" "$JA" "$@"; }   # run with the fakes first on PATH
TOKEN="ATATT3xFAKEFAKEFAKE0000=ABCDEF12"
EM="dev@example.com"

eq "ja no arguments" 64 "$(ja >/dev/null 2>&1; echo $?)"
eq "ja bad email" 64 "$(ja check --email 'a b' --site x.atlassian.net >/dev/null 2>&1; echo $?)"
for bad in x.atlassian.net.evil.com evil.com/.atlassian.net 'a.atlassian.net@evil.com' 'evil.com' 'x.atlassian.net:8443' "x.atlassian.net
evil.com"; do
  eq "ja refuses site [$bad]" 64 "$(ja check --email $EM --site "$bad" >/dev/null 2>&1; echo $?)"
done
eq "ja refuses an email with a newline" 64 "$(ja check --email "a@b.co
x" --site x.atlassian.net >/dev/null 2>&1; echo $?)"
eq "ja refuses an email with a quote" 64 "$(ja check --email 'a"b@b.co' --site x.atlassian.net >/dev/null 2>&1; echo $?)"
eq "ja refuses a bad cloud id" 64 "$(ja check --email $EM --site x.atlassian.net --cloud-id nope >/dev/null 2>&1; echo $?)"
eq "ja refuses a non-numeric id" 64 "$(ja get --email $EM --site x.atlassian.net --id 12a --max-bytes 10 --out "$TMP/o" >/dev/null 2>&1; echo $?)"
eq "ja refuses a relative out" 64 "$(ja get --email $EM --site x.atlassian.net --id 12 --max-bytes 10 --out rel >/dev/null 2>&1; echo $?)"
eq "ja refuses .. in out" 64 "$(ja get --email $EM --site x.atlassian.net --id 12 --max-bytes 10 --out "$TMP/a/../b" >/dev/null 2>&1; echo $?)"
eq "ja no token yet" 3 "$(ja check --email $EM --site x.atlassian.net >/dev/null 2>&1; echo $?)"
eq "ja login refuses junk" 64 "$(printf 'has a space' | ja login --email $EM >/dev/null 2>&1; echo $?)"
eq "ja login refuses a short token" 64 "$(printf 'abc' | ja login --email $EM >/dev/null 2>&1; echo $?)"
eq "ja login stores" "stored $EM" "$(printf '%s\n' "$TOKEN" | ja login --email $EM 2>/dev/null)"
case "$(cat "$FAKE_KC.argv")" in *"$TOKEN"*) fail=$((fail + 1)); echo "FAIL: the token reached a security argument list" >&2 ;; *) pass=$((pass + 1)) ;; esac

OUT="$TMP/media/raw"
export FAKE_CURL_MODE=png
eq "ja get a png" "saved $OUT/123.png image/png 33" "$(ja get --email $EM --site X.atlassian.net --id 123 --max-bytes 1000 --out "$OUT" 2>/dev/null)"
eq "ja get builds the url from site and id only" "https://x.atlassian.net/rest/api/3/attachment/content/123" "$(cat "$FAKE_CURL.url")"
contains "ja get sends the token on stdin as curl config" "user = \"$EM:$TOKEN\"" "$(cat "$FAKE_CURL.stdin")"
case "$(cat "$FAKE_CURL.argv")" in *"$TOKEN"*) fail=$((fail + 1)); echo "FAIL: the token reached curl's argument list" >&2 ;; *) pass=$((pass + 1)) ;; esac
contains "ja get ignores a .curlrc (-q first)" "curl [-q] [-sS]" "$(sed -n 1p "$FAKE_CURL.argv")"
contains "ja get allows https only" "[--proto] [=https] [--proto-redir] [=https]" "$(cat "$FAKE_CURL.argv")"
contains "ja get follows redirects with a limit" "[-L] [--max-redirs] [5]" "$(cat "$FAKE_CURL.argv")"
ja get --email $EM --site x.atlassian.net --cloud-id 0123abcd-0123-4abc-8123-0123456789ab --id 124 --max-bytes 1000 --out "$OUT" >/dev/null 2>&1
eq "ja get through the gateway address" "https://api.atlassian.com/ex/jira/0123abcd-0123-4abc-8123-0123456789ab/rest/api/3/attachment/content/124" "$(cat "$FAKE_CURL.url")"
FAKE_CURL_MODE=html; export FAKE_CURL_MODE
eq "ja get refuses an html page" 5 "$(ja get --email $EM --site x.atlassian.net --id 125 --max-bytes 1000 --out "$OUT" >/dev/null 2>&1; echo $?)"
eq "ja get leaves nothing under the id" "" "$(ls "$OUT" | grep '^125' )"
FAKE_CURL_MODE=zip; export FAKE_CURL_MODE
eq "ja get refuses an archive" 5 "$(ja get --email $EM --site x.atlassian.net --id 126 --max-bytes 1000 --out "$OUT" >/dev/null 2>&1; echo $?)"
FAKE_CURL_MODE=png; export FAKE_CURL_MODE
eq "ja get refuses a file over the limit" 5 "$(ja get --email $EM --site x.atlassian.net --id 127 --max-bytes 10 --out "$OUT" >/dev/null 2>&1; echo $?)"
FAKE_CURL_MODE=big; export FAKE_CURL_MODE
eq "ja get curl's own size limit" 5 "$(ja get --email $EM --site x.atlassian.net --id 128 --max-bytes 10 --out "$OUT" >/dev/null 2>&1; echo $?)"
FAKE_CURL_MODE=401; export FAKE_CURL_MODE
eq "ja get refused token" 4 "$(ja get --email $EM --site x.atlassian.net --id 129 --max-bytes 1000 --out "$OUT" >/dev/null 2>&1; echo $?)"
FAKE_CURL_MODE=404; export FAKE_CURL_MODE
eq "ja get not found" 6 "$(ja get --email $EM --site x.atlassian.net --id 130 --max-bytes 1000 --out "$OUT" >/dev/null 2>&1; echo $?)"
eq "ja leaves no .part file" "" "$(ls "$OUT" | grep '\.part$')"
FAKE_CURL_MODE=me; export FAKE_CURL_MODE
eq "ja check" "ok abc123" "$(ja check --email $EM --site x.atlassian.net 2>/dev/null)"
eq "ja logout" "removed $EM" "$(ja logout --email $EM 2>/dev/null)"
eq "ja after logout" 3 "$(ja check --email $EM --site x.atlassian.net >/dev/null 2>&1; echo $?)"
unset FAKE_CURL_MODE

# ---------------------------------------------------------------- media-prep (no ffmpeg needed except through fakes)
eq "mp no arguments" 64 "$("$MP" >/dev/null 2>&1; echo $?)"
eq "mp pick without candidates" "0.000 14.950 29.900 44.850 59.800" "$("$MP" pick --duration 60 --max-frames 8 | tr '\n' ' ' | sed 's/ $//')"
eq "mp pick uses scene changes" "0.000 5.200 20.100 40.500 59.800" "$("$MP" pick --duration 60 --max-frames 8 5.2 20.1 40.5 | tr '\n' ' ' | sed 's/ $//')"
eq "mp pick spreads many scene changes" "0.000 11.000 31.000 51.000 71.000 99.800" "$("$MP" pick --duration 100 --max-frames 6 3 7 11 15 19 23 27 31 35 39 43 47 51 55 59 63 67 71 75 79 | tr '\n' ' ' | sed 's/ $//')"
eq "mp pick a tiny video" "0.000" "$("$MP" pick --duration 0.3 --max-frames 6)"
eq "mp pick ignores edge and close times" "0.000 7.450 14.900 22.350 29.800" "$("$MP" pick --duration 30 --max-frames 6 0.1 0.2 10 10.2 29.9 | tr '\n' ' ' | sed 's/ $//')"
eq "mp pick bad usage" 64 "$("$MP" pick --duration x --max-frames 6 >/dev/null 2>&1; echo $?)"
eq "mp hash is order independent" "$("$MP" hash 1:10:2026-01-01T10:00:00 2:20:2026-01-02T10:00:00)" "$("$MP" hash 2:20:2026-01-02T10:00:00 1:10:2026-01-01T10:00:00)"
eq "mp hash changes with a size" "no" "$([ "$("$MP" hash 1:10:2026-01-01T10:00:00)" = "$("$MP" hash 1:11:2026-01-01T10:00:00)" ] && echo yes || echo no)"
eq "mp hash is 16 hex characters" 16 "$("$MP" hash 1:10:2026-01-01T10:00:00 | tr -d '\n' | wc -c | tr -d ' ')"
eq "mp hash refuses a name" 64 "$("$MP" hash 'photo one.png' >/dev/null 2>&1; echo $?)"

MD="$TMP/mp"; mkdir -p "$MD/raw" "$MD/view"
cp "$TMP/media/raw/123.png" "$MD/raw/123.png"
eq "mp image shows a png" "view $MD/raw/123.png" "$("$MP" image --in "$MD/raw/123.png" --out "$MD/view")"
eq "mp auto shows a png" "view $MD/raw/123.png" "$("$MP" auto --in "$MD/raw/123.png" --out "$MD/view" --max-frames 6)"
eq "mp auto shows a png without --max-frames" "view $MD/raw/123.png" "$("$MP" auto --in "$MD/raw/123.png" --out "$MD/view")"
eq "mp auto shows a png with --max-frames 1" "view $MD/raw/123.png" "$("$MP" auto --in "$MD/raw/123.png" --out "$MD/view" --max-frames 1)"
printf '<html>login</html>' > "$MD/raw/200.mp4"
eq "mp refuses a page called .mp4" 5 "$("$MP" auto --in "$MD/raw/200.mp4" --out "$MD/view" --max-frames 6 >/dev/null 2>&1; echo $?)"
printf '#EXTM3U\nfile:///etc/passwd\n' > "$MD/raw/201.mp4"
eq "mp refuses a playlist called .mp4" 5 "$("$MP" auto --in "$MD/raw/201.mp4" --out "$MD/view" --max-frames 6 >/dev/null 2>&1; echo $?)"
ln -s "$MD/raw/123.png" "$MD/raw/202.png"
eq "mp refuses a symlink" 5 "$("$MP" image --in "$MD/raw/202.png" --out "$MD/view" >/dev/null 2>&1; echo $?)"
eq "mp refuses a relative path" 64 "$("$MP" image --in raw/123.png --out "$MD/view" >/dev/null 2>&1; echo $?)"
eq "mp refuses .. in a path" 64 "$("$MP" image --in "$MD/raw/123.png" --out "$MD/view/../x" >/dev/null 2>&1; echo $?)"

# a video with fake ffprobe, ffmpeg and file: this checks the control flow and the hardening flags, not ffmpeg itself
VB="$TMP/videobin"; mkdir -p "$VB"
cat > "$VB/file" <<'EOF'
#!/bin/sh
for last; do :; done
case "$last" in *.webm) echo video/webm ;; *.mp4) echo video/mp4 ;; *) exec /usr/bin/file "$@" ;; esac
EOF
cat > "$VB/ffprobe" <<'EOF'
#!/bin/sh
echo "ffprobe $*" >> "$FAKE_FF.log"
case "$*" in
  *format_name*) echo "format_name=matroska,webm"; echo "duration=${FAKE_DURATION:-N/A}" ;;
  *packet=pts_time*) printf '0.000\n10.000\n20.400\n' ;;
  *"-select_streams a"*) [ "${FAKE_AUDIO:-no}" = yes ] && echo 1 ;;
esac
exit 0
EOF
cat > "$VB/ffmpeg" <<'EOF'
#!/bin/sh
echo "ffmpeg $*" >> "$FAKE_FF.log"
case "$*" in
  *"-f null"*) printf 'x pts_time:3.2 y\nx pts_time:9.0 y\nx pts_time:15.1 y\n' >&2 ;;
  *) for last; do :; done; printf 'jpeg' > "$last" ;;
esac
exit 0
EOF
chmod +x "$VB/file" "$VB/ffprobe" "$VB/ffmpeg"
FAKE_FF="$TMP/ff"; export FAKE_FF
mkdir -p "$MD/raw" && printf 'webm' > "$MD/raw/300.webm"
rm -f "$FAKE_FF.log"
res="$(FAKE_DURATION=20.5 PATH="$VB:$PATH" "$MP" auto --in "$MD/raw/300.webm" --out "$MD/view/300" --max-frames 6 --remove-input 2>&1)"
eq "mp video: five frames and a summary" "frames 5 duration 20.5 audio no" "$(printf '%s\n' "$res" | tail -n 1)"
eq "mp video: frame times" "0.000 3.200 9.000 15.100 20.300" "$(printf '%s\n' "$res" | sed -n 's/^frame \([0-9.]*\) .*/\1/p' | tr '\n' ' ' | sed 's/ $//')"
eq "mp video: frame file names carry the time" "t00000.000.jpg t00003.200.jpg t00009.000.jpg t00015.100.jpg t00020.300.jpg" "$(ls "$MD/view/300" | tr '\n' ' ' | sed 's/ $//')"
eq "mp video: the raw video is removed" "no" "$([ -e "$MD/raw/300.webm" ] && echo yes || echo no)"
log="$(cat "$FAKE_FF.log")"
# every single ffmpeg call (the scene pass and each frame), not only one of them, carries the hardening flags
eq "mp video: ffmpeg was called for the scene pass and every frame" 6 "$(grep -c '^ffmpeg ' "$FAKE_FF.log" | tr -d ' ')"
for flag in "-protocol_whitelist file" "-f matroska" "-nostdin" "-i file:$MD/raw/300.webm"; do
  eq "mp video: every ffmpeg call has [$flag]" 0 "$(grep '^ffmpeg ' "$FAKE_FF.log" | grep -vc -e "$flag" | tr -d ' ')"
done
contains "mp video: ffprobe reads files only too" "-protocol_whitelist file" "$(grep '^ffprobe ' "$FAKE_FF.log" | head -n 1)"
printf 'webm' > "$MD/raw/301.webm"
res="$(FAKE_DURATION=N/A FAKE_AUDIO=yes PATH="$VB:$PATH" "$MP" video --in "$MD/raw/301.webm" --out "$MD/view/301" --max-frames 4 2>&1)"
eq "mp video without a container duration uses the last packet" "frames 4 duration 20.4 audio yes" "$(printf '%s\n' "$res" | tail -n 1)"
eq "mp video: the input is kept without --remove-input" "yes" "$([ -e "$MD/raw/301.webm" ] && echo yes || echo no)"
printf 'webm' > "$MD/raw/302.webm"
eq "mp video: a too long video is refused" 5 "$(FAKE_DURATION=900 PATH="$VB:$PATH" "$MP" video --in "$MD/raw/302.webm" --out "$MD/view/302" --max-frames 4 >/dev/null 2>&1; echo $?)"
mkdir -p "$TMP/fileonly" && cp "$VB/file" "$TMP/fileonly/file"
eq "mp video: ffmpeg missing" 127 "$(PATH="$TMP/fileonly:$TMP/bin:/usr/bin:/bin" "$MP" auto --in "$MD/raw/302.webm" --out "$MD/view/302" --max-frames 4 >/dev/null 2>&1; echo $?)"
eq "mp check with ffmpeg" "ffmpeg yes" "$(PATH="$VB:$PATH" "$MP" check | sed -n 1p)"

# validate: the viewer's reply may become a findings file only when it keeps the contract
VM="$TMP/vm.json"
cat > "$VM" <<'EOF'
{
  "key": "ABC-1",
  "hash": "0123456789abcdef",
  "dir": "/x/media/0123456789abcdef",
  "files": [
    { "id": "56090", "kind": "image", "mime": "image/png", "frames": [ { "t": null, "path": "/x/raw/56090.png" } ] }
  ],
  "skipped": [ { "id": "56091", "reason": "too large" } ]
}
EOF
good() { printf '# Media findings for ABC-1\n\n## File 56090\n- Kind: screenshot\n- Seen: a form\n\n## Instruction-like text\nnone\n\n## Not viewed\nnone\n'; }
vf() { printf '%s\n' "$1" > "$TMP/vf.md"; "$MP" validate --manifest "$VM" --file "$TMP/vf.md" 2>&1; }
eq "mp validate accepts a good reply" ok "$(vf "$(good)")"
contains "mp validate refuses an unknown file id" "rejected file 99999" "$(vf "$(good | sed 's/File 56090/File 99999/')")"
contains "mp validate refuses a missing heading" "rejected the heading '## Not viewed'" "$(vf "$(good | grep -v 'Not viewed')")"
contains "mp validate refuses a wrong first line" "rejected the first line" "$(vf "hello")"
contains "mp validate refuses a private key" "rejected the reply contains a secret-like string" "$(vf "$(good; echo '-----BEGIN RSA PRIVATE KEY-----')")"
contains "mp validate refuses an Atlassian token" "rejected the reply contains a secret-like string" "$(vf "$(good; echo 'ATATT3xFAKEFAKEFAKEFAKEFAKE0000')")"
contains "mp validate refuses the user's home path" "rejected the reply contains a path of this user's home folder" "$(vf "$(good; echo "$HOME/.aws/credentials")")"
eq "mp validate allows an ordinary url path in a quote" ok "$(vf "$(good; echo '- Text: "/api/v1/users/12 returned 500"')")"
VM2="$TMP/vm2.json"; printf '{\n  "files": [\n    { "id": 56090, "kind": "image" }\n  ]\n}\n' > "$VM2"
eq "mp validate accepts a numeric manifest id" ok "$(printf '%s\n' "$(good)" > "$TMP/vf.md"; "$MP" validate --manifest "$VM2" --file "$TMP/vf.md" 2>&1)"
contains "mp validate refuses a JWT" "rejected the reply contains a secret-like string" "$(vf "$(good; echo 'token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0')")"
head -c 40000 /dev/zero | tr '\0' 'a' > "$TMP/big.md"
contains "mp validate refuses a huge reply" "rejected the reply is empty or longer" "$("$MP" validate --manifest "$VM" --file "$TMP/big.md" 2>&1)"

# manifest: the viewer may be pointed only at image files inside the manifest's own folder
MF="$TMP/mf"; mkdir -p "$MF/raw" "$MF/view"
cp "$TMP/media/raw/123.png" "$MF/raw/56090.png"; printf 'jpeg' > "$MF/view/t00000.000.jpg"; printf 'secret' > "$TMP/outside.png"
ln -s "$MF/raw/56090.png" "$MF/raw/link.png"; printf 'x' > "$MF/raw/notes.txt"
mf() { printf '{\n  "key": "ABC-1",\n  "dir": "%s",\n  "files": [\n    { "id": "56090", "frames": [ { "t": null, "path": "%s" }, { "t": 0, "path": "%s" } ] }\n  ]\n}\n' "$MF" "$1" "$2" > "$TMP/mf.json"; "$MP" manifest --file "$TMP/mf.json" 2>&1; }
eq "mp manifest accepts files inside dir" ok "$(mf "$MF/raw/56090.png" "$MF/view/t00000.000.jpg")"
contains "mp manifest refuses a path outside dir" "rejected a picture path is outside" "$(mf "$MF/raw/56090.png" "$TMP/outside.png")"
contains "mp manifest refuses .. in a path" "rejected" "$(mf "$MF/raw/56090.png" "$MF/raw/../../outside.png")"
contains "mp manifest refuses a non-image path" "rejected a picture path is not an image file" "$(mf "$MF/raw/56090.png" "$MF/raw/notes.txt")"
contains "mp manifest refuses a missing file" "rejected a picture file is missing" "$(mf "$MF/raw/56090.png" "$MF/raw/gone.png")"
contains "mp manifest refuses a symlink" "rejected a picture file is missing or is a link" "$(mf "$MF/raw/56090.png" "$MF/raw/link.png")"
printf '{\n  "files": []\n}\n' > "$TMP/mf0.json"
contains "mp manifest refuses a manifest without dir" "rejected the manifest has no absolute dir" "$("$MP" manifest --file "$TMP/mf0.json" 2>&1)"

# ---------------------------------------------------------------- kiro/ files (static consistency)
KA="$ROOT/kiro/agents"
HOSTMD="$ROOT/kiro/HOST.md"
shared_n=0; wrap_n=0
for f in "$ROOT"/agents/*.md; do
  a="${f##*/}"; a="${a%.md}"; shared_n=$((shared_n + 1))
  [ -f "$KA/agentic-workflow-$a.md" ] && pass=$((pass + 1)) || { fail=$((fail + 1)); printf 'FAIL: agents/%s.md has no Kiro wrapper\n' "$a" >&2; }
done
for f in "$KA"/agentic-workflow-*.md; do
  a="${f##*/agentic-workflow-}"; a="${a%.md}"; wrap_n=$((wrap_n + 1))
  [ -f "$ROOT/agents/$a.md" ] && pass=$((pass + 1)) || { fail=$((fail + 1)); printf 'FAIL: the Kiro wrapper %s has no agents/%s.md\n' "${f##*/}" "$a" >&2; }
  eq "kiro agent $a: its name is the file name" "name: agentic-workflow-$a" "$(grep -m1 '^name:' "$f")"
  contains "kiro agent $a: it loads the shared agent file" "  - file://~/.kiro/agentic-workflow-plugin/agents/$a.md" "$(cat "$f")"
  contains "kiro agent $a: it loads HOST.md" "  - file://~/.kiro/agentic-workflow-plugin/kiro/HOST.md" "$(cat "$f")"
  eq "kiro agent $a: no repository MCP file" 1 "$(grep -c '^includeMcpJson: false$' "$f")"
  contains "kiro agent $a: it is told never to call user_input" 'Never call the built-in tool `user_input`' "$(cat "$f")"
  # nothing a wrapper ships may grant permissions, run hooks or open another MCP server
  for bad in '^permissions:' '^hooks:' '^includeMcpJson: true' '"\*"' '@builtin' '"subagent"' '"@mcp"'; do
    if grep -Eq "$bad" "$f"; then fail=$((fail + 1)); printf 'FAIL: %s contains %s\n' "${f##*/}" "$bad" >&2; else pass=$((pass + 1)); fi
  done
  case "$a" in
    jira-analyst) ;;
    *) eq "kiro agent $a: no MCP server of its own" 0 "$(grep -c '^mcpServers:' "$f")" ;;
  esac
  case "$(grep -m1 '^model:' "$f")" in
    "model: claude-opus-5.5"|"model: claude-sonnet-5.5") pass=$((pass + 1)) ;;
    *) fail=$((fail + 1)); printf 'FAIL: %s has an unknown model\n' "${f##*/}" >&2 ;;
  esac
  # Kiro loads at most 50000 characters of a resource file and about 99000 of all of them
  sz1="$(wc -c < "$ROOT/agents/$a.md" | tr -d ' ')"; sz2="$(wc -c < "$HOSTMD" | tr -d ' ')"
  if [ "$sz1" -lt 50000 ] && [ "$sz2" -lt 50000 ] && [ $((sz1 + sz2)) -lt 90000 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL: the resources of %s are too large for Kiro (%s + %s)\n' "$a" "$sz1" "$sz2" >&2; fi
done
eq "kiro every shared agent has exactly one wrapper" "$shared_n" "$wrap_n"
for a in correctness-reviewer conventions-reviewer security-reviewer performance-reviewer media-analyst review-aggregator; do
  tl="$(grep -m1 '^tools:' "$KA/agentic-workflow-$a.md")"
  case "$tl" in *shell*|*execute_bash*|*str_replace*|*'"write"'*) fail=$((fail + 1)); printf 'FAIL: %s must not have a shell or an edit tool: %s\n' "$a" "$tl" >&2 ;; *) pass=$((pass + 1)) ;; esac
done
for a in correctness-reviewer conventions-reviewer security-reviewer performance-reviewer media-analyst review-aggregator; do
  case "$(grep -m1 '^tools:' "$KA/agentic-workflow-$a.md")" in *fs_write*) fail=$((fail + 1)); printf 'FAIL: %s must not write\n' "$a" >&2 ;; *) pass=$((pass + 1)) ;; esac
done
eq "kiro media-analyst has exactly read_file" 'tools: ["read_file"]' "$(grep -m1 '^tools:' "$KA/agentic-workflow-media-analyst.md")"
eq "kiro the four reviewers read and search only" 4 "$(grep -l '^tools: \["read_file", "grep_search", "file_search"\]$' "$KA"/agentic-workflow-*-reviewer.md | wc -l | tr -d ' ')"
eq "kiro the aggregator only reads (the orchestrator saves its summary)" 'tools: ["read_file"]' "$(grep -m1 '^tools:' "$KA/agentic-workflow-review-aggregator.md")"
eq "kiro the planner cannot edit existing files" 0 "$(grep -m1 '^tools:' "$KA/agentic-workflow-implementation-planner.md" | grep -c str_replace)"
eq "kiro the analyst gets the one Atlassian server and cannot delete files" 'tools: ["read", "fs_write", "str_replace", "shell", "@agentic-workflow-atlassian"]' "$(grep -m1 '^tools:' "$KA/agentic-workflow-jira-analyst.md")"
eq "kiro only the analyst and the orchestrator have the Atlassian tools" 2 "$(grep -l '@agentic-workflow-atlassian' "$KA"/*.md | wc -l | tr -d ' ')"
eq "kiro only the analyst and the orchestrator declare the server" 2 "$(grep -l '^mcpServers:' "$KA"/*.md | wc -l | tr -d ' ')"
eq "kiro the server address is the v2 one" 2 "$(grep -c 'url: "https://mcp.atlassian.com/v2/mcp"' "$KA/agentic-workflow-jira-analyst.md" "$KA/agentic-workflow.md" | awk -F: '{ n += $2 } END { print n }')"
eq "kiro the orchestrator may start the 11 stage agents and no other" 11 "$(grep -m1 '^tools:' "$KA/agentic-workflow.md" | grep -o 'subagent/agentic-workflow-[a-z-]*' | sort -u | wc -l | tr -d ' ')"
for f in "$ROOT"/agents/*.md; do
  a="${f##*/}"; a="${a%.md}"
  contains "kiro the orchestrator may start $a" "\"subagent/agentic-workflow-$a\"" "$(grep -m1 '^tools:' "$KA/agentic-workflow.md")"
done
eq "kiro the implementer wrapper names its memory folder" 1 "$(grep -c '~/.kiro/agentic-workflow/memory/implementer/' "$KA/agentic-workflow-implementer.md")"

# the hook: it matches the three write tools of the plugin's server, as Kiro writes their ids, and nothing else
KHOOK="$ROOT/kiro/hooks/agentic-workflow.json"
KMATCH="$(sed -n 's/.*"matcher": "\(.*\)",$/\1/p' "$KHOOK")"
for id in mcp_agentic_workflow_atlassian_editjiraissue mcp_agentic_workflow_atlassian_addcommenttojiraissue mcp_agentic_workflow_atlassian_transitionjiraissue; do
  printf '%s' "$id" | grep -Eq "$KMATCH" && pass=$((pass + 1)) || { fail=$((fail + 1)); printf 'FAIL: the Kiro hook matcher misses %s\n' "$id" >&2; }
done
for id in mcp_agentic_workflow_atlassian_getjiraissue mcp_agentic_workflow_atlassian_editjiraissue_x xmcp_agentic_workflow_atlassian_editjiraissue mcp_other_editjiraissue mcp_agentic_workflow_atlassian_editJiraIssue execute_bash; do
  printf '%s' "$id" | grep -Eq "$KMATCH" && { fail=$((fail + 1)); printf 'FAIL: the Kiro hook matcher also matches %s\n' "$id" >&2; } || pass=$((pass + 1))
done
eq "kiro hook: the guard runs with --tool kiro" 1 "$(grep -c '"command": "~/.kiro/agentic-workflow-plugin/hooks/guard --tool kiro" *}' "$KHOOK")"
eq "kiro hook: the session marker runs with --tool kiro --marker" 1 "$(grep -c '"command": "~/.kiro/agentic-workflow-plugin/hooks/guard --tool kiro --marker"' "$KHOOK")"
eq "kiro hook: no hook runs without --tool kiro" 0 "$(grep '"command"' "$KHOOK" | grep -vc -- '--tool kiro')"
eq "kiro hook: the guard is blocking on a PreToolUse only" 1 "$(grep -c '"trigger": "PreToolUse"' "$KHOOK")"
# the matcher's server is the server the agents declare (Kiro folds the name: lower case, - to _)
srv="$(sed -n 's/^  \([A-Za-z0-9-]*\):$/\1/p' "$KA/agentic-workflow-jira-analyst.md" | head -1)"
eq "kiro the declared server" agentic-workflow-atlassian "$srv"
eq "kiro the hook matcher names the declared server as Kiro folds it" "mcp_$(printf '%s' "$srv" | tr 'A-Z' 'a-z' | tr ' -' '__' | tr -cd 'a-z0-9_')_" "$(printf '%s' "$KMATCH" | sed -n 's/^\^\(mcp_[a-z0-9_]*_\)(.*/\1/p')"
eq "kiro kiro-permissions names the same server" "$srv" "$(sed -n 's/^server="\(.*\)"$/\1/p' "$ROOT/bin/kiro-permissions" | head -1)"
eq "kiro kiro-install names the same server" "$srv" "$(sed -n 's/^SERVER="\(.*\)"$/\1/p' "$ROOT/bin/kiro-install" | head -1)"
eq "kiro the guard reads the same prefix form setup stores" 1 "$(grep -c '`mcpPrefix` is `agentic-workflow-atlassian::`' "$HOSTMD")"

# the prompts: no frontmatter (Kiro sends it to the model as text), the arguments, and the shared skill they follow
for x in start setup media; do
  p="$ROOT/kiro/prompts/agentic-workflow-$x.md"
  [ -f "$p" ] && pass=$((pass + 1)) || { fail=$((fail + 1)); printf 'FAIL: missing prompt %s\n' "$p" >&2; continue; }
  eq "kiro prompt $x: no frontmatter" "no" "$([ "$(head -c 3 "$p")" = "---" ] && echo yes || echo no)"
  eq "kiro prompt $x: it passes the arguments" 1 "$(grep -c '^Arguments: \$ARGUMENTS$' "$p")"
  contains "kiro prompt $x: it follows the shared skill" "~/.kiro/agentic-workflow-plugin/skills/$x/SKILL.md" "$(cat "$p")"
  [ -f "$ROOT/skills/$x/SKILL.md" ] && pass=$((pass + 1)) || { fail=$((fail + 1)); printf 'FAIL: skills/%s/SKILL.md is missing\n' "$x" >&2; }
  contains "kiro prompt $x: it reads HOST.md" "kiro/HOST.md" "$(cat "$p")"
done
eq "kiro there is one prompt per skill" "$(ls "$ROOT"/skills | wc -l | tr -d ' ')" "$(ls "$ROOT"/kiro/prompts | wc -l | tr -d ' ')"

# HOST.md overrides passages of the shared files by their exact text: each one must still be there, and named in HOST.md
for pair in 'skills/setup/SKILL.md|**Tool names.**' 'skills/setup/SKILL.md|**Atlassian server.**' 'skills/setup/SKILL.md|**Authorization.**' \
            'skills/setup/SKILL.md|## Waiting for an authorization' 'skills/setup/SKILL.md|## Permission rules' 'skills/setup/SKILL.md|## Migration from an older version' \
            'skills/start/SKILL.md|- Hooks:' 'skills/start/SKILL.md|- Jira authorization:'; do
  file="${pair%%|*}"; anchor="${pair#*|}"
  grep -Fq -- "$anchor" "$ROOT/$file" && pass=$((pass + 1)) || { fail=$((fail + 1)); printf 'FAIL: %s no longer contains [%s], which kiro/HOST.md overrides\n' "$file" "$anchor" >&2; }
  grep -Fq -- "$anchor" "$HOSTMD" && pass=$((pass + 1)) || { fail=$((fail + 1)); printf 'FAIL: kiro/HOST.md does not name [%s]\n' "$anchor" >&2; }
done
# the rules the installer's permission script writes cover exactly the agents that exist
eq "kiro kiro-permissions allows the 12 agents of this checkout" 12 "$("$ROOT/bin/kiro-permissions" print --plugin-dir "$ROOT" | awk '/capability:/ { s = ($0 ~ /subagent/) } s && /^      - / { n++ } END { print n + 0 }')"
# the real checkout installs into a scratch Kiro home, and passes its own check
KRH="$TMP/kreal"; mkdir -p "$KRH"
eq "kiro the real checkout installs" 0 "$(HOME="$KRH" "$ROOT/bin/kiro-install" --no-mcp >/dev/null 2>&1 </dev/null; echo $?)"
eq "kiro the real checkout passes --check" 0 "$(HOME="$KRH" "$ROOT/bin/kiro-install" --no-mcp --check >/dev/null 2>&1 </dev/null; echo $?)"
eq "kiro the installed hook calls a guard that exists" yes "$([ -x "$KRH/.kiro/agentic-workflow-plugin/hooks/guard" ] && echo yes || echo no)"

# the agents keep their boundaries
grep -q '^tools: Read$' "$ROOT/agents/media-analyst.md" && pass=$((pass + 1)) || { fail=$((fail + 1)); echo "FAIL: media-analyst must have only the Read tool" >&2; }
grep -q '^disallowedTools: .*Bash' "$ROOT/agents/media-analyst.md" && pass=$((pass + 1)) || { fail=$((fail + 1)); echo "FAIL: media-analyst must disallow Bash" >&2; }
if grep '^tools:' "$ROOT/agents/jira-analyst.md" | grep -Eq '\b(Agent|Task)\b'; then fail=$((fail + 1)); echo "FAIL: jira-analyst must not have the Agent tool (it reads untrusted text)" >&2; else pass=$((pass + 1)); fi

# permissions of the shipped scripts
for f in bin/aw-paths bin/aw-decisions bin/gh-as bin/wait-gh-login bin/wait-mcp bin/jira-attachment bin/media-prep bin/kiro-install bin/kiro-permissions hooks/guard; do
  if [ -x "$ROOT/$f" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL: %s is not executable\n' "$f" >&2; fi
done
# the hook matcher must name exactly the Atlassian prefixes the analyst may use
for p in plugin_agentic-workflow_atlassian claude_ai_Atlassian_Rovo claude_ai_Atlassian_Rovo_2; do
  grep -q "mcp__${p}__" "$ROOT/agents/jira-analyst.md" && grep -q "$p" "$ROOT/hooks/hooks.json" && pass=$((pass + 1)) || { fail=$((fail + 1)); printf 'FAIL: prefix %s missing from jira-analyst tools or hooks.json\n' "$p" >&2; }
done

# No AI attribution: the rule must stay in the two agents that write commits and PR texts, and the check that
# pr-publisher runs before a push must flag exactly the commits that carry such a line (the command is taken
# from the agent file itself, so the test cannot drift from the text).
IMPL="$(cat "$ROOT/agents/implementer.md")"
PUBL="$(cat "$ROOT/agents/pr-publisher.md")"
contains "implementer: commits with -F from a file" 'git commit -F <State>/<KEY>/commit-msg.txt' "$IMPL"
contains "implementer: no Co-Authored-By line" 'no `Co-Authored-By` trailer' "$IMPL"
contains "implementer: reads the commit back" 'git log -1 --format=%B' "$IMPL"
contains "pr-publisher: no AI attribution rule" '- No AI attribution.' "$PUBL"
contains "pr-publisher: bodies go through a file" '--body-file' "$PUBL"
contains "pr-publisher: checks the commits before a push" '- Attribution check before every push' "$PUBL"
contains "pr-publisher: never rewrites history" 'You never rewrite history' "$PUBL"
contains "start: attribution is an always-stop" 'carries an AI attribution line' "$(cat "$ROOT/skills/start/SKILL.md")"
ATT="$TMP/attribution"
mkrepo "$ATT" ""
git -C "$ATT" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m base
git -C "$ATT" update-ref refs/remotes/origin/main HEAD
attc() { git -C "$ATT" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m "$1"; }
attc "clean commit"
attc "$(printf 'trailer\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')"
attc "$(printf 'lower case trailer\n\nco-authored-by: claude sonnet <x@y.z>')"
attc "$(printf 'generated\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)')"
attc "$(printf 'session\n\nClaude-Session: https://claude.ai/code/session_abc')"
attc "$(printf 'human\n\nCo-Authored-By: Jane Doe <jane@example.com>')"
attc "docs: explain why the Co-Authored-By: Claude and Generated with Claude Code lines are removed"
ATTCMD="$(sed -n 's/.*`\(git log -i -E[^`]*\)`.*/\1/p' "$ROOT/agents/pr-publisher.md" | sed 's|<base>|main|')"
contains "attribution check: the command is found in pr-publisher.md" 'origin/main..HEAD' "$ATTCMD"
ATTHITS="$(cd "$ATT" && sh -c "$ATTCMD" | sed 's/^[0-9a-f]* //' | sort | tr '\n' ',')"
eq "attribution check flags the four attributed commits and nothing else" "generated,lower case trailer,session,trailer," "$ATTHITS"

# ---------------------------------------------------------------- aw-decisions
AWD="$ROOT/bin/aw-decisions"
DS="$TMP/home/.claude/agentic-workflow/state/github.com/octo/hello"
DF="$DS/operator-decisions.jsonl"
dadd() { # category followed [extra args]
  c="$1"; f="$2"; shift 2
  "$AWD" add --state "$DS" --key ABC-1 --stage plan --tag Tech --category "$c" --followed "$f" --source operator "$@"
}
eq "awd stats without history is empty" "0:" "$(out="$("$AWD" stats --state "$DS")"; echo "$?:$out")"
eq "awd streak without history is empty" "0:" "$(out="$("$AWD" streak --state "$DS")"; echo "$?:$out")"
eq "awd the first record is D1" D1 "$(dadd naming true --confidence 0.50)"
eq "awd the second record is D2" D2 "$(dadd naming false)"
eq "awd one line per record" 2 "$(grep -c . "$DF")"
contains "awd the record holds the fields" '"key":"ABC-1","stage":"plan","tag":"Tech","category":"naming","followed":"true","source":"operator","confidence":"0.50","answer":""}' "$(sed -n 1p "$DF")"
eq "awd stats counts followed and overridden" "naming followed=1 overridden=1" "$("$AWD" stats --state "$DS")"
dadd naming none >/dev/null
dadd other true >/dev/null
eq "awd stats skips none and other" "naming followed=1 overridden=1" "$("$AWD" stats --state "$DS")"
i=0; while [ "$i" -lt 10 ]; do dadd naming true >/dev/null; i=$((i + 1)); done
eq "awd stats looks at the last 10 of a category" "naming followed=10 overridden=0" "$("$AWD" stats --state "$DS")"
dadd ui-text false >/dev/null
eq "awd stats has one line per category" "naming followed=10 overridden=0|ui-text followed=0 overridden=1" "$("$AWD" stats --state "$DS" | tr '\n' '|' | sed 's/|$//')"
printf '%s' '{"id":"D40","category":"x"}' >> "$DF"
eq "awd the id follows the highest one, also after a lost newline" D41 "$(dadd naming true)"
eq "awd the hand-edited line stays alone" 1 "$(grep -c '^{"id":"D40","category":"x"}$' "$DF")"

sadd() { # tag answer source
  "$AWD" add --state "$DS" --key ABC-2 --stage analysis --tag "$1" --category edge-case --followed none --source "$3" --answer "$2" >/dev/null
}
sadd DoR:S4 out-of-scope operator; sadd DoR:S4 out-of-scope operator
eq "awd two equal answers are no streak" "" "$("$AWD" streak --state "$DS")"
sadd DoR:S4 out-of-scope operator-checkpoint
eq "awd a checkpoint record does not make a streak" "" "$("$AWD" streak --state "$DS")"
sadd DoR:S4 out-of-scope operator
contains "awd three equal operator answers are a streak" "DoR:S4 out-of-scope D" "$("$AWD" streak --state "$DS")"
eq "awd a streak names three records" 3 "$("$AWD" streak --state "$DS" | awk '{ print split($3, a, ",") }')"
sadd DoR:S4 handle operator
eq "awd a different answer ends the streak" "" "$("$AWD" streak --state "$DS")"
sadd DoR:S2 other operator; sadd DoR:S2 other operator; sadd DoR:S2 other operator
eq "awd other is never a streak" "" "$("$AWD" streak --state "$DS")"

before="$(cat "$DF")"
refused() { # name args...
  n="$1"; shift
  eq "awd refuses $n" 2 "$("$AWD" "$@" >/dev/null 2>&1; echo $?)"
}
base="--stage plan --tag Tech --category naming --followed true --source operator"
refused "a state outside the run folders" add --state "$TMP/work" --key ABC-1 $base
refused "the folder of local.json" add --state "$TMP/home/.claude/agentic-workflow/repos/github.com/octo/hello" --key ABC-1 $base
refused "dot-dot in the state path" add --state "$DS/../../../repos" --key ABC-1 $base
refused "a relative state path" stats --state agentic-workflow/state/x
refused "a bad key" add --state "$DS" --key 'ABC-1"x' $base
refused "a lower-case key" add --state "$DS" --key abc-1 $base
refused "an unknown category" add --state "$DS" --key ABC-1 --stage plan --tag Tech --category 'naming other' --followed true --source operator
refused "an unknown tag" add --state "$DS" --key ABC-1 --stage plan --tag DoR:Z1 --category naming --followed true --source operator
refused "an unknown followed value" add --state "$DS" --key ABC-1 --stage plan --tag Tech --category naming --followed yes --source operator
refused "an unknown source" add --state "$DS" --key ABC-1 --stage plan --tag Tech --category naming --followed true --source agent
refused "a free-text answer" add --state "$DS" --key ABC-1 $base --answer 'whatever'
refused "an answer code on a Tech question" add --state "$DS" --key ABC-1 $base --answer handle
refused "a bad confidence" add --state "$DS" --key ABC-1 $base --confidence 1.50
refused "an unknown option" add --state "$DS" --question text
refused "no subcommand"
eq "awd a refused call writes nothing" "$before" "$(cat "$DF")"
DL="$TMP/home/.claude/agentic-workflow/state/github.com/octo/link"; mkdir -p "$DL"
ln -s "$TMP/work/target" "$DL/operator-decisions.jsonl"
refused "a symbolic link as the history file" add --state "$DL" --key ABC-1 $base

# the confidence rules the prompts must keep
PLANNER="$(cat "$ROOT/agents/implementation-planner.md")"
ANALYST="$(cat "$ROOT/agents/jira-analyst.md")"
contains "planner: the threshold" '0.85' "$PLANNER"
contains "planner: agent-decided" 'agent-decided' "$PLANNER"
contains "analyst: the READY threshold" 'confidence ≥ 0.85' "$ANALYST"
eq "analyst: no old threshold" 0 "$(grep -c '0\.75' "$ROOT/agents/jira-analyst.md")"
contains "setup: aw-decisions rule" '`Bash(aw-decisions *)`' "$(cat "$ROOT/skills/setup/SKILL.md")"
contains "config schema: aw-decisions rule" '`Bash(aw-decisions *)`' "$(cat "$ROOT/skills/start/references/config-schema.md")"
for r in correctness conventions security performance; do
  contains "$r reviewer: agent-decided is in scope" 'agent-decided' "$(cat "$ROOT/agents/$r-reviewer.md")"
done
contains "pr-publisher: lists the agent decisions" 'Decisions made by the agent' "$(cat "$ROOT/agents/pr-publisher.md")"

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
