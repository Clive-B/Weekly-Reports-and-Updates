#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$(mktemp)"
trap 'rm -f "${FIXTURE}"' EXIT

cat >"${FIXTURE}" <<'JSON'
{
  "output": [
    {
      "type": "message",
      "content": [
        {
          "type": "output_text",
          "text": "{\"reportingWeek\":\"model value replaced by runner\",\"preparedBy\":\"Innovation Unit\",\"executiveSnapshot\":\"Verified weekly snapshot.\",\"priorityTrends\":[{\"title\":\"Trend 1\",\"whatHappened\":\"Event 1\",\"whyItMatters\":\"Impact 1\",\"signal\":\"Signal 1\",\"riskOpportunity\":\"Opportunity 1\"},{\"title\":\"Trend 2\",\"whatHappened\":\"Event 2\",\"whyItMatters\":\"Impact 2\",\"signal\":\"Signal 2\",\"riskOpportunity\":\"Risk 2\"},{\"title\":\"Trend 3\",\"whatHappened\":\"Event 3\",\"whyItMatters\":\"Impact 3\",\"signal\":\"Signal 3\",\"riskOpportunity\":\"Opportunity 3\"}],\"horizon\":[{\"title\":\"Horizon\",\"body\":\"Watch item\"}],\"implications\":[{\"title\":\"Implication\",\"body\":\"Regulatory relevance\"}],\"attentionSignals\":[\"Monitor the signal\"],\"assumptions\":[\"Limited to public sources.\"],\"references\":[{\"title\":\"Source 1\",\"url\":\"https://example.com/1\",\"publisher\":\"Example\",\"publishedAt\":\"2026-07-06\"},{\"title\":\"Source 2\",\"url\":\"https://example.com/2\",\"publisher\":\"Example\",\"publishedAt\":\"2026-07-07\"},{\"title\":\"Source 3\",\"url\":\"https://example.com/3\",\"publisher\":\"Example\",\"publishedAt\":\"2026-07-08\"},{\"title\":\"Source 4\",\"url\":\"https://example.com/4\",\"publisher\":\"Example\",\"publishedAt\":\"2026-07-09\"},{\"title\":\"Source 5\",\"url\":\"https://example.com/5\",\"publisher\":\"Example\",\"publishedAt\":\"2026-07-10\"}]}"
        }
      ]
    }
  ]
}
JSON

PAYLOAD="$({
  WEEK_START=2026-07-06 \
  WEEK_END=2026-07-10 \
  AGENT_AUTO_PUBLISH=true \
  OPENAI_RESPONSE_FILE="${FIXTURE}" \
    bash "${SCRIPT_DIR}/generate-weekly-report.sh"
})"

jq -e '
  .weekStart == "2026-07-06"
  and .weekEnd == "2026-07-10"
  and .autoPublishIfValid == true
  and .content.reportingWeek == "6 - 10 July 2026"
  and (.content.priorityTrends | length) == 3
  and (.content.references | length) == 5
' >/dev/null <<<"${PAYLOAD}"

printf 'generate-weekly-report self-test passed.\n'
