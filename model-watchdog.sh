#!/bin/bash
# Refresh the local model catalog only. This service never controls cmux or CLI processes.
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
umask 077

MODEL_STATE_DIR="$HOME/.config/cmux-remote"
MODEL_CATALOG_HELPER="$MODEL_STATE_DIR/model-catalog.py"
MODEL_PYTHON=/usr/bin/python3
MODEL_REFRESH_STAMP="$MODEL_STATE_DIR/models.last-refresh"
MODEL_ATTEMPT_STAMP="$MODEL_STATE_DIR/models.last-attempt"
MODEL_REQUEST_FILE="$MODEL_STATE_DIR/agent-models-refresh"
MODEL_REQUEST_RECEIPT="$MODEL_STATE_DIR/models.last-request"
MODEL_STATUS_FILE="$MODEL_STATE_DIR/model-watchdog.status"
MODEL_LOG="$MODEL_STATE_DIR/model-watchdog.log"
MODEL_REFRESH_INTERVAL=300
MODEL_RETRY_INTERVAL=60

model_status() {
  local previous=""
  [ -f "$MODEL_STATUS_FILE" ] && previous=$(cat "$MODEL_STATUS_FILE" 2>/dev/null)
  printf '%s\n' "$1" > "$MODEL_STATUS_FILE"
  if [ "$previous" != "$1" ]; then
    printf '%s %s\n' "$(date '+%F %T')" "$1" >> "$MODEL_LOG"
  fi
}

model_refresh_due() {
  local now="$1" stamp interval age
  interval=$MODEL_RETRY_INTERVAL
  if [ -f "$MODEL_STATUS_FILE" ] && [ "$(cat "$MODEL_STATUS_FILE" 2>/dev/null)" = ok ]; then
    interval=$MODEL_REFRESH_INTERVAL
  fi
  stamp=$(cat "$MODEL_ATTEMPT_STAMP" 2>/dev/null || true)
  case "$stamp" in ''|*[!0-9]*) return 0 ;; esac
  age=$((now - stamp))
  [ "$age" -lt 0 ] || [ "$age" -ge "$interval" ]
}

refresh_models() {
  local now request previous_request
  mkdir -p "$MODEL_STATE_DIR" || return 1
  now=$(date +%s)
  request=$(head -c 128 "$MODEL_REQUEST_FILE" 2>/dev/null || true)
  previous_request=$(head -c 128 "$MODEL_REQUEST_RECEIPT" 2>/dev/null || true)
  if [ "${1:-}" != --force ] && [ "$request" = "$previous_request" ] && ! model_refresh_due "$now"; then
    return 0
  fi
  printf '%s\n' "$now" > "$MODEL_ATTEMPT_STAMP" || return 1
  # Acknowledge this request without deleting a newer request written during the probe.
  printf '%s' "$request" > "$MODEL_REQUEST_RECEIPT" || return 1
  if [ ! -f "$MODEL_CATALOG_HELPER" ] || [ ! -x "$MODEL_PYTHON" ]; then
    model_status helper-unavailable
    return 1
  fi
  # The helper bounds and cleans up its own isolated probes. Never log native CLI output.
  if "$MODEL_PYTHON" "$MODEL_CATALOG_HELPER" --config-dir "$MODEL_STATE_DIR" >/dev/null 2>&1; then
    printf '%s\n' "$now" > "$MODEL_REFRESH_STAMP"
    model_status ok
    return 0
  fi
  model_status refresh-failed
  return 1
}

model_tick_delay() {
  local elapsed=$(( $2 - $1 ))
  # Keep a minute cadence even when the isolated probes take most of a tick.
  if [ "$elapsed" -lt 0 ]; then printf '60\n'
  elif [ "$elapsed" -ge 60 ]; then printf '1\n'
  else printf '%s\n' "$((60 - elapsed))"; fi
}

model_watchdog_tick() {
  local started
  started=$(date +%s)
  refresh_models
  sleep "$(model_tick_delay "$started" "$(date +%s)")"
}

model_watchdog_main() {
  case "${1:-}" in
    --loop) while :; do model_watchdog_tick; done ;;
    --once) refresh_models --force ;;
    --status)
      if [ -f "$MODEL_STATUS_FILE" ]; then cat "$MODEL_STATUS_FILE"; else printf 'not-run\n'; fi
      if [ -f "$MODEL_REFRESH_STAMP" ]; then
        printf 'last-success-unix: '; cat "$MODEL_REFRESH_STAMP"
      fi
      ;;
    *) printf 'Usage: model-watchdog.sh --loop | --once | --status\n' >&2; return 2 ;;
  esac
}

if [ "${CMUX_MODEL_WATCHDOG_LIB:-0}" != 1 ]; then model_watchdog_main "$@"; fi
