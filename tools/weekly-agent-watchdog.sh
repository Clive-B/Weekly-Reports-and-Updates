#!/usr/bin/env bash
set -euo pipefail

: "${APP_BASE_URL:?Set APP_BASE_URL, for example http://localhost:8080}"
: "${AGENT_API_KEY:?Set AGENT_API_KEY to match Agent__ApiKey}"
: "${AGENT_GENERATE_COMMAND:?Set AGENT_GENERATE_COMMAND to a command that writes the /api/agent/run JSON payload to stdout}"

WATCHDOG_RESPONSE="$(
  curl -fsS \
    -H "X-Agent-Key: ${AGENT_API_KEY}" \
    -H "Content-Type: application/json" \
    -X POST \
    "${APP_BASE_URL%/}/api/agent/watchdog-check" \
    -d '{}'
)"

SHOULD_RUN="$(printf '%s' "${WATCHDOG_RESPONSE}" | jq -r '.shouldRunAgent')"
WEEK_START="$(printf '%s' "${WATCHDOG_RESPONSE}" | jq -r '.weekStart')"
WEEK_END="$(printf '%s' "${WATCHDOG_RESPONSE}" | jq -r '.weekEnd')"
MESSAGE="$(printf '%s' "${WATCHDOG_RESPONSE}" | jq -r '.message')"

printf 'Watchdog check: %s to %s - %s\n' "${WEEK_START}" "${WEEK_END}" "${MESSAGE}"

if [[ "${SHOULD_RUN}" != "true" ]]; then
  exit 0
fi

PAYLOAD="$(
  WEEK_START="${WEEK_START}" WEEK_END="${WEEK_END}" bash -c "${AGENT_GENERATE_COMMAND}"
)"

printf '%s' "${PAYLOAD}" | jq -e '.content and (.autoPublishIfValid != null)' >/dev/null

curl -fsS \
  -H "X-Agent-Key: ${AGENT_API_KEY}" \
  -H "Content-Type: application/json" \
  -X POST \
  "${APP_BASE_URL%/}/api/agent/run" \
  -d "${PAYLOAD}" >/dev/null

printf 'Agent fallback submitted for %s to %s.\n' "${WEEK_START}" "${WEEK_END}"
