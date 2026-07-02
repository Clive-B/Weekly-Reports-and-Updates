# Weekly Reports and Updates

This repository contains weekly Emerging Technologies and Trends reports prepared for National Communications Authority research, innovation, policy, and strategy review work.

## Contents

- Weekly report documents in Microsoft Word format.
- A reusable HTML report template that can import compatible `.docx` weekly reports and render the report sections in a browser.

## Publication Notes

- The HTML file is a local/static template and does not include embedded editor credentials.
- The Word reports may retain standard document metadata from Microsoft Word.
- For protected editing or wider deployment, place the HTML template behind proper server-side authentication rather than relying on front-end controls.

## Intranet Application

The `app/WeeklyReports.Intranet` project is an ASP.NET Core intranet workflow for authenticated upload, editing, review, and publication.

Core behavior:

- Uses server-side cookie authentication with role-based access.
- Stores all generated and uploaded reports only inside this repository under `reports/`.
- Supports `Draft`, `PendingReview`, `Published`, and `Rejected` report states.
- Supports both human-approved and controlled auto-published reports.
- Writes audit records beside each report in repo-local JSON/JSONL files.
- Provides an agent endpoint for previous-week Monday-Friday report intake.

Run locally:

```powershell
dotnet run --project app\WeeklyReports.Intranet
```

Before production use, configure:

- `Auth:Users` with PBKDF2 password hashes.
- `Agent:ApiKey` with a strong server-side secret.
- HTTPS and intranet hosting controls in IIS or the approved NCA hosting environment.

The legacy `Weekly Report HTML File.html` remains as the original standalone local template.
