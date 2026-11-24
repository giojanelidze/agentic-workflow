#!/bin/sh
# Shell tests for bin/aw-paths, hooks/guard, bin/jira-attachment and bin/media-prep. No network, no claude CLI, no real HOME,
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

# the agents keep their boundaries
grep -q '^tools: Read$' "$ROOT/agents/media-analyst.md" && pass=$((pass + 1)) || { fail=$((fail + 1)); echo "FAIL: media-analyst must have only the Read tool" >&2; }
grep -q '^disallowedTools: .*Bash' "$ROOT/agents/media-analyst.md" && pass=$((pass + 1)) || { fail=$((fail + 1)); echo "FAIL: media-analyst must disallow Bash" >&2; }
if grep '^tools:' "$ROOT/agents/jira-analyst.md" | grep -Eq '\b(Agent|Task)\b'; then fail=$((fail + 1)); echo "FAIL: jira-analyst must not have the Agent tool (it reads untrusted text)" >&2; else pass=$((pass + 1)); fi

# permissions of the shipped scripts
for f in bin/aw-paths bin/gh-as bin/wait-gh-login bin/wait-mcp bin/jira-attachment bin/media-prep hooks/guard; do
  if [ -x "$ROOT/$f" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL: %s is not executable\n' "$f" >&2; fi
done
# the hook matcher must name exactly the Atlassian prefixes the analyst may use
for p in plugin_agentic-workflow_atlassian claude_ai_Atlassian_Rovo claude_ai_Atlassian_Rovo_2; do
  grep -q "mcp__${p}__" "$ROOT/agents/jira-analyst.md" && grep -q "$p" "$ROOT/hooks/hooks.json" && pass=$((pass + 1)) || { fail=$((fail + 1)); printf 'FAIL: prefix %s missing from jira-analyst tools or hooks.json\n' "$p" >&2; }
done

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
