#!/usr/bin/env bash
set -euo pipefail

# Generates the complete JSON request consumed by POST /api/agent/run.
# Normal output is JSON only; diagnostics are written to stderr.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_PATH="${NCA_AGENT_SCHEMA_PATH:-${SCRIPT_DIR}/weekly-report-content.schema.json}"
OPENAI_API_BASE="${OPENAI_API_BASE:-https://api.openai.com/v1}"
OPENAI_MODEL="${OPENAI_MODEL:-gpt-5.5}"
OPENAI_REASONING_EFFORT="${OPENAI_REASONING_EFFORT:-medium}"
OPENAI_TIMEOUT_SECONDS="${OPENAI_TIMEOUT_SECONDS:-300}"
AGENT_AUTO_PUBLISH="${AGENT_AUTO_PUBLISH:-false}"

die() {
  printf 'generate-weekly-report: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_command jq
require_command date

[[ -r "${SCHEMA_PATH}" ]] || die "schema not readable: ${SCHEMA_PATH}"
jq -e . "${SCHEMA_PATH}" >/dev/null || die "schema is not valid JSON: ${SCHEMA_PATH}"

calculate_previous_week() {
  local today weekday days_since_monday this_monday
  today="${TODAY:-$(TZ=Africa/Accra date +%F)}"
  weekday="$(TZ=Africa/Accra date -d "${today}" +%u 2>/dev/null)" || die "invalid TODAY value: ${today}"
  days_since_monday=$((weekday - 1))
  this_monday="$(TZ=Africa/Accra date -d "${today} - ${days_since_monday} days" +%F)"
  WEEK_START="$(TZ=Africa/Accra date -d "${this_monday} - 7 days" +%F)"
  WEEK_END="$(TZ=Africa/Accra date -d "${WEEK_START} + 4 days" +%F)"
}

if [[ -z "${WEEK_START:-}" && -z "${WEEK_END:-}" ]]; then
  calculate_previous_week
elif [[ -z "${WEEK_START:-}" || -z "${WEEK_END:-}" ]]; then
  die "WEEK_START and WEEK_END must be supplied together"
fi

START_NORMALIZED="$(date -d "${WEEK_START}" +%F 2>/dev/null)" || die "invalid WEEK_START: ${WEEK_START}"
END_NORMALIZED="$(date -d "${WEEK_END}" +%F 2>/dev/null)" || die "invalid WEEK_END: ${WEEK_END}"
[[ "${START_NORMALIZED}" == "${WEEK_START}" ]] || die "WEEK_START must use YYYY-MM-DD"
[[ "${END_NORMALIZED}" == "${WEEK_END}" ]] || die "WEEK_END must use YYYY-MM-DD"

EXPECTED_END="$(date -d "${WEEK_START} + 4 days" +%F)"
[[ "${WEEK_END}" == "${EXPECTED_END}" ]] || die "WEEK_END must be four days after WEEK_START"
[[ "$(date -d "${WEEK_START}" +%u)" == "1" ]] || die "WEEK_START must be a Monday"
[[ "$(date -d "${WEEK_END}" +%u)" == "5" ]] || die "WEEK_END must be a Friday"

start_day="$(date -d "${WEEK_START}" +%-d)"
end_day="$(date -d "${WEEK_END}" +%-d)"
start_month="$(date -d "${WEEK_START}" +%B)"
end_month="$(date -d "${WEEK_END}" +%B)"
start_year="$(date -d "${WEEK_START}" +%Y)"
end_year="$(date -d "${WEEK_END}" +%Y)"

if [[ "${start_year}" != "${end_year}" ]]; then
  REPORTING_WEEK="${start_day} ${start_month} ${start_year} - ${end_day} ${end_month} ${end_year}"
elif [[ "${start_month}" != "${end_month}" ]]; then
  REPORTING_WEEK="${start_day} ${start_month} - ${end_day} ${end_month} ${end_year}"
else
  REPORTING_WEEK="${start_day} - ${end_day} ${end_month} ${end_year}"
fi

REPORT_TITLE="${REPORT_TITLE:-Weekly Emerging Technologies & Trends Report: ${REPORTING_WEEK}}"

read -r -d '' SYSTEM_PROMPT <<'PROMPT' || true
You prepare evidence-led weekly emerging technologies and telecommunications reports for Ghana's National Communications Authority Innovation & Policy unit.

Use web search and include only developments that occurred or were officially announced during the supplied Monday-Friday reporting window. Prioritize primary and authoritative sources: regulators, governments, standards bodies, cybersecurity agencies, telecom operators, established technology vendors, and recognized multilateral institutions. Give priority to Ghana, Africa, ECOWAS, the African Union, and ITU-relevant signals while still including material global developments.

Every claimed trend must be supported by a reference URL that you actually found. Use at least five distinct HTTPS source URLs. Do not invent URLs, titles, dates, quotations, statistics, or events. Clearly expose weak, conflicting, or incomplete evidence in assumptions. If no material uncertainty exists, include an assumption note stating that the report is limited to publicly available sources reviewed for the reporting window.

Write for an executive and regulatory audience. Keep the executive snapshot concise. Provide at least three priority trends. Separate what happened from why it matters, the signal, and the risk or opportunity. Return only content that conforms to the supplied JSON schema.
PROMPT

USER_PROMPT="Prepare the report for ${WEEK_START} through ${WEEK_END} (${REPORTING_WEEK}). Set preparedBy to Innovation & Policy and reportingWeek to ${REPORTING_WEEK}."

REQUEST_JSON="$({
  jq -n \
    --arg model "${OPENAI_MODEL}" \
    --arg effort "${OPENAI_REASONING_EFFORT}" \
    --arg instructions "${SYSTEM_PROMPT}" \
    --arg input "${USER_PROMPT}" \
    --slurpfile schema "${SCHEMA_PATH}" \
    '{
      model: $model,
      store: false,
      reasoning: {effort: $effort},
      tools: [{
        type: "web_search",
        external_web_access: true,
        search_context_size: "medium",
        user_location: {type: "approximate", country: "GH"}
      }],
      tool_choice: "required",
      instructions: $instructions,
      input: $input,
      text: {
        format: {
          type: "json_schema",
          name: "nca_weekly_report_content",
          strict: true,
          schema: $schema[0]
        }
      },
      max_output_tokens: 12000
    }'
})"

