# Weekly Reports Intranet — System Overview

## Purpose

This system publishes the latest approved NCA Emerging Technologies and Trends weekly report while giving authorized staff a controlled workflow for upload, editing, review, approval, rejection, and audit.

## Main components

- **ASP.NET Core 8 application:** serves the browser interface and JSON API from one process.
- **Static browser interface:** provides the public report view and authenticated editor/reviewer controls.
- **Repository-local report store:** writes report metadata, structured content, Word output, validation results, approval records, and append-only audit lines under `reports/<year>/<week-range>/`.
- **Weekly agent tools:** optional Linux scripts generate structured weekly content and submit it through an API key-protected endpoint.
- **Watchdog:** checks whether the previous Monday-to-Friday report is already published before invoking the generator.

## User and data flow

1. An anonymous visitor opens the site and sees only the newest `Published` report.
2. An editor signs in, uploads a Word report or edits structured report content, and submits it for review.
3. A reviewer approves and publishes or rejects the report.
4. The agent may create a draft through `POST /api/agent/run`; the server validates required sections and references.
5. Agent auto-publication is blocked unless the server operator explicitly enables `Agent:AllowAutoPublish`.
6. Report actions are written to report-local JSONL audit records.

## Access model

- **Anonymous:** health, session state, and latest published report only.
- **Editor:** report creation, upload, editing, and review submission.
- **Reviewer:** approval, publication, and rejection.
- **Admin:** all human roles plus diagnostics and password-hash tooling.
- **Weekly agent:** API-key access to watchdog, report intake, week lookup, and—only when server-enabled—auto-publication.

## Deployment model

The supplied test deployment builds a Linux .NET 8 container, runs it as a non-root user, keeps the root filesystem read-only, binds the application port to host loopback, and persists both report data and ASP.NET data-protection keys in named volumes. HTTPS is expected at an approved reverse proxy.

## Governance position

Human review is the default release path. Agent output includes validation and provenance fields, and test deployment disables automatic publication. This implements practical least-privilege, explainability, and human-authority controls, but it does not prove that external VPF runtime services, ledgers, signatures, residency enforcement, or scheduled audits are active.

The web container does not call an external AI provider. Enabling the separate generator requires an explicit provider, data-residency, source-access, retention, and secret-management decision. Until those controls are approved, keep live AI generation disconnected and test only with synthetic content.

## Current operational gaps

- No test-host address or SSH/deployment credential is stored in the repository.
- Docker is required on the target host; it is not installed on the current Windows workstation.
- TLS and the test hostname must be supplied by the target environment's reverse proxy.
- Authentication is application-managed rather than integrated with NCA directory identity.
- Reports are persisted in files, not a transactional database; concurrent editing and multi-instance deployment are not supported safely.
- Login throttling, centralized monitoring, backup policy, and restore testing still need production decisions.

See `TEST_SERVER_DEPLOYMENT.md` for test-host commands and `INTRANET_WORKFLOW.md` for the report lifecycle.
