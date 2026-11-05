#!/bin/bash

# Run a chain of test scenarios in the background while the next steps of the same job run.
# GitHub Actions keeps background processes alive across the steps of a job.
#
# Usage:
#   background-scenarios.sh start <name>   Read a bash script from stdin and run it in the background.
#   background-scenarios.sh wait <name>    Wait for it, print its log and exit with its status.
#   background-scenarios.sh stop <name>    Kill it if it is still running (cancelled jobs).

set -e

ACTION="$1"
NAME="$2"

if [ -z "$ACTION" ] || [ -z "$NAME" ]; then
  echo "Usage: $0 start|wait|stop <name>"
  exit 1
fi

DIR="${RUNNER_TEMP:-/tmp}/background-scenarios"
SCRIPT="${DIR}/${NAME}.sh"
LOG="${DIR}/${NAME}.log"
PID="${DIR}/${NAME}.pid"
STATUS="${DIR}/${NAME}.status"

case "$ACTION" in
  start)
    mkdir -p "$DIR"
    rm -f "$STATUS"
    cat >"$SCRIPT"
    # setsid gives the chain its own process group, so stop can kill its children too.
    # The redirections detach it from the step, so the step ends right away.
    # The status is renamed into place, so wait never reads a half-written file.
    setsid bash -c 'bash -e "$1" >"$2" 2>&1; echo $? >"$3.tmp"; mv "$3.tmp" "$3"' _ "$SCRIPT" "$LOG" "$STATUS" </dev/null >/dev/null 2>&1 &
    echo $! >"$PID"
    echo "Started ${NAME} in the background"
    ;;
  wait)
    if [ ! -f "$PID" ]; then
      echo "${NAME} was not started, nothing to wait for"
      exit 0
    fi
    until [ -f "$STATUS" ]; do
      if ! kill -0 "$(cat "$PID")" 2>/dev/null && [ ! -f "$STATUS" ]; then
        echo "::error::${NAME} stopped without an exit status"
        cat "$LOG"
        exit 1
      fi
      sleep 5
    done
    status=$(cat "$STATUS")
    if [ "$status" = 0 ]; then
      echo "::group::${NAME} log"
      cat "$LOG"
      echo "::endgroup::"
    else
      cat "$LOG"
      echo "::error::${NAME} failed with exit code ${status}"
    fi
    exit "$status"
    ;;
  stop)
    if [ -f "$PID" ] && [ ! -f "$STATUS" ]; then
      echo "Stopping ${NAME}"
      kill -- "-$(cat "$PID")" 2>/dev/null || true
      cat "$LOG"
    fi
    ;;
  *)
    echo "Usage: $0 start|wait|stop <name>"
    exit 1
    ;;
esac
