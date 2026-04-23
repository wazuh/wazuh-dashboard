#!/bin/bash
set -e

LOG_FILE="/tmp/osd-start.log"

echo "Starting yarn start --no-base-path to warm up optimizer cache..."
touch "$LOG_FILE"
yarn start --no-base-path --config /home/node/warmup-opensearch_dashboards.yml > "$LOG_FILE" 2>&1 &
OSD_PID=$!

# Stream log to stdout so Docker shows progress
tail -f "$LOG_FILE" &
TAIL_PID=$!

echo "Waiting for @osd/optimizer to complete..."
until grep -q '\[success\]\[@osd/optimizer\]' "$LOG_FILE" 2>/dev/null; do
  sleep 5
  if ! kill -0 $OSD_PID 2>/dev/null; then
    kill $TAIL_PID 2>/dev/null
    echo "ERROR: yarn start exited before optimizer completed" >&2
    tail -n 100 "$LOG_FILE" >&2
    exit 1
  fi
done

echo "Optimizer completed! Stopping service..."
kill $TAIL_PID 2>/dev/null
kill $OSD_PID 2>/dev/null
wait $OSD_PID 2>/dev/null || true
echo "Service stopped. Optimizer cache is ready."
