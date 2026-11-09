#!/usr/bin/env bash
# tests/smoke.sh: an end-to-end check of cc-parallel with a stub `claude`, in a throwaway HOME and tmux server.
# Needs tmux and git. Run from the repo root: bash tests/smoke.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CCP="$ROOT/bin/cc-parallel"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ccp-smoke.XXXXXX")"
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
finish() { tmux kill-server 2>/dev/null; for s in "$TMUX_TMPDIR"/tmux-*/*; do tmux -S "$s" kill-server 2>/dev/null; done; }
trap finish EXIT; [ -n "${KEEP:-}" ] && trap "finish; echo kept \$WORK" EXIT

# A stub claude: records its arguments, then echoes every line it is sent; "/exit" ends it.
cat >"$WORK/bin/claude" <<'EOF'
#!/bin/bash
# tmux names a pane's command from argv[0], so re-exec with argv[0] = claude, as the real binary has.
[ -z "${STUBBED:-}" ] && STUBBED=1 exec -a claude /bin/bash "$0" "$@"
printf '%s\n' "$@" >"$HOME/claude-args-$CC_PARALLEL_LANE"
while IFS= read -r line; do
  printf '%s\n' "$line" >>"$HOME/claude-input-$CC_PARALLEL_LANE"
  [ "$line" = "/exit" ] && exit 0
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

printf '# T1 · first task\nDo the thing.\n' >"$HOME/Downloads/t1.md"
"$CCP" queue A t1.md opus task >/dev/null
check "a queued launch starts Claude Code in lane A" wait_for "[ -f '$HOME/claude-args-A' ]"
check "the launch passes the model" grep -qx opus "$HOME/claude-args-A"
check "the launch passes the hooks through --settings" grep -q '"Stop"' "$HOME/claude-args-A"
check "the kickoff names the file and the code" grep -q "\[T1 · lane A\] Read $HOME/Downloads/t1.md" "$HOME/claude-args-A"
wait_for "[ \"\$(tmux display-message -p -t parallel:A '#{pane_current_command}')\" = claude ]"

printf 'A ruling.\n' >"$HOME/Downloads/r1.md"
"$CCP" send A r1.md >/dev/null
check "send types the checked line into the running session" wait_for "grep -q 'Read $HOME/Downloads/r1.md whole (sha256 starts' '$HOME/claude-input-A' 2>/dev/null"

printf 'r1.md deadbeef\n' >"$XDG_STATE_HOME/cc-parallel/relay/inbox/A-20260101T000000-relay.txt"
check "a relay file with the wrong sha256 is rejected" wait_for "[ -f '$XDG_STATE_HOME/cc-parallel/relay/rejected/A-20260101T000000-relay.txt' ]"
printf 'r1.md 12345678; rm -rf ~\n' >"$XDG_STATE_HOME/cc-parallel/relay/inbox/A-20260101T000001-relay.txt"
check "a relay file with shell characters is rejected" wait_for "[ -f '$XDG_STATE_HOME/cc-parallel/relay/rejected/A-20260101T000001-relay.txt' ]"
printf 'r1.md %s\n' "$(sha256sum "$HOME/Downloads/r1.md" | cut -c1-8)" >"$XDG_STATE_HOME/cc-parallel/relay/inbox/Q-20260101T000002-relay.txt"
check "a relay file for an unknown lane is rejected" wait_for "[ -f '$XDG_STATE_HOME/cc-parallel/relay/rejected/Q-20260101T000002-relay.txt' ]"

printf '# T2 · second task\n' >"$HOME/Downloads/t2.md"
"$CCP" queue A t2.md sonnet task --exit >/dev/null
check "--exit sends /exit to a busy lane, then launches" wait_for "grep -qx sonnet '$HOME/claude-args-A' 2>/dev/null" 80
check "the /exit reached the session" grep -qx /exit "$HOME/claude-input-A"

sed -i "s|^# ON_CHANGE=.*|ON_CHANGE='echo \"\$LANE \$STATE\" >>\"\$HOME/changes\"'|" "$XDG_CONFIG_HOME/cc-parallel/config"
tmux send-keys -t parallel:relay C-\\ ; sleep 1
kill "$(cat "$XDG_STATE_HOME/cc-parallel/relay/log/relay.pid")" 2>/dev/null; sleep 1
tmux send-keys -t parallel:relay "$CCP relay" Enter
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

check "nothing in the inbox was deleted: every file is in sent/ or rejected/" test "$(ls "$XDG_STATE_HOME/cc-parallel/relay/inbox"/*.txt 2>/dev/null | wc -l)" -eq 0

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
