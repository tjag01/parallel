#!/usr/bin/env bash
# tests/bsd-smoke.sh: run tests/smoke.sh with a PATH of BSD-style tools, as on macOS, so a GNU-only flag fails on
# Linux before it reaches a Mac. Each shim refuses the GNU-only forms that macOS refuses and hands the rest to the
# real tool; GNU-only tools (sha256sum, timeout, flock, tac, realpath, ...) are simply absent.
# An approximation: the macOS job in .github/workflows/test.yml is the real check. Run from the repo root:
#   bash tests/bsd-smoke.sh
set -uo pipefail
ROOT="$(cd -P "$(dirname "$0")/.." && pwd)"
SHIM="$(mktemp -d "${TMPDIR:-/tmp}/ccp-bsd.XXXXXX")"
trap '[ -n "${KEEP:-}" ] && echo "kept $SHIM"' EXIT

# Tools macOS has, linked as they are.
for t in bash sh tmux git cat cut tr awk head tail mkdir mv cp ln chmod rm sleep env id ps df du basename dirname \
         uname mktemp seq sort ls tee kill true false python3 cmp diff; do
  p="$(command -v "$t")" && ln -s "$p" "$SHIM/$t"
done

shim() { # shim NAME REAL-TOOL BODY: a bash script; BODY sees the real tool as $R
  local real; real="$(command -v "$2")" || { echo "bsd-smoke: no $2 to wrap" >&2; exit 2; }
  printf '#!%s\nR=%q\n%s\n' "$(command -v bash)" "$real" "$3" >"$SHIM/$1"; chmod +x "$SHIM/$1"
}
refuse='refuse() { echo "$(basename "$0"): illegal option -- $1 (GNU-only; macOS has no such flag)" >&2; exit 1; }'

# stat: no -c; -f %m (mtime) and -f %z (size) are BSD's, emulated.
shim stat stat "$refuse"'
for a in "$@"; do case "$a" in -c*|--format*|--printf*) refuse c ;; esac; done
if [ "${1:-}" = -f ]; then f="$2"; shift 2; [ "${1:-}" = -- ] && shift
  case "$f" in %m) exec "$R" -c %Y -- "$@" ;; %z) exec "$R" -c %s -- "$@" ;; esac; fi
echo "stat (bsd shim): unsupported form: $*" >&2; exit 1'
# readlink: no -f, -e or -m (macOS before 12.3).
shim readlink readlink "$refuse"'
for a in "$@"; do case "$a" in -f|-e|-m|-[a-z]*f*|--canon*) refuse f ;; esac; done
exec "$R" "$@"'
# shasum -a 256 is macOS's sha256sum.
shim shasum sha256sum '[ "${1:-}" = -a ] && [ "${2:-}" = 256 ] || { echo "shasum (bsd shim): only -a 256" >&2; exit 1; }
shift 2; [ "${1:-}" = -- ] && shift; exec "$R" -- "$@"'
# date: no -d (BSD reads -r SECONDS instead) and no %N.
shim date date "$refuse"'
a=(); while [ $# -gt 0 ]; do case "$1" in
  -d|--date*) refuse d ;;
  -r) [[ "${2:-}" =~ ^-?[0-9]+$ ]] || refuse r; a+=(-d "@$2"); shift 2; continue ;;
  +*%N*) refuse N ;;
  *) a+=("$1") ;; esac; shift; done
exec "$R" "${a[@]}"'
# touch: -d takes only an ISO time (no "3 hours ago").
shim touch touch "$refuse"'
for ((i = 1; i <= $#; i++)); do [ "${!i}" = -d ] && { j=$((i + 1)); [[ "${!j}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]] || refuse d; }; done
exec "$R" "$@"'
# sed: -i needs its own suffix argument; no -r, no long options.
shim sed sed "$refuse"'
for a in "$@"; do case "$a" in -i|-r|-z|--*) refuse "${a#-}" ;; esac; done
exec "$R" "$@"'
# find: no -printf, -newermt or -regextype.
shim find find "$refuse"'
for a in "$@"; do case "$a" in -printf|-fprintf|-newermt|-regextype) refuse "${a#-}" ;; esac; done
exec "$R" "$@"'
# grep: no -P.
shim grep grep "$refuse"'
for a in "$@"; do case "$a" in -P|--perl-regexp|-[a-zA-Z]*P*) refuse P ;; esac; done
exec "$R" "$@"'
# xargs: no -r.
shim xargs xargs "$refuse"'
for a in "$@"; do case "$a" in -r|--no-run-if-empty) refuse r ;; esac; done
exec "$R" "$@"'
# wc: BSD pads its counts with spaces.
shim wc wc '"$R" "$@" | awk "{ printf \"%8d\", \$1; for (i = 2; i <= NF; i++) printf \" %s\", \$i; printf \"\\n\" }"'

echo "bsd-smoke: tools in $SHIM"
PATH="$SHIM" "$SHIM/bash" "$ROOT/tests/smoke.sh"
