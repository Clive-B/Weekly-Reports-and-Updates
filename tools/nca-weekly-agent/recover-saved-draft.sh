#!/usr/bin/env sh
set -eu

: "${APP_BASE_URL:?Set APP_BASE_URL}"
: "${AGENT_API_KEY:?Set AGENT_API_KEY}"

week_start="${1:?Pass the reporting week start}"
week_end="${2:?Pass the reporting week end}"

until curl -fsS "${APP_BASE_URL%/}/api/health" >/dev/null; do
  sleep 1
done

report="$(curl -fsS \
  -H "X-Agent-Key: ${AGENT_API_KEY}" \
  "${APP_BASE_URL%/}/api/reports/by-week?weekStart=${week_start}&weekEnd=${week_end}")"

payload="$(printf '%s' "${report}" | jq '{
  weekStart: .meta.weekStart,
  weekEnd: .meta.weekEnd,
  title: .meta.title,
  autoPublishIfValid: false,
  content: .content
}')"

result="$(curl -fsS \
  -H 'Content-Type: application/json' \
  -H "X-Agent-Key: ${AGENT_API_KEY}" \
  -X POST "${APP_BASE_URL%/}/api/agent/run" \
  -d "${payload}")"

printf '%s' "${result}" | jq '{
  id: .meta.id,
  status: .meta.status,
  publicationMode: .meta.publicationMode,
  validationIssueCount: (.validationIssues | length),
  priorityTrendCount: (.content.priorityTrends | length),
  referenceCount: (.content.references | length)
}'
