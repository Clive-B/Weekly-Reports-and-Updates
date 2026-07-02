# NCA Weekly Reports Intranet Workflow

## Governance Position

This workflow follows the VPF / Nyame Mind operating posture:

- Route before reasoning: classify each report action before execution.
- Recall before major judgment: preserve audit metadata and source references.
- Validate before polishing: block unattended publication when validation fails.
- Govern before release: require human approval where available.
- Escalate before invention: do not fabricate trends or references.

## Storage Boundary

Reports are stored only inside this repository.

Default structure:

```text
reports/
  2026/
    2026-06-15_to_2026-06-19/
      report.docx
      report.json
      content.json
      approval.json
      validation.json
      audit.jsonl
```

The application validates the storage path so `Reports:Root` cannot escape the repository.

## Roles

- `Editor`: uploads Word reports, edits drafts, submits for review.
- `Reviewer`: approves, rejects, and publishes pending reports.
- `Admin`: full access, including password-hash helper.
- `weekly-trends-agent`: service identity for automated draft creation and auto-publication.

## Report Lifecycle

```text
Draft -> PendingReview -> Published
   \          |
    \         -> Rejected
     \
      -> AutoPublished when the agent key is used and validation passes
```

Human approval remains the preferred route. Auto-publication exists for leave periods or unattended continuity and is recorded as `AutoPublished`.

## Agent Intake

The agent endpoint is:

```text
POST /api/agent/run
Header: X-Agent-Key: <configured secret>
```

The agent should send structured report content with references. If no week is supplied, the server calculates the previous Monday-Friday window.

For example, on Monday 22 June 2026, the target reporting window is Monday 15 June 2026 to Friday 19 June 2026.

The server validates before auto-publication:

- Executive snapshot must be present.
- At least three priority trends are required.
- At least five references are required.
- Every reference must include a URL.
- Assumption exposure notes must be present.

If validation fails, the report remains pending for review.

## Authentication Setup

The current project uses server-side cookie authentication with PBKDF2 password hashes configured under `Auth:Users`.

To generate a hash before the first sign-in:

```powershell
powershell -ExecutionPolicy Bypass -File tools\New-PasswordHash.ps1 -Password "replace-with-strong-password"
```

Place the generated value in `Auth:Users:PasswordHash`.

After an admin user is configured, an admin can also visit:

```text
/api/tools/hash-password?password=<new-password>
```

For production intranet hosting, NCA may replace this with IIS/Active Directory/Entra-backed authentication while preserving the same role model.

## Human Plus Automation Policy

- If a reviewer is available, the reviewer approves or rejects.
- If no reviewer acts before the automation deadline, the scheduler may call `auto-publish`.
- Auto-published reports must be flagged for post-review.
- Human edits after auto-publication should create a revised report version rather than silently rewriting the audit trail.
