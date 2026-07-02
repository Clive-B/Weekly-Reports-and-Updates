# Docker App Needs

This note describes what the Ubuntu-hosted Docker container needs for the NCA Weekly Emerging Technologies & Trends intranet app to run reliably at:

```text
https://emergingtrends.corp.nca.org.gh
```

## Container Runtime

Use a Linux container with:

- .NET 8 ASP.NET Core runtime.
- HTTPS termination handled by the reverse proxy, such as Nginx, Apache, Traefik, or the NCA ingress layer.
- The app listening on an internal HTTP port, for example `8080`.
- A stable mounted volume for repo-local report storage.

Recommended runtime environment variables:

```text
ASPNETCORE_URLS=http://+:8080
ASPNETCORE_ENVIRONMENT=Production
Reports__Root=reports
Agent__ApiKey=<strong-random-agent-secret>
```

Do not bake secrets into the image. Inject them through Docker secrets, the orchestrator secret store, or protected environment variables.

## Persistent Repo Storage

The application is designed to store generated and uploaded reports only inside the repository under:

```text
reports/
```

In Docker, this path must be persistent. Mount it as a volume so reports survive container rebuilds and restarts:

```text
/app/reports
```

The container user must have read/write access to this folder.

The app currently writes:

```text
reports/<year>/<week-range>/report.docx
reports/<year>/<week-range>/report.json
reports/<year>/<week-range>/content.json
reports/<year>/<week-range>/approval.json
reports/<year>/<week-range>/validation.json
reports/<year>/<week-range>/audit.jsonl
```

## Authentication

The current implementation supports server-side cookie authentication with configured users and roles.

For production, choose one of these:

- Keep app-managed users with PBKDF2 password hashes in secure configuration.
- Preferably integrate with NCA intranet identity through the reverse proxy or a future Active Directory / Entra / OIDC layer.

Required roles:

```text
Editor
Reviewer
Admin
```

The AI service identity is not an interactive user. It authenticates through:

```text
X-Agent-Key: <Agent__ApiKey>
```

## AI Agent Requirements

For seamless automated report generation, the container or its sidecar/scheduler needs:

- Outbound HTTPS access to the approved AI provider endpoint.
- Outbound HTTPS access to approved source websites, if the agent researches live weekly trends.
- An OpenAI/API credential or equivalent provider credential injected as a secret.
- The app's internal agent endpoint URL:

```text
POST http://localhost:8080/api/agent/run
```

or, from outside the container:

```text
POST https://emergingtrends.corp.nca.org.gh/api/agent/run
```

with:

```text
X-Agent-Key: <Agent__ApiKey>
Content-Type: application/json
```

The agent must submit structured JSON matching `docs/WEEKLY_TRENDS_AGENT_CONTRACT.md`.

## Scheduling

The app does not currently include a built-in scheduler.

Use one of these:

- Host cron on the Ubuntu server.
- A separate scheduler container.
- Systemd timer.
- NCA orchestration platform scheduled job.

Recommended generation schedule:

```text
Every Monday after the previous week has closed, for example Monday 08:00 Africa/Accra.
```

The agent should calculate the previous Monday-Friday reporting window. For example, on Monday 22 June 2026, the target window is Monday 15 June 2026 to Friday 19 June 2026.

Recommended watchdog fallback schedule:

```text
Tuesday-Friday at 08:00 Africa/Accra.
```

The watchdog checks whether the previous Monday-Friday report has already been published. If the report is published, it exits quietly. If the report is missing or still not published, it triggers the AI agent generator and submits the generated payload to the app.

The app exposes:

```text
POST /api/agent/watchdog-check
X-Agent-Key: <Agent__ApiKey>
Content-Type: application/json
```

The response includes:

```text
shouldRunAgent=true|false
```

The watchdog must only generate a report when `shouldRunAgent` is `true`.

The repo includes a Linux runner skeleton:

```text
tools/weekly-agent-watchdog.sh
```

It requires `curl` and `jq` in the scheduler environment.

Example scheduler environment:

```text
APP_BASE_URL=http://localhost:8080
AGENT_API_KEY=<same value as Agent__ApiKey>
AGENT_GENERATE_COMMAND=/opt/nca-weekly-agent/generate-weekly-report.sh
```

Example cron entries:

