# Test Server Deployment

The test deployment runs the ASP.NET Core 8 application as a non-root Linux container and persists report data in a Docker volume. The application binds only to the test host's loopback interface; the Compose-managed Nginx edge publishes the approved HTTPS endpoint.

## Prerequisites

- Docker Engine with the Compose plugin
- Git access to this repository
- An HTTPS reverse proxy, or an SSH tunnel for private testing

## Configure secrets

On the test host, clone or pull the repository and create the runtime environment file:

```bash
cp .env.test.example .env.test
chmod 600 .env.test
```

Generate an editor password hash on a trusted machine:

```powershell
powershell -ExecutionPolicy Bypass -File tools\New-PasswordHash.ps1 -Password "<test-password>"
```

Put that output in `ADMIN_PASSWORD_HASH` and set a separate long random value in `AGENT_API_KEY`. Do not use production secrets on the test server. The test deployment forces `Agent__AllowAutoPublish=false`, so agent submissions remain pending for human review.

## Start or update

```bash
docker compose --env-file .env.test -f compose.test.yaml up -d --build
docker compose --env-file .env.test -f compose.test.yaml ps
```

The web application starts independently. Before enabling the weekly research agent, add `OPENAI_API_KEY` directly to the protected `.env.test` file on the server, then run:

```bash
docker compose --env-file .env.test -f compose.test.yaml --profile agent build weekly-agent
docker compose --env-file .env.test -f compose.test.yaml --profile agent run --rm weekly-agent /nca-weekly-agent/test-generate-weekly-report.sh
docker compose --env-file .env.test -f compose.test.yaml --profile agent up -d weekly-agent
```

The agent checks once per weekday at or after 08:00 Africa/Accra. The watchdog avoids generation when the previous Monday-Friday report is already published. Generated reports remain pending for human review because both `AGENT_AUTO_PUBLISH` and the server-side `Agent__AllowAutoPublish` setting are disabled.

The application service listens on `127.0.0.1:8080` unless `TEST_HTTP_PORT` is changed. The HTTPS edge listens on port `3055` unless `WEEKLY_REPORTS_HTTPS_PORT` is changed and uses the NCA corporate wildcard certificate mounted read-only from the test host.

Open the deployed application at:

`https://dev-env.corp.nca.org.gh:3055/index.html`

Port `3054` is reserved by the existing NCA GRC test application and must not be reassigned.

For temporary private access without a reverse proxy, create an SSH tunnel from the tester's computer:

```bash
ssh -L 8080:127.0.0.1:8080 <user>@<test-host>
```

Then open `http://127.0.0.1:8080` locally.

## Verify

```bash
curl --fail http://127.0.0.1:8080/api/health
curl --fail http://127.0.0.1:8080/api/session
curl --include http://127.0.0.1:8080/api/reports
```

Expected results:

- `/api/health` returns `storageOk: true`.
- `/api/session` returns `authenticated: false` before login.
- `/api/reports` returns HTTP 401 before login.
- The home page opens in public read-only mode.
- `Editor Sign In` accepts the configured test editor password.

After basic verification, run the agent pipeline with a test-only agent key and synthetic data. Keep automatic live AI generation disabled until the generated report has been reviewed. The Compose deployment does not run or contact an external AI provider; adding the generator requires a separate approval of provider, data-residency, source-access, and secret-management controls.

## Operations

View logs:

```bash
docker compose --env-file .env.test -f compose.test.yaml logs --tail=200 -f weekly-reports
```

Stop the service without deleting report data:

```bash
docker compose --env-file .env.test -f compose.test.yaml down
```

The named volume `weekly-reports-test-data` is intentionally retained by `down`. Do not add `--volumes` unless deletion of all test report data is explicitly intended.
