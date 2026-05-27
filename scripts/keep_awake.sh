#!/usr/bin/env bash
#
# keep_awake.sh — start/stop a scoped macOS keep-awake assertion via caffeinate.
#
# Usage:
#   keep_awake.sh start [timeout_seconds]   # default cap: 3600s (1 hour)
#   keep_awake.sh stop
#   keep_awake.sh status
#
# Design notes:
# - Uses `caffeinate -i -s -t <timeout>` so the assertion ALWAYS has a hard
#   cap. Even if `stop` is never called (crash, abandoned session), the Mac
#   regains the ability to sleep when the timeout elapses. This protects the
#   user's battery from a runaway keep-awake.
# - Records the caffeinate PID in a temp file so `stop` can reliably terminate
#   the exact process this script started, without killing unrelated
#   caffeinate processes the user may be running.
# - `-i` blocks idle sleep; `-s` blocks sleep on AC power (the flag that helps
#   with a closed lid while plugged in). The display is intentionally NOT kept
#   on (no `-d`), since a closed-lid run wants the screen off.

set -euo pipefail

PIDFILE="${TMPDIR:-/tmp}/claude_keep_awake.pid"

is_running() {
  [[ -f "$PIDFILE" ]] || return 1
  local pid
  pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  [[ -n "${pid}" ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

cmd="${1:-}"

case "$cmd" in
  start)
    if [[ "$(uname)" != "Darwin" ]]; then
      echo "keep-awake: this skill is macOS-only (found $(uname)). On Windows use powercfg instead." >&2
      exit 1
    fi

    if is_running; then
      echo "keep-awake: already active (pid $(cat "$PIDFILE")). Call 'stop' first if you want to restart."
      exit 0
    fi

    timeout="${2:-3600}"
    if ! [[ "$timeout" =~ ^[0-9]+$ ]]; then
      echo "keep-awake: timeout must be a whole number of seconds (got '$timeout')." >&2
      exit 1
    fi

    # Start caffeinate detached; -t gives it a hard safety cap.
    caffeinate -i -s -t "$timeout" &
    echo $! > "$PIDFILE"

    mins=$(( timeout / 60 ))
    echo "keep-awake: ON (pid $(cat "$PIDFILE")), safety cap ${timeout}s (~${mins} min)."
    echo "keep-awake: remember to plug in for a closed-lid run, and call 'stop' when the task finishes."
    ;;

  stop)
    if is_running; then
      pid="$(cat "$PIDFILE")"
      kill "$pid" 2>/dev/null || true
      rm -f "$PIDFILE"
      echo "keep-awake: OFF (released pid ${pid}). The Mac will sleep normally again."
    else
      rm -f "$PIDFILE" 2>/dev/null || true
      echo "keep-awake: nothing to stop — no active assertion from this skill."
    fi
    ;;

  status)
    if is_running; then
      echo "keep-awake: ACTIVE (pid $(cat "$PIDFILE"))."
    else
      echo "keep-awake: inactive."
    fi
    # Surface any other system-wide assertions for debugging context.
    if [[ "$(uname)" == "Darwin" ]] && command -v pmset >/dev/null 2>&1; then
      echo "--- pmset assertions (system-wide) ---"
      pmset -g assertions 2>/dev/null | grep -E "PreventUserIdleSystemSleep|PreventSystemSleep" || true
    fi
    ;;

  *)
    echo "Usage: keep_awake.sh {start [timeout_seconds] | stop | status}" >&2
    exit 1
    ;;
esac
