# Parallel on Windows (WSL2)

Parallel needs tmux, and tmux needs a Unix terminal. On Windows it therefore runs inside **WSL2** (the Windows
Subsystem for Linux), which gives you a real Ubuntu next to Windows. Claude Code runs there too. CI runs the test
suite inside WSL on every push.

## Install

1. **WSL2 and Ubuntu.** Open PowerShell as administrator:

   ```
   wsl --install -d Ubuntu
   ```

   Restart if Windows asks you to. Then open **Ubuntu** from the Start menu and create your Linux user.

2. **tmux and git**, in the Ubuntu terminal:

   ```
   sudo apt update
   ```
   ```
   sudo apt install -y tmux git
   ```

3. **Claude Code, inside Ubuntu.** Follow Anthropic's setup guide, <https://code.claude.com/docs/en/setup>. In its
   words: "Open your WSL distribution and run the Linux installer from the install instructions. You install and launch
   claude inside the WSL terminal, not from PowerShell or CMD." Sign in once by running `claude`.

4. **Parallel:** the Linux steps in the README (clone, link into `~/.local/bin`, `cc-parallel --version`).

## Where to keep things

- **Repositories go in your WSL home** (`~/projects/...`), not under `/mnt/c/...`. On a Windows drive, git and builds
  are many times slower and file permissions behave differently. `cc-parallel init` and `cc-parallel up` warn when a
  lane sits on a Windows drive.
- **Task files (`PROMPT_DIR`).** The default is `~/Downloads` inside Ubuntu. To have the relay read files you save
  from Windows, point it at your Windows Downloads folder in `~/.config/cc-parallel/config`:

  ```
  PROMPT_DIR="/mnt/c/Users/YOUR-WINDOWS-USER-NAME/Downloads"
  ```

  The relay polls, so a folder on the Windows drive works for these small files.
- **Line endings.** Clone Parallel inside Ubuntu. If a copy was made with Git for Windows, the repo's
  `.gitattributes` still keeps the script's LF endings; a script saved with Windows (CRLF) endings would fail with
  `$'\r': command not found`.

## The wall

- Use **Windows Terminal**; mouse clicks, `Ctrl-a z` (zoom a lane) and `Ctrl-a d` (close the wall) work there.
- `cc-parallel install-app` prints a command line for a Windows Terminal profile (Settings, then "Add a new
  profile"), for example:

  ```
  wsl.exe -d Ubuntu -- /home/you/parallel/bin/cc-parallel wall
  ```

## Notifications

`ON_CHANGE` runs inside Linux, where `notify-send` has no Windows desktop to show on. On WSL, `cc-parallel init`
writes a beep as the example instead:

```
ON_CHANGE='powershell.exe -NoProfile -Command "[console]::beep(880,300)"'
```

Any Windows notifier you can call from WSL works the same way.

## Git Bash, MSYS2 and Cygwin

These are not supported: Git Bash has no tmux, and Parallel is tested only inside WSL. `cc-parallel` stops in them
and points to this page.