if [[ -n "${OPENAI_RESPONSE_FILE:-}" ]]; then
  [[ -r "${OPENAI_RESPONSE_FILE}" ]] || die "OPENAI_RESPONSE_FILE is not readable: ${OPENAI_RESPONSE_FILE}"
  RESPONSE_JSON="$(<"${OPENAI_RESPONSE_FILE}")"
else
  require_command curl
  printf 'Generating NCA weekly report for %s through %s with %s.\n' "${WEEK_START}" "${WEEK_END}" "${OPENAI_MODEL}" >&2
  if [[ -n "${OPENAI_PROXY_URL:-}" ]]; then
    : "${AGENT_API_KEY:?Set AGENT_API_KEY for the provider proxy}"
    RESPONSE_JSON="$(
      curl --fail-with-body --silent --show-error \
        --max-time "${OPENAI_TIMEOUT_SECONDS}" \
        -H 'Content-Type: application/json' \
        -H "X-Agent-Key: ${AGENT_API_KEY}" \
        -X POST "${OPENAI_PROXY_URL}" \
        -d "${REQUEST_JSON}"
    )" || die "Provider proxy request failed"
  else
    : "${OPENAI_API_KEY:?Set OPENAI_API_KEY or OPENAI_PROXY_URL}"
    RESPONSE_JSON="$(
      curl --fail-with-body --silent --show-error \
        --max-time "${OPENAI_TIMEOUT_SECONDS}" \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer ${OPENAI_API_KEY}" \
        -X POST "${OPENAI_API_BASE%/}/responses" \
        -d "${REQUEST_JSON}"
    )" || die "OpenAI Responses API request failed"
  fi
fi

jq -e . >/dev/null <<<"${RESPONSE_JSON}" || die "provider response was not valid JSON"

CONTENT_JSON="$({
  jq -er '
    [
      .output[]?
      | select(.type == "message")
      | .content[]?
      | select(.type == "output_text")
      | .text
    ][0]
  ' <<<"${RESPONSE_JSON}"
})" || {
  provider_error="$(jq -r '.error.message // "response contained no output_text"' <<<"${RESPONSE_JSON}")"
  die "${provider_error}"
}

jq -e . >/dev/null <<<"${CONTENT_JSON}" || die "model output was not valid JSON"

CONTENT_JSON="$({
  jq \
    --arg reportingWeek "${REPORTING_WEEK}" \
    '.reportingWeek = $reportingWeek | .preparedBy = "Innovation & Policy"' \
    <<<"${CONTENT_JSON}"
})"

CONTENT_VALID=false
if jq -e '
  (.executiveSnapshot | type == "string" and length > 0)
  and (.priorityTrends | type == "array" and length >= 3)
  and (.horizon | type == "array" and length > 0)
  and (.implications | type == "array" and length > 0)
  and (.attentionSignals | type == "array" and length > 0)
  and (.assumptions | type == "array" and length > 0)
  and (.references | type == "array" and length >= 5)
  and ([.references[].url | select(type == "string" and test("^https://"))] | unique | length >= 5)
' >/dev/null <<<"${CONTENT_JSON}"; then
  CONTENT_VALID=true
fi

AUTO_PUBLISH=false
if [[ "${AGENT_AUTO_PUBLISH,,}" == "true" && "${CONTENT_VALID}" == "true" ]]; then
  AUTO_PUBLISH=true
fi

if [[ "${CONTENT_VALID}" != "true" ]]; then
  printf 'Generated content did not satisfy unattended-publication checks; submitting for human review.\n' >&2
elif [[ "${AUTO_PUBLISH}" != "true" ]]; then
  printf 'Generated content passed structural checks; AGENT_AUTO_PUBLISH is not enabled, so human review remains required.\n' >&2
fi

jq -n \
  --arg weekStart "${WEEK_START}" \
  --arg weekEnd "${WEEK_END}" \
  --arg title "${REPORT_TITLE}" \
  --argjson autoPublishIfValid "${AUTO_PUBLISH}" \
  --argjson content "${CONTENT_JSON}" \
  '{
    weekStart: $weekStart,
    weekEnd: $weekEnd,
    title: $title,
    autoPublishIfValid: $autoPublishIfValid,
    content: $content
  }'
