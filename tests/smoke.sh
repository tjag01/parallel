#!/usr/bin/env bash
# tests/smoke.sh: an end-to-end check of cc-parallel with a stub `claude`, in a throwaway HOME and tmux server.
# Needs tmux and git. Run from the repo root: bash tests/smoke.sh
set -uo pipefail
ROOT="$(cd -P "$(dirname "$0")/.." && pwd)"
CCP="$ROOT/bin/cc-parallel"
WORK="$(cd -P -- "$(mktemp -d "${TMPDIR:-/tmp}/ccp-smoke.XXXXXX")" && pwd)"  # physical: macOS TMPDIR is /var/..., a link to /private/var/..., and cc-parallel resolves its own path
TMUX_TMPDIR="$(mktemp -d /tmp/ccpt.XXXX)"  # short: a socket path is capped at ~100 bytes
export HOME="$WORK/home" TMUX_TMPDIR
# 
export XDG_CONFIG_HOME="$WORK/home/.config" XDG_STATE_HOME="$WORK/home/.local/state"
mkdir -p "$HOME/Downloads" "$WORK/bin"
unset TMUX
pass=0; fail=0
ok() { echo "ok   $*"; pass=$((pass + 1)); }
no() { echo "FAIL $*"; fail=$((fail + 1)); }
check() { local d="$1"; shift; if "$@"; then ok "$d"; else no "$d"; fi; }
wait_for() { for _ in $(seq 1 "${2:-40}"); do eval "$1" && return 0; sleep 0.25; done; return 1; }
# The same on GNU (Linux, WSL) and BSD (macOS) tools:
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
ago() { local e=$(( $(date +%s) - $1 )); date -d "@$e" +%Y%m%d%H%M.%S 2>/dev/null || date -r "$e" +%Y%m%d%H%M.%S; }  # touch -t, N s ago
sed_i() { local f="${*: -1}"; sed "${@:1:$#-1}" "$f" >"$f.new" && mv "$f.new" "$f"; }   # sed -i
finish() { tmux kill-server 2>/dev/null; for s in "$TMUX_TMPDIR"/tmux-*/*; do tmux -S "$s" kill-server 2>/dev/null; done; }
trap finish EXIT; [ -n "${KEEP:-}" ] && trap "finish; echo kept \$WORK" EXIT

# A stub claude: records its arguments, then echoes every line it is sent; "/exit" ends it. tmux names a pane after
# its process, from argv[0] on Linux but from the executable's own name on macOS, so the stub runs under a copy of
# bash that is itself named claude.
mkdir -p "$WORK/stub"; cp "$(command -v bash)" "$WORK/stub/claude"
printf '#!/bin/sh\nexec "%s" "%s" "$@"\n' "$WORK/stub/claude" "$WORK/stub/claude.sh" >"$WORK/bin/claude"
cat >"$WORK/stub/claude.sh" <<'EOF'
printf '%s\n' "$@" >"$HOME/claude-args-$CC_PARALLEL_LANE"
while IFS= read -r line; do
  printf '%s\n' "$line" >>"$HOME/claude-input-$CC_PARALLEL_LANE"
  if [ "$line" = "/exit" ]; then
    if [ -e "$HOME/dialog-$CC_PARALLEL_LANE" ]; then   # as Claude Code does when background work is still running
      printf 'Background work is running\n  1. Exit and stop tasks\n  2. Move to background and exit\n  3. Stay\n Enter to confirm\n'
      while IFS= read -r -n1 c; do printf 'dialog-key %s\n' "$c" >>"$HOME/claude-input-$CC_PARALLEL_LANE"; [ "$c" = 1 ] && exit 0; done
    fi
    if [ -e "$HOME/feedback-$CC_PARALLEL_LANE" ]; then   # as Claude Code does when it holds an unsent feedback draft
      printf 'You have 1 unsent feedback draft\n  Enter to review & send · Esc to discard and exit\n'
      while IFS= read -r -n1 c; do
        if [ "$c" = $'\e' ]; then printf 'feedback-key ESC\n' >>"$HOME/claude-input-$CC_PARALLEL_LANE"; exit 0; fi
        if [ -z "$c" ]; then printf 'feedback-key ENTER\n' >>"$HOME/claude-input-$CC_PARALLEL_LANE"; exit 0; fi
      done
    fi
    exit 0
  fi
done
EOF
chmod +x "$WORK/bin/claude"
export PATH="$WORK/bin:$PATH"

# A repo with one commit.
R="$WORK/repo"; git init -q -b main "$R"; git -C "$R" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init

"$CCP" init --repo "$R" --lanes 6 >/dev/null
printf 'POLL=1\nCLAUDE_BIN=%q\n' "$WORK/bin/claude" >>"$XDG_CONFIG_HOME/cc-parallel/config"
check "init makes six lanes (one checkout and five worktrees)" test "$(git -C "$R" worktree list | wc -l)" -eq 6
check "init writes the four kickoff templates" test "$(ls "$XDG_CONFIG_HOME/cc-parallel/kickoff" | wc -l)" -eq 4

"$CCP" up >/dev/null
check "up makes the session with a relay window and six lane windows" test "$(tmux list-windows -t parallel | wc -l)" -eq 7
check "up starts the relay" wait_for "[ -f '$XDG_STATE_HOME/cc-parallel/relay/log/heartbeat' ]"

tmux new-window -d -t parallel -n relay; tmux new-window -d -t parallel -n A   # duplicate names, as a real session collects
check "up copes with two windows of one name" bash -c "'$CCP' up 2>&1 | grep -qv \"can't find\""

printf '# T1 · first task\nDo the thing.\n' >"$HOME/Downloads/t1.md"
"$CCP" queue A t1.md opus task >/dev/null
check "a queued launch starts Claude Code in lane A" wait_for "[ -f '$HOME/claude-args-A' ]"
check "the launch passes the model" grep -qx opus "$HOME/claude-args-A"
check "the launch passes the hooks through --settings" grep -q '"Stop"' "$HOME/claude-args-A"
check "the kickoff names the file and the code" grep -q "\[T1 · lane A\] Read $HOME/Downloads/t1.md" "$HOME/claude-args-A"
check "the status line names the sprint from its heading" grep -qx 'Opus 5.5 · T1 first task' "$XDG_STATE_HOME/cc-parallel/status/A.label"
wait_for "[ \"\$(tmux display-message -p -t parallel:1 '#{pane_current_command}')\" = claude ]"

tmux copy-mode -t parallel:1   # as if someone scrolled lane A back in the wall
printf 'A ruling.\n' >"$HOME/Downloads/r1.md"
"$CCP" send A r1.md >/dev/null
check "send types the checked line into the running session, even from copy mode" wait_for "grep -q 'Read $HOME/Downloads/r1.md whole (sha256 starts' '$HOME/claude-input-A' 2>/dev/null"

printf 'r1.md deadbeef\n' >"$XDG_STATE_HOME/cc-parallel/relay/inbox/A-20260101T000000-relay.txt"
check "a relay file with the wrong sha256 is rejected" wait_for "[ -f '$XDG_STATE_HOME/cc-parallel/relay/rejected/A-20260101T000000-relay.txt' ]"
printf 'r1.md 12345678; rm -rf ~\n' >"$XDG_STATE_HOME/cc-parallel/relay/inbox/A-20260101T000001-relay.txt"
check "a relay file with shell characters is rejected" wait_for "[ -f '$XDG_STATE_HOME/cc-parallel/relay/rejected/A-20260101T000001-relay.txt' ]"
printf 'r1.md %s\n' "$(sha256 "$HOME/Downloads/r1.md" | cut -c1-8)" >"$XDG_STATE_HOME/cc-parallel/relay/inbox/Q-20260101T000002-relay.txt"
check "a relay file for an unknown lane is rejected" wait_for "[ -f '$XDG_STATE_HOME/cc-parallel/relay/rejected/Q-20260101T000002-relay.txt' ]"

printf '# T2 · second task\n' >"$HOME/Downloads/t2.md"
"$CCP" queue A t2.md sonnet task --exit >/dev/null
check "--exit sends /exit to a busy lane, then launches" wait_for "grep -qx sonnet '$HOME/claude-args-A' 2>/dev/null" 80
check "the /exit reached the session" grep -qx /exit "$HOME/claude-input-A"
check "the kickoff tells the agent how to mark its task done" grep -q "cc-parallel done T2" "$HOME/claude-args-A"

printf '# T3 · follow-on\n' >"$HOME/Downloads/t3.md"
"$CCP" queue A t3.md opus task --after-done >/dev/null
sleep 4
check "an --after-done launch waits while the lane has not run done" grep -qx sonnet "$HOME/claude-args-A"
check "the relay logs why it is holding" grep -q "HOLD A-.*has not run cc-parallel done" "$XDG_STATE_HOME/cc-parallel/relay/log/relay.log"
check "the relay logs a hold once, not on every poll" test "$(grep -c "HOLD A-.*has not run cc-parallel done" "$XDG_STATE_HOME/cc-parallel/relay/log/relay.log")" -eq 1
CC_PARALLEL_LANE=A CC_PARALLEL_STATUS="$XDG_STATE_HOME/cc-parallel/status" "$CCP" "done" T2 >/dev/null
check "done lets the follow-on start: /exit, then the launch" wait_for "grep -q 'T3 · lane A' '$HOME/claude-args-A' 2>/dev/null" 80
touch "$HOME/dialog-A"
printf '# T4 · after a dialog\n' >"$HOME/Downloads/t4.md"
"$CCP" queue A t4.md opus task --exit >/dev/null
check "the relay answers Claude Code's exit dialog with 1, then launches" wait_for "grep -q 'T4 · lane A' '$HOME/claude-args-A' 2>/dev/null" 80
check "the dialog got exactly the key 1" grep -qx 'dialog-key 1' "$HOME/claude-input-A"
rm -f "$HOME/dialog-A"
touch "$HOME/feedback-A"
printf '# T5 · after a feedback-draft prompt\n' >"$HOME/Downloads/t5.md"
"$CCP" queue A t5.md opus task --exit >/dev/null
check "the relay answers Claude Code's feedback-draft prompt with Esc, then launches" wait_for "grep -q 'T5 · lane A' '$HOME/claude-args-A' 2>/dev/null" 80
check "the feedback-draft prompt got Esc, never Enter" bash -c "grep -qx 'feedback-key ESC' '$HOME/claude-input-A' && ! grep -q 'feedback-key ENTER' '$HOME/claude-input-A'"
rm -f "$HOME/feedback-A"
check "the done marker is used once" test ! -e "$XDG_STATE_HOME/cc-parallel/status/A.done"
check "done outside a lane is refused" bash -c "! env -u CC_PARALLEL_LANE '$CCP' done 2>/dev/null"
check "done --lane marks a lane started some other way" bash -c "'$CCP' done --lane B Q9 >/dev/null && grep -q '^Q9 ' '$XDG_STATE_HOME/cc-parallel/status/B.done'"

sed_i "s|^# ON_CHANGE=.*|ON_CHANGE='echo \"\$LANE \$STATE\" >>\"\$HOME/changes\"'|" "$XDG_CONFIG_HOME/cc-parallel/config"
kill "$(cat "$XDG_STATE_HOME/cc-parallel/relay/log/relay.pid")" 2>/dev/null; sleep 1
"$CCP" up >/dev/null
wait_for "grep -q 'START relay' '$XDG_STATE_HOME/cc-parallel/relay/log/relay.log'"
echo '{}' | CC_PARALLEL_LANE=B "$CCP" hook working; sleep 2
echo '{}' | CC_PARALLEL_LANE=B "$CCP" hook idle
check "the hook records the lane's state" grep -q '^idle ' "$XDG_STATE_HOME/cc-parallel/status/B"
check "ON_CHANGE runs when a lane turns idle" wait_for "grep -qx 'B idle' '$HOME/changes' 2>/dev/null" 40
check "status lists every lane" test "$("$CCP" status | grep -c '^[A-F] ')" -eq 6

CC_PARALLEL_NO_ATTACH=1 "$CCP" wall >/dev/null 2>&1
check "the wall tiles all six lanes" test "$(tmux -L parallel-wall-A_B_C_D_E_F list-panes -t wall:lanes | wc -l)" -eq 6
check "the wall refuses more lanes than fit" bash -c "WALL_MAX=4 CC_PARALLEL_NO_ATTACH=1 '$CCP' wall 2>&1 | grep -q 'too many'"
CC_PARALLEL_NO_ATTACH=1 "$CCP" wall A C >/dev/null 2>&1
check "a wall of a subset shows only those lanes" test "$(tmux -L parallel-wall-A_C list-panes -t wall:lanes | wc -l)" -eq 2

# gc: old caches go; the current task's, a fresh one, the lane's own target/ and anything outside the globs stay.
LB="$WORK/repo-lanes/b"; LC="$WORK/repo-lanes/c"
mkdir -p "$LB/target/q1-scratch/clone/target/debug" "$LB/target/q2-scratch/clone/target/debug" "$LC/target/q3-scratch/clone/target/debug" "$LB/target/debug" "$LB/keepme/clone/target"
touch -t "$(ago 10800)" "$LB/target/q1-scratch/clone/target/debug" "$LB/target/q1-scratch/clone/target" "$LB/target/q2-scratch/clone/target/debug" "$LB/target/q2-scratch/clone/target"
echo 'Q2' >"$XDG_STATE_HOME/cc-parallel/status/B.code"
printf 'GC_GLOBS="target/*-scratch/clone/target target"\n' >>"$XDG_CONFIG_HOME/cc-parallel/config"
mkdir -p "$LB/target/q21-scratch/clone/target/debug"; touch -t "$(ago 10800)" "$LB/target/q21-scratch/clone/target/debug" "$LB/target/q21-scratch/clone/target"
"$CCP" gc --dry-run >"$WORK/gc-dry.out" 2>&1  # to a file: grep -q on a pipe closes it early and cc-parallel's next echo hits a broken pipe
check "gc --dry-run lists without removing" bash -c "grep -q 'would remove .*q1-scratch' '$WORK/gc-dry.out' && [ -d '$LB/target/q1-scratch/clone/target' ]"
check "gc does not keep q21's cache for the current task Q2 (the code matches a whole name, not a substring)" grep -q 'would remove .*q21-scratch' "$WORK/gc-dry.out"
"$CCP" gc >/dev/null
check "gc removes an old cache of a finished task" test ! -e "$LB/target/q1-scratch/clone/target"
check "gc keeps the lane's current task's cache" test -d "$LB/target/q2-scratch/clone/target"
check "gc keeps a cache used in the last hour" test -d "$LC/target/q3-scratch/clone/target"
check "gc never removes a lane's own target/" test -d "$LB/target/debug"
check "gc touches nothing outside its globs" test -d "$LB/keepme/clone/target"

# The status line: lane · model · sprint · time on it, coloured by state; STOP when a lane's stop file is newer than its last launch or relay.
SD="$XDG_STATE_HOME/cc-parallel/status"
printf 'Opus · Q2 Two\n' >"$SD/B.label"; printf 'working 0 hook\n' >"$SD/B"
[ -e "$SD/B.done" ] && { check "bar: a lane that ran done is blue, with done" bash -c "'$CCP' bar B | grep -q 'bg=colour33.* · done '"; mv "$SD/B.done" "$SD/B.done.used"; }
check "bar: a working lane is green and shows lane, label and time" bash -c "'$CCP' bar B | grep -q '^#\[bg=colour34,fg=black\] B · Opus · Q2 Two · 0h0[0-9]m #\[default\]\$'"
printf 'waiting 0 hook\n' >"$SD/B"
check "bar: a waiting lane is amber" bash -c "'$CCP' bar B | grep -q 'bg=colour214'"
mkdir -p "$LB/target/q2-scratch/drafts"; touch -t "$(ago -60)" "$LB/target/q2-scratch/drafts/STOP_QUESTIONS.md"
check "bar: a stop file newer than the launch makes the lane red, with STOP" bash -c "'$CCP' bar B | grep -q 'bg=colour196.* · STOP '"
touch -t "$(ago 86400)" "$LB/target/q2-scratch/drafts/STOP_QUESTIONS.md"
check "bar: an older stop file does not" bash -c "! '$CCP' bar B | grep -q STOP"
"$CCP" statusbar >/dev/null 2>&1
check "statusbar: the lanes' status line runs cc-parallel bar" bash -c "tmux show -t parallel -v status-left | grep -q 'bar #{window_name}'"
check "statusbar: the window list is hidden" test -z "$(tmux show -w -t parallel:B -v window-status-format 2>/dev/null)"
check "statusbar: an open wall shows only the time" test "$(tmux -L parallel-wall-A_C show -gv status-right)" = " %H:%M %d-%b-%y "

# macOS's tmux names a pane by its executable, and Claude Code's native installer runs a binary named by its version.
mkdir -p "$WORK/stub2"; cp "$(command -v bash)" "$WORK/stub2/2.1.31"
printf '#!/bin/sh\nexec "%s" "%s" "$@"\n' "$WORK/stub2/2.1.31" "$WORK/stub/claude.sh" >"$WORK/bin/claude-v"; chmod +x "$WORK/bin/claude-v"
tmux send-keys -t parallel:D "CC_PARALLEL_LANE=D '$WORK/bin/claude-v'" Enter
wait_for "[ \"\$(tmux display-message -p -t parallel:D '#{pane_current_command}')\" = 2.1.31 ]"
"$CCP" send D r1.md >/dev/null
check "a pane named by Claude Code's version counts as Claude Code" wait_for "grep -q 'Read $HOME/Downloads/r1.md whole' '$HOME/claude-input-D' 2>/dev/null"

# Paths: through a symlink, and with a space (the hooks' command must still be valid JSON for --settings).
ln -s "$CCP" "$WORK/bin/ccp-link"
check "a symlinked cc-parallel finds its real path" bash -c "'$WORK/bin/ccp-link' launch E t1.md opus task </dev/null >/dev/null 2>&1; grep -q '$CCP done T1' '$HOME/claude-args-E'"
mkdir -p "$WORK/with space/bin"; cp "$CCP" "$WORK/with space/bin/cc-parallel"
"$WORK/with space/bin/cc-parallel" launch F t1.md opus task </dev/null >/dev/null 2>&1
if command -v python3 >/dev/null 2>&1; then
  check "a path with a space gives valid --settings JSON" python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["hooks"]["Stop"][0]["hooks"][0]["command"].startswith(sys.argv[2])' "$(sed -n 4p "$HOME/claude-args-F")" "$WORK/with\\ space/bin/cc-parallel hook"
else
  check "a path with a space gives valid --settings JSON" grep -qF 'with\\ space/bin/cc-parallel hook idle' "$HOME/claude-args-F"
fi

# Systems: a native Windows shell is pointed to WSL2; WSL and macOS each get their own launcher.
fake_uname() { mkdir -p "$WORK/uname-$1"; printf '#!/bin/sh\ncase "$1" in -r) echo "%s" ;; *) echo "%s" ;; esac\n' "$3" "$2" >"$WORK/uname-$1/uname"; chmod +x "$WORK/uname-$1/uname"; }
fake_uname win MINGW64_NT-10.0-19045 3.4.10; fake_uname wsl Linux 5.15.167.4-microsoft-standard-WSL2; fake_uname mac Darwin 24.1.0
check "on a native Windows shell, cc-parallel points to WSL2" bash -c "! PATH='$WORK/uname-win:$PATH' '$CCP' status >/dev/null 2>'$WORK/win.err' && grep -q 'inside WSL2' '$WORK/win.err'"
check "on WSL, install-app gives a Windows Terminal command line" bash -c "PATH='$WORK/uname-wsl:$PATH' '$CCP' install-app | grep -q 'wsl.exe -d'"
check "on macOS, install-app makes a double-clickable .command" bash -c "PATH='$WORK/uname-mac:$PATH' '$CCP' install-app >/dev/null && [ -x '$HOME/Applications/Parallel Wall.command' ] && grep -q ' wall\$' '$HOME/Applications/Parallel Wall.command'"

check "nothing in the inbox was deleted: every file is in sent/ or rejected/" test "$(ls "$XDG_STATE_HOME/cc-parallel/relay/inbox"/*.txt 2>/dev/null | wc -l)" -eq 0

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
