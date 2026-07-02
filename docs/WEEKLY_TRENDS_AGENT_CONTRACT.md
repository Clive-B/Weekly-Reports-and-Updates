# Weekly Trends Agent Contract

## Objective

Prepare the previous Monday-Friday NCA Weekly Emerging Technologies & Trends report in the established format, then submit it to the intranet workflow as a draft or auto-publishable candidate.

## Required Format

The agent output must map to this JSON shape:

```json
{
  "autoPublishIfValid": false,
  "content": {
    "reportingWeek": "15 - 19 June 2026",
    "preparedBy": "Innovation Unit",
    "executiveSnapshot": "",
    "priorityTrends": [
      {
        "title": "",
        "whatHappened": "",
        "whyItMatters": "",
        "signal": "",
        "riskOpportunity": ""
      }
    ],
    "horizon": [
      {
        "title": "",
        "body": ""
      }
    ],
    "implications": [
      {
        "title": "",
        "body": ""
      }
    ],
    "attentionSignals": [],
    "assumptions": [],
    "references": [
      {
        "title": "",
        "url": "",
        "publisher": "",
        "publishedAt": ""
      }
    ]
  }
}
```

## Source Discipline

The agent must prioritize:

- regulator and government notices,
- telecom operator and vendor announcements,
- satellite and standards-body updates,
- cybersecurity advisories,
- cloud/data governance developments,
- Ghana, African, ECOWAS, AU, and ITU-relevant signals.

The agent must not include a trend unless it has a traceable source URL. If source quality is weak, place the caveat in `assumptions`.

## Automation Boundary

Set `autoPublishIfValid` to `true` only when:

- the reporting week is complete,
- all required sections are populated,
- at least five source URLs are included,
- the agent has not inferred facts beyond the sources,
- no high-impact uncertainty remains unresolved.

Otherwise set it to `false` and let a human reviewer decide.

## Endpoint

```text
POST /api/agent/run
X-Agent-Key: <server-configured key>
Content-Type: application/json
```

The intranet app saves the resulting `report.docx`, metadata, validation file, and audit trail under `reports/` inside this repository.

## Watchdog Fallback

The agent platform should also run a Tuesday-Friday watchdog at 08:00 Africa/Accra.

The watchdog checks whether the previous Monday-Friday report has already been published. If it has, the watchdog exits without generating anything. If it has not, the watchdog triggers the report generator and submits the generated payload to `/api/agent/run`.

The watchdog check endpoint is:

```text
POST /api/agent/watchdog-check
X-Agent-Key: <server-configured key>
Content-Type: application/json
```

Body:

```json
{}
```

Optional explicit date body for tests or manual recovery:

```json
{
  "today": "2026-06-24"
}
```

Optional explicit week body:

```json
{
  "weekStart": "2026-06-15",
  "weekEnd": "2026-06-19"
}
```

Example response:

```json
{
  "weekStart": "2026-06-15",
  "weekEnd": "2026-06-19",
  "published": false,
  "shouldRunAgent": true,
  "reportId": null,
  "message": "No report exists for the target reporting week."
}
```

The watchdog must only call the generator when `shouldRunAgent` is `true`.

The repo includes a Linux runner skeleton:

```text
tools/weekly-agent-watchdog.sh
```

It expects:

```text
APP_BASE_URL
AGENT_API_KEY
AGENT_GENERATE_COMMAND
```

`AGENT_GENERATE_COMMAND` must write the full `/api/agent/run` JSON payload to stdout.