```cron
TZ=Africa/Accra

# Monday primary generation.
0 8 * * 1 /opt/nca-weekly-agent/generate-weekly-report.sh | curl -fsS -H "X-Agent-Key: $AGENT_API_KEY" -H "Content-Type: application/json" -X POST "$APP_BASE_URL/api/agent/run" -d @-

# Tuesday-Friday fallback check.
0 8 * * 2-5 /app/tools/weekly-agent-watchdog.sh
```

If the scheduler runs in a separate container, mount or copy `tools/weekly-agent-watchdog.sh` into that scheduler image and provide the same environment variables through Docker secrets or a protected env file.

## Network Access

The container should have:

- Inbound access only through the reverse proxy.
- Internal listening port exposed only to the proxy, not directly to the public network.
- Outbound HTTPS restricted to approved AI and research/source domains where possible.
- DNS resolution for `emergingtrends.corp.nca.org.gh` and approved external sources.
- Correct system time and timezone handling.

Recommended timezone:

```text
TZ=Africa/Accra
```

## Reverse Proxy Requirements

The reverse proxy should provide:

- TLS certificate for `emergingtrends.corp.nca.org.gh`.
- Redirect from HTTP to HTTPS.
- Forwarded headers:

```text
X-Forwarded-For
X-Forwarded-Proto
X-Forwarded-Host
```

- Upload size large enough for Word documents.
- Reasonable request timeout for agent generation or upload operations.

Suggested upload allowance:

```text
client_max_body_size 25m
```

## Secrets Needed

Minimum production secrets:

```text
Agent__ApiKey
Auth__Users__0__PasswordHash
```

If the agent runs inside or beside the container:

```text
OPENAI_API_KEY=<OpenAI platform API key>
```

or the approved equivalent for the selected AI provider.

Do not commit production secrets to Git.

Never place the live OpenAI API key directly in this Markdown file, `appsettings.json`, a Dockerfile, or any repo-tracked file. Inject it at runtime through Docker secrets, an orchestrator secret store, or a protected environment file that is excluded from Git.

Example runtime-only environment file:

```text
# /etc/nca-weekly-reports/weekly-reports.env
OPENAI_API_KEY=<paste-live-key-here-on-server-only>
Agent__ApiKey=<strong-random-agent-secret>
ASPNETCORE_ENVIRONMENT=Production
ASPNETCORE_URLS=http://+:8080
Reports__Root=reports
TZ=Africa/Accra
```

The environment file should be readable only by the deployment user or container runtime:

```bash
sudo chown root:docker /etc/nca-weekly-reports/weekly-reports.env
sudo chmod 640 /etc/nca-weekly-reports/weekly-reports.env
```

## File Permissions

Run the container as a non-root user where possible.

Required writable paths:

```text
/app/reports
```

Optional writable paths:

```text
/tmp
```

No Desktop path is required. No external desktop sync is required.

## Git Behavior

The current app stores files in the repo directory but does not automatically commit or push them.

If NCA wants every generated report committed:

- Add a controlled Git worker or CI job.
- Use a service account.
- Commit only `reports/` changes.
- Keep Git credentials outside the app image.
- Log commit hash in the report audit trail.

Do not let the AI agent run broad Git commands directly inside the app container without a constrained wrapper.

## Human Plus Automation Controls

The workflow supports:

- Human upload and edit.
- Human approval and publish.
- Agent draft generation.
- Auto-publication when validation passes and the agent key is used.

Auto-published reports should remain visibly auditable through:

```text
approval.json
audit.jsonl
validation.json
```

Reports with missing references, missing assumptions, or incomplete sections should remain pending for review.

## Health Checks

Use:

```text
GET /api/session
```

Expected unauthenticated response:

```json
{
  "authenticated": false
}
```

A stronger future health endpoint can be added for:

- storage write checks,
- agent key presence,
- AI provider connectivity,
- report volume availability.

## Minimum Container Checklist

- .NET 8 ASP.NET Core runtime installed.
- Scheduler image or host cron has `curl` and `jq` if using `tools/weekly-agent-watchdog.sh`.
- App files copied to `/app`.
- `/app/reports` mounted as a persistent writable volume.
- `ASPNETCORE_URLS=http://+:8080`.
- `ASPNETCORE_ENVIRONMENT=Production`.
- `Agent__ApiKey` configured.
- Production authentication configured.
- Reverse proxy terminates HTTPS for `emergingtrends.corp.nca.org.gh`.
- Outbound HTTPS allowed for approved AI/source access.
- Scheduler configured outside or beside the app.
- Secrets injected securely, not committed.
- Logs collected by Docker, journald, or the NCA logging platform.
