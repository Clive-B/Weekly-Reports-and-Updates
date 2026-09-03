[CmdletBinding()]
param(
    [string]$BaseUrl = "http://localhost:5188",
    [string]$AgentKey = "local-test-agent-key"
)

$ErrorActionPreference = "Stop"
$base = $BaseUrl.TrimEnd("/")
$headers = @{ "X-Agent-Key" = $AgentKey }

Write-Host "Checking the local watchdog endpoint..." -ForegroundColor Cyan
$watchdog = Invoke-RestMethod `
    -Uri "$base/api/agent/watchdog-check" `
    -Method Post `
    -Headers $headers `
    -ContentType "application/json" `
    -Body "{}"

$weekStart = [string]$watchdog.weekStart
$weekEnd = [string]$watchdog.weekEnd

$trends = 1..3 | ForEach-Object {
    @{
        title = "Local Test Trend $_"
        whatHappened = "Synthetic development $_ created for local testing."
        whyItMatters = "This verifies that report content reaches the webpage."
        signal = "Local pipeline test signal $_."
        riskOpportunity = "Testing opportunity $_."
    }
}

$references = 1..5 | ForEach-Object {
    @{
        title = "Local Test Source $_"
        url = "https://example.com/test-$_"
        publisher = "Local Test Publisher"
        publishedAt = $weekEnd
    }
}

$payload = @{
    weekStart = $weekStart
    weekEnd = $weekEnd
    title = "Local Weekly Trends Pipeline Test"
    autoPublishIfValid = $true
    content = @{
        reportingWeek = "$weekStart to $weekEnd"
        preparedBy = "Innovation Unit"
        executiveSnapshot = "Synthetic content created to verify the local agent publication pipeline."
        priorityTrends = $trends
        horizon = @(
            @{
                title = "Emerging Connectivity Models"
                body = "Monitor satellite and direct-to-device developments."
            }
        )
        implications = @(
            @{
                title = "Regulatory Readiness"
                body = "Review whether existing frameworks cover emerging technologies."
            }
        )
        attentionSignals = @(
            "Monitor emerging technology developments."
        )
        assumptions = @(
            "This report contains synthetic local-test content."
        )
        references = $references
    }
}

Write-Host "Submitting a synthetic report for $weekStart through $weekEnd..." -ForegroundColor Cyan
$result = Invoke-RestMethod `
    -Uri "$base/api/agent/run" `
    -Method Post `
    -Headers $headers `
    -ContentType "application/json" `
    -Body ($payload | ConvertTo-Json -Depth 10)

$current = Invoke-RestMethod -Uri "$base/api/reports/current"

Write-Host "Local agent pipeline test passed." -ForegroundColor Green
[pscustomobject]@{
    SubmittedReportId = $result.meta.id
    SubmittedStatus = $result.meta.status
    PublicationMode = $result.meta.publicationMode
    CurrentReportId = $current.meta.id
    CurrentTitle = $current.meta.title
    TrendCount = $current.content.priorityTrends.Count
    ReferenceCount = $current.content.references.Count
}
