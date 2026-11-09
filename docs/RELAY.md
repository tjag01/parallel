# The relay

The relay (`cc-parallel relay`) lets anything that can write a small file drive your lanes. That could be you from a
phone over a synced folder, a script, or a supervising agent. It does this without that writer ever getting a shell.
It runs in the `relay` window of the session (`cc-parallel up` starts it).

## The inbox

Its directory is `~/.local/state/cc-parallel/relay/`:

```
inbox/      one-line files to deliver
sent/       delivered files (moved here, never deleted)
rejected/   refused files (moved here; the reason is in log/relay.log)
panes/      <lane>.txt: the last 200 lines of each lane's screen, refreshed about every minute
log/        relay.log, heartbeat (written every poll), relay.pid
```

You rarely write inbox files by hand. `cc-parallel send` and `cc-parallel queue` write them for you.

### `<LANE>-<YYYYMMDDTHHMMSS>-relay.txt`
```
review-notes.md 3fa9c2e1
```
The fields are a file in `PROMPT_DIR` and the first 8 hex characters of its sha256. The relay types `RELAY_TEXT`
into the lane's running Claude Code session, with the file's full path filled in:

> Read /home/you/Downloads/review-notes.md whole (sha256 starts 3fa9c2e1) and follow it.

The file itself is never typed and never executed. The agent reads it, so the agent knows which version it was sent.

### `<LANE>-<YYYYMMDDTHHMMSS>-launch.txt`
```
fix-login-redirect.md opus task 9b01d4aa exit
```
The fields are the file, the model, the mode and the sha8, plus an optional `exit`.
- When the lane is at a shell, the relay types `cc-parallel launch <lane> <file> <model> <mode>`.
- With `exit`, a lane that is still running Claude Code gets `/exit` first, and the launch follows once the shell is
  back.
- Without `exit`, the launch waits until the lane is free.

## The checks

Every check runs before anything is typed. A file that fails one is moved to `rejected/`.

- The name matches the patterns above, and the lane is one of `LANES`.
- It is a regular file (not a symlink), under 1 KB, with exactly one line.
- It holds only letters, digits, spaces and `. _ -`: no quotes, no `$`, `;`, `|`, `&`, `>`, `<` or backticks.
- The named file exists in `PROMPT_DIR`, and its sha256 starts with the given 8 characters.
- The model is in `MODELS`, and the mode is `task`, `sprint`, `ground` or `resume`.
- A relay line goes only to a lane whose pane is running Claude Code. Otherwise it is held and retried.
- A launch goes only to a lane at its shell, or after `/exit` when asked.

Before it types, the relay clears the lane's input line (Ctrl-U), so a half-typed draft or a ghost suggestion in the
prompt never merges with the delivered sentence.

## Stopping and starting

- Ctrl-C in the relay window is ignored on purpose, so a stray keystroke cannot stop it. Stop it with
  `kill $(cat ~/.local/state/cc-parallel/relay/log/relay.pid)`.
- Every start and exit is logged, so a supervisor can tell a stopped relay (a stale `heartbeat`) from a quiet one.
- `cc-parallel up` starts it again if it is not running.

## Lane states

Each launch installs five hooks through `--settings`:

| Hook | State |
|---|---|
| `UserPromptSubmit` | `working` |
| `PreToolUse` | `working` |
| `Notification` | `waiting` |
| `Stop` | `idle` |
| `SessionEnd` | `ended` |

The relay logs every change, and runs `ON_CHANGE` with `LANE`, `STATE` and `EVENT` set whenever a lane turns
`idle` or `waiting`. That is the moment a supervisor should look at the lane, so it is the one worth a notification.
