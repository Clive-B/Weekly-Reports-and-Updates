# SharePoint Word Template Fields

The controlled master template is:

```text
NCA Weekly Report Power Automate Master Template.docx
```

It is derived from `Week 4th-8th May 2026 Report Emerging Trends & Technologies.docx`. The source report remains unchanged.

## Protection model

- The NCA logo, institutional headings, section headings, formatting, and numbering remain static.
- Every dynamic field uses a uniquely named plain-text content control supported by the Power Automate Word Online (Business) connector.
- Content controls are locked against deletion but their contents remain replaceable by Power Automate.
- The local master file is marked read-only.
- After upload, restrict SharePoint `Templates` library editing to designated template administrators. Power Automate needs read access to the master and write access to the `Drafts` library.
- Do not apply a Word open password, write password, or document-level editing restriction to the automation master; those controls can prevent cloud template processing.

## Header fields

```text
ReportingWeek
PreparedBy
ExecutiveSnapshotParagraph1
ExecutiveSnapshotParagraph2
ExecutiveSnapshotParagraph3
```

## Priority trends

Four fixed trend blocks are retained. Replace `{N}` with `1`, `2`, `3`, or `4`:

```text
Trend{N}Title
Trend{N}WhatHappened
Trend{N}WhyItMatters
Trend{N}StrategicSignal1
Trend{N}StrategicSignal2
Trend{N}Risk
Trend{N}Opportunity
Trend{N}TimeHorizon
```

## Technologies and developments on the horizon

Three fixed horizon blocks are retained. Replace `{N}` with `1`, `2`, or `3`:

```text
Horizon{N}Title
Horizon{N}PotentialRelevance
Horizon{N}UncertaintyLevel
```

## Regulatory and strategic implications

```text
SpectrumManagementSignal1
SpectrumManagementSignal2
InfrastructureEvolutionSignal1
InfrastructureEvolutionSignal2
DigitalServicesGovernanceSignal1
CybersecurityDataProtectionSignal1
MarketCompetitionSignal1
```

## Executive attention signals

```text
MonitorSignal1
MonitorSignal2
EngageSignal1
EngageSignal2
PrepareSignal1
PrepareSignal2
PolicyReviewSignal1
PolicyReviewSignal2
PolicyReviewSignal3
```

## Assumptions

```text
Assumption1
Assumption2
Assumption3
Assumption4
```

## References

Ten fixed reference fields are retained:

```text
Reference1
Reference2
Reference3
Reference4
Reference5
Reference6
Reference7
Reference8
Reference9
Reference10
```

## Rebuilding the master

Run from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File ".\tools\New-SharePointWordTemplate.ps1" -Force
```

The script requires Microsoft Word desktop. Word inserts and saves the native content controls while preserving the embedded images and existing formatting.
