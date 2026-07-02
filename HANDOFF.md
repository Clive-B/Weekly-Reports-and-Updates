# Weekly Reports Intranet Handoff

Last updated: 2 July 2026

Repository: `C:\Users\codro\Desktop\WEEKLY REPORTS`

Branch: `main`

Remote: `https://github.com/Clive-B/Weekly-Reports-and-Updates.git`

## Purpose

This handoff preserves the current state of the NCA Weekly Emerging Technologies & Trends intranet application, the decisions made during the latest work, the verification completed, and the remaining production-deployment steps.

## Requested access model

The agreed behavior is public-read/editor-protected:

- Anyone visiting the site should immediately see the latest published weekly report.
- Visitors must not be forced through an authentication page.
- Anonymous visitors remain read-only.
- An `Editor Sign In` button opens the editor login form on demand.
- Upload, content editing, review, approval, publication, report inventory, and audit controls remain authenticated.
- Anonymous API access exposes only the latest report whose status is `Published`; drafts, rejected reports, audit records, approval records, validation details, and repository paths remain protected.
- Signing out returns the user to the public report view.

## Implementation completed

### Server

`app/WeeklyReports.Intranet/Program.cs`

- Cookie authentication and role policies remain in place.
- `GET /api/reports/current` now permits anonymous access.
- That endpoint selects only the newest `Published` report.
- Its public response contains a reduced public metadata object plus report content; it does not return audit, approval, validation, creator, or document-path information.
- `GET /api/reports`, `GET /api/reports/{id}`, uploads, edits, review actions, approval, rejection, and administrative tools remain authenticated and role-protected.

### Browser interface

`app/WeeklyReports.Intranet/wwwroot/index.html`

- Added `Editor Sign In` to the identity header.
- Added a cancel action to the editor login form.
- Added an identifier used to hide the report-management picker from anonymous visitors.
- Updated the footer to describe public read-only access.

`app/WeeklyReports.Intranet/wwwroot/app.js`

- The report page is shown to anonymous visitors.
- Editor controls and the complete report inventory are hidden until authentication succeeds.
- Anonymous visitors load `/api/reports/current`.
- Authenticated users load the protected report inventory.
- If no report has been published, the public page shows an explicit awaiting-publication state instead of a login wall.
- The login form opens only when `Editor Sign In` is selected.

`app/WeeklyReports.Intranet/wwwroot/styles.css`

- Added styling for the sign-in and cancel action row.

### Supporting application files

- `.gitignore` excludes .NET `bin/`, `obj/`, and production appsettings files.
- `README.md` documents the ASP.NET Core intranet application and local run command.
- `docs/INTRANET_WORKFLOW.md` documents the human workflow.
- `docs/WEEKLY_TRENDS_AGENT_CONTRACT.md` documents the automation contract.
- `app/WeeklyReports.Intranet/DOCKER_APP_NEEDS.md` records the production container, persistence, reverse-proxy, scheduler, and secret requirements.
- `tools/New-PasswordHash.ps1` generates compatible PBKDF2 password hashes.
- `tools/weekly-agent-watchdog.sh` contains the watchdog workflow helper.

## Editor authentication

The configured username is `admin`, with the roles `Admin`, `Reviewer`, and `Editor`.

The requested editor password was generated as a PBKDF2-SHA256 hash and successfully tested against the local `/api/login` and `/api/session` endpoints. The login returned `authenticated: true` and all three roles.

The password and hash are deliberately not stored in this Git repository. `appsettings.json` contains an empty development placeholder. Production must inject the generated hash through the protected runtime variable:

```text
Auth__Users__0__PasswordHash
```

Generate the value during deployment without committing it:

```powershell
powershell -ExecutionPolicy Bypass -File tools\New-PasswordHash.ps1 -Password "<editor-password>"
```

If production also overrides the user record, verify `Auth__Users__0__Username=admin` and the required role variables/configuration.

## Verification completed

- `dotnet build app\WeeklyReports.Intranet\WeeklyReports.Intranet.csproj`
  - Result: succeeded with 0 warnings and 0 errors.
- `node --check app\WeeklyReports.Intranet\wwwroot\app.js`
  - Result: passed.
- Local application smoke test:
  - Home page returned HTTP 200.
  - The HTML contained `Editor Sign In`.
  - With no published local report, `/api/reports/current` returned HTTP 404 as designed.
  - The protected report inventory did not expose report JSON anonymously.
- Local authentication test before secret removal from tracked configuration:
  - Login authenticated as `admin`.
  - Session authentication was true.
  - Roles returned: `Admin`, `Reviewer`, `Editor`.

## Current data state

The local repository has no populated `reports/` records and therefore no published report. The anonymous interface will show its awaiting-publication state until a report is uploaded, reviewed, and published or until the production persistent reports volume is mounted.

The production reports directory must remain on persistent storage so a container rebuild does not erase published reports.

## Why the live site still showed the old login wall

The production URL shown during review was:

```text
https://emergingtrends.corp.nca.org.gh
```

The screenshot demonstrated that production was still serving the previous build:

- Header status said `Not signed in`, rather than `Public view`.
- The editor authentication panel appeared immediately.
- There was no `Editor Sign In` button.
- The footer still said `Authenticated intranet workflow`.
- The newly requested editor password failed.

At that time the entire `app/` directory was untracked locally, so none of the application changes had reached GitHub or the production server. In addition, production is expected to use an environment-provided password hash, which overrides the empty/template value in `appsettings.json`.

## Production continuation steps

1. Pull the commit containing this handoff and application into the production build context.
2. Build and deploy a new application/container image.
3. Preserve or mount the existing production `reports/` volume.
4. Generate the requested password hash outside Git and set `Auth__Users__0__PasswordHash` in the protected production environment or secret store.
5. Confirm the production username is `admin` and roles include `Admin`, `Reviewer`, and `Editor`.
6. Restart or replace the application container.
7. Clear any reverse-proxy/static cache if the old `index.html`, `app.js`, or `styles.css` remains cached.
8. Verify in a private browser window:
   - The public report appears without sign-in.
   - `Editor Sign In` opens the form.
   - The requested editor credentials work.
   - Anonymous visitors cannot list drafts or call editing endpoints.
   - Editor upload and publication work.
   - Signing out restores the public view.

## Deployment constraints identified

- No production-server or container-runtime credentials are available in this workspace.
- No executable Dockerfile or CI/CD workflow is currently present in the repository; `DOCKER_APP_NEEDS.md` is a requirements document, not a deploy script.
- A previous direct GitHub query failed on this Windows host with `SEC_E_NO_CREDENTIALS`. If push authentication fails again, authenticate Git Credential Manager or use an approved GitHub credential/session.

## Scope and repository hygiene

The application, documentation, tools, `.gitignore`, `README.md`, and this handoff belong in the application commit.

The following untracked user artifacts were intentionally not included automatically because their relationship to the deployable application was not established:

- `EMERGING TRENDS AND TECHNOLOGIES.zip`
- `EMERGING TRENDS AND TECHNOLOGIES V2.zip`
- `Watchdog Implemented Chat Feedback.docx`
- `Watchdog.docx`
- `sk.docx`

Review those binary artifacts separately before adding them to Git.
