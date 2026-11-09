# Parallel for Claude Code

Run several Claude Code agents at once, each in its own git worktree ("lane"), all visible on one screen, with a safe
inbox that lets a supervisor (you, from any device, or another agent) hand each lane its next task.

```
┌ lane A ───────────────┬ lane B ───────────────┬ lane C ───────────────┐
│ ✻ Running tests…      │ ● Step 2 committed    │ ❯ waiting for you     │
├ lane D ───────────────┼ lane E ───────────────┼ lane F ───────────────┤
│ ✻ Reading files…      │ idle 4m               │ ✻ Writing report…     │
└───────────────────────┴───────────────────────┴───────────────────────┘
 parallel · A B C D E F      click to focus · Ctrl-a z zoom · Ctrl-a d close
```

One bash script (`cc-parallel`), tmux and git. No daemon, no account, no network calls of its own.

> Parallel is an independent project. It is not made, endorsed or supported by Anthropic. "Claude" and "Claude
> Code" are Anthropic's trademarks.

## What it does

- **Lanes:** `cc-parallel init --lanes 8` creates one git worktree per lane. Use as many lanes as your machine and
  your plan can carry (1–26 by letter, or any names you like with `--names`).
- **One tmux session:** a window per lane plus a `relay` window. Detach, close the laptop lid, reattach later.
- **The wall:** `cc-parallel wall` tiles every lane on one screen, up to 9 per wall. You can open more walls, or one
  for a subset: `cc-parallel wall A C E`. It runs on its own tmux server, so it never disturbs the lanes.
- **State from hooks:** each launch passes Claude Code hooks through `--settings`, nothing written into your
  settings files. Each lane reports `working`, `waiting` (Claude Code needs you), `idle` (its turn is over) or
  `ended`.
  - `cc-parallel status` shows all lanes at a glance.
  - `ON_CHANGE` runs a command whenever a lane turns idle or waiting, for example a desktop notification.
- **The relay:** a watcher that reads one-line files from an inbox and either types a fixed, checked sentence into a
  lane's running session ("Read <file> whole (sha256 starts …) and follow it.") or launches a task in a free lane.
  It never executes what a file says, and every file is checked first (see [docs/RELAY.md](docs/RELAY.md)). This is
  what lets work continue while you are away. A supervisor writes the next instruction file, and the relay delivers
  it.
- **Kickoff templates:** `task`, `sprint`, `ground` (read-only investigation) and `resume`. Each is a text file you
  can edit, sent as the session's first prompt.

## Install

```
git clone https://github.com/tjag01/parallel ~/parallel
```
```
ln -s ~/parallel/bin/cc-parallel ~/.local/bin/cc-parallel
```

You need bash 4+, tmux 3+, git, and Claude Code installed and signed in (`claude` on your PATH). It is tested on
Linux, and should work on macOS with Homebrew bash.

## Quick start

```
cc-parallel init --repo ~/projects/myapp --lanes 6
```
```
cc-parallel up
```
```
cc-parallel wall
```

Write a task file into `~/Downloads` (or set `PROMPT_DIR`), then start it in a lane:

```
cc-parallel launch B fix-login-redirect.md
```

Or queue it, and the relay starts it when lane B is free:

```
cc-parallel queue B fix-login-redirect.md opus task
```

Queue the next task to start the moment the current one is finished, with no one at the keyboard:

```
cc-parallel queue B next-task.md opus sprint --after-done
```

The kickoff templates tell each agent to run `cc-parallel done` as its last action, but only when its task has fully
landed. A lane that stops for a decision never runs it, so its follow-on waits for you.

Hand a running lane a follow-up file (a review, a ruling, a correction):

```
cc-parallel send B review-notes.md
```

See every lane's state:

```
cc-parallel status
```

## Configuration

`~/.config/cc-parallel/config` is plain bash, and `init` writes it. These are the settings you will most likely
change:

| Setting | Default | |
|---|---|---|
| `LANES` | `"A B C D"` | Lane names, as many as you want. Add one, then re-run `init` and `up`. |
| `REPO` | — | The main checkout. The first lane runs there; the others in `$REPO-lanes/<lane>`. |
| `PROMPT_DIR` | `~/Downloads` | Where task and follow-up files are read from. |
| `MODELS`, `DEFAULT_MODEL` | `opus sonnet`, `opus` | What a launch may name. |
| `CLAUDE_FLAGS` | empty | Extra flags for every launch. See "Permissions" below. |
| `ON_CHANGE` | empty | For example `notify-send "lane $LANE is $STATE"`. |
| `LANE_DIR_<X>` | — | Put one lane anywhere. |
| `GC_GLOBS` | empty | Build caches the relay may remove, as globs under each lane, e.g. `target/*-scratch/clone/target`. It runs after a lane says done, and whenever free disk falls below `GC_MIN_FREE_GB` (100). It never touches a lane's current task, anything used in the last `GC_MIN_AGE_MIN` (60) minutes, or a lane's own `target/`. `cc-parallel gc --dry-run` shows what it would remove. |

The kickoff templates are in `~/.config/cc-parallel/kickoff/*.txt`, with `{path}`, `{file}`, `{lane}` and `{code}`
filled in. The code is the first word of the task file's `# ` title line, so `# T12 · Fix login` gives `T12`.

## Permissions: read this

By default each lane asks for permission as Claude Code normally does. The `waiting` state and `ON_CHANGE` tell you
which lane is asking.

You may set `CLAUDE_FLAGS="--dangerously-skip-permissions"` so lanes run unattended. That gives every agent full
command access inside its worktree and beyond. Do it only on a machine and in repositories where you accept that
risk, and give your task files hard limits, for example "never delete", "no network" or "stop and report on
anything unexpected". [docs/SUPERVISOR.md](docs/SUPERVISOR.md) describes the discipline that kept this safe in
practice.

## How it compares

Running agents in parallel worktrees is a well-trodden idea, and Parallel borrows from the tools that made it popular:

- worktree-per-agent and tmux sessions, as in Claude Squad, workmux, dmux and cmux;
- per-agent status from Claude Code hooks, as in workmux's status plugin and Claude Code's own agent view;
- a single dashboard of all sessions, as in Conductor and other desktop session managers.

**What Parallel adds is the supervised relay.** It is a narrow, checked channel through which a supervisor drives
the lanes, so a long queue of work keeps moving without anyone at the keyboard. The method behind it (sprint files,
verified assumptions, halt-and-report, rulings) is written up in [docs/SUPERVISOR.md](docs/SUPERVISOR.md).

## Tests

```
bash tests/smoke.sh
```

This runs an end-to-end check against a stub `claude` in a throwaway HOME and tmux server. It covers six lanes:
launch, send, the rejections, exit-then-launch, the hooks, `ON_CHANGE`, status, and the walls.

## Licence

MIT. See [LICENSE](LICENSE).
