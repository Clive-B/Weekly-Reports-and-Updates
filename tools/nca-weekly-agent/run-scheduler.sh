#!/usr/bin/env bash
set -euo pipefail

: "${APP_BASE_URL:?Set APP_BASE_URL}"
: "${AGENT_API_KEY:?Set AGENT_API_KEY}"
if [[ -z "${OPENAI_PROXY_URL:-}" && -z "${OPENAI_API_KEY:-}" ]]; then
  printf 'Set OPENAI_PROXY_URL or OPENAI_API_KEY.\n' >&2
  exit 1
fi

SCHEDULER_STATE_DIR="${SCHEDULER_STATE_DIR:-/state}"
SCHEDULER_POLL_SECONDS="${SCHEDULER_POLL_SECONDS:-300}"
WATCHDOG_COMMAND="${WATCHDOG_COMMAND:-/usr/local/bin/weekly-agent-watchdog.sh}"

mkdir -p "${SCHEDULER_STATE_DIR}"
printf 'Weekly report agent scheduler started; timezone=Africa/Accra, weekday run time=08:00.\n'

while true; do
  today="$(TZ=Africa/Accra date +%F)"
  weekday="$(TZ=Africa/Accra date +%u)"
  hour="$(TZ=Africa/Accra date +%H)"
  last_attempt="$(cat "${SCHEDULER_STATE_DIR}/last-attempt" 2>/dev/null || true)"

  touch "${SCHEDULER_STATE_DIR}/scheduler-alive"

  if (( 10#${weekday} <= 5 && 10#${hour} >= 8 )) && [[ "${last_attempt}" != "${today}" ]]; then
    if [[ -n "${OPENAI_PROXY_URL:-}" ]]; then
      provider_status_url="${APP_BASE_URL%/}/api/agent/provider-key/status"
      provider_ready="$(curl --silent --show-error --max-time 30 -H "X-Agent-Key: ${AGENT_API_KEY}" "${provider_status_url}" | jq -r '.configured // false' 2>/dev/null || true)"
      if [[ "${provider_ready}" != "true" ]]; then
        printf 'Waiting for an administrator to configure the provider API key.\n'
        sleep "${SCHEDULER_POLL_SECONDS}"
        continue
      fi
    fi

    # Record the attempt before starting so a restart cannot duplicate a paid run.
    printf '%s\n' "${today}" >"${SCHEDULER_STATE_DIR}/last-attempt"
    printf 'Starting scheduled watchdog for %s.\n' "${today}"

    if "${WATCHDOG_COMMAND}"; then
      printf '%s\n' "${today}" >"${SCHEDULER_STATE_DIR}/last-success"
      printf 'Scheduled watchdog completed for %s.\n' "${today}"
    else
      status=$?
      printf 'Scheduled watchdog failed for %s with status %s; it will retry on the next weekday.\n' "${today}" "${status}" >&2
    fi
  fi

  sleep "${SCHEDULER_POLL_SECONDS}"
done
