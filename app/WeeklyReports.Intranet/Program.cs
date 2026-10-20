using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using System.IO.Compression;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.Mvc;

var builder = WebApplication.CreateBuilder(args);

if (builder.Configuration.GetValue<bool>("ReverseProxy:TrustForwardedHeaders"))
{
    builder.Services.Configure<ForwardedHeadersOptions>(options =>
    {
        options.ForwardedHeaders = ForwardedHeaders.XForwardedFor
            | ForwardedHeaders.XForwardedProto
            | ForwardedHeaders.XForwardedHost;
        options.KnownNetworks.Clear();
        options.KnownProxies.Clear();
    });
}

builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(options =>
    {
        options.Cookie.Name = "nca_weekly_reports_auth";
        options.Cookie.HttpOnly = true;
        options.Cookie.SameSite = SameSiteMode.Lax;
        options.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;
        options.LoginPath = "/";
        options.AccessDeniedPath = "/";
        options.SlidingExpiration = true;
        options.Events.OnRedirectToLogin = context =>
        {
            if (context.Request.Path.StartsWithSegments("/api"))
            {
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                return Task.CompletedTask;
            }

            context.Response.Redirect(context.RedirectUri);
            return Task.CompletedTask;
        };
        options.Events.OnRedirectToAccessDenied = context =>
        {
            if (context.Request.Path.StartsWithSegments("/api"))
            {
                context.Response.StatusCode = StatusCodes.Status403Forbidden;
                return Task.CompletedTask;
            }

            context.Response.Redirect(context.RedirectUri);
            return Task.CompletedTask;
        };
    });
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("Editor", policy => policy.RequireRole("Editor", "Reviewer", "Admin"));
    options.AddPolicy("Reviewer", policy => policy.RequireRole("Reviewer", "Admin"));
    options.AddPolicy("Admin", policy => policy.RequireRole("Admin"));
});
builder.Services.AddSingleton<ReportStore>();
builder.Services.AddSingleton<PasswordVerifier>();
builder.Services.AddDataProtection();
builder.Services.AddHttpClient("OpenAI", client => client.Timeout = TimeSpan.FromMinutes(6));
builder.Services.AddSingleton<ProviderCredentialStore>();
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.Converters.Add(new JsonStringEnumConverter());
});

var app = builder.Build();

app.UseForwardedHeaders();
app.UseDefaultFiles();
app.UseStaticFiles();
app.UseAuthentication();
app.UseAuthorization();

app.MapGet("/api/session", (ClaimsPrincipal user) =>
{
    if (user.Identity?.IsAuthenticated != true)
    {
        return Results.Ok(new { authenticated = false });
    }

    return Results.Ok(new
    {
        authenticated = true,
        user = user.Identity.Name,
        roles = user.Claims.Where(c => c.Type == ClaimTypes.Role).Select(c => c.Value).Distinct().ToArray()
    });
});

app.MapGet("/api/health", (ReportStore store) => Results.Ok(store.CheckStorage()));

app.MapGet("/api/admin/diagnostics", [Authorize(Policy = "Admin")] (
    IConfiguration config,
    ReportStore store) =>
{
    return Results.Ok(store.GetDiagnostics(config));
});

app.MapGet("/api/admin/provider-key/status", [Authorize(Policy = "Admin")] (
    ProviderCredentialStore credentials) => Results.Ok(credentials.Status()));

app.MapPost("/api/admin/provider-key", [Authorize(Policy = "Admin")] async (
    [FromBody] ProviderKeyRequest request,
    ProviderCredentialStore credentials,
    IHttpClientFactory clients,
    CancellationToken cancellationToken) =>
{
    var apiKey = request.ApiKey?.Trim();
    if (string.IsNullOrWhiteSpace(apiKey))
    {
        return Results.BadRequest(new { error = "Enter an API key." });
    }

    using var validation = new HttpRequestMessage(HttpMethod.Get, "https://api.openai.com/v1/models");
    validation.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", apiKey);
    using var response = await clients.CreateClient("OpenAI").SendAsync(validation, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
    if (!response.IsSuccessStatusCode)
    {
        return Results.BadRequest(new { error = "The provider did not accept this API key. Nothing was saved." });
    }

    var status = credentials.Save(apiKey);
    return Results.Ok(status);
});

app.MapDelete("/api/admin/provider-key", [Authorize(Policy = "Admin")] (
    ProviderCredentialStore credentials) => Results.Ok(credentials.Remove()));

app.MapPost("/api/login", async (
    [FromBody] LoginRequest request,
    IConfiguration config,
    PasswordVerifier verifier,
    HttpContext context) =>
{
    var users = config.GetSection("Auth:Users").Get<List<AppUser>>() ?? [];
    var user = users.FirstOrDefault(u => string.Equals(u.Username, request.Username, StringComparison.OrdinalIgnoreCase));

    if (user is null || string.IsNullOrWhiteSpace(user.PasswordHash) || !verifier.Verify(request.Password, user.PasswordHash))
    {
        return Results.Unauthorized();
    }

    var claims = new List<Claim>
    {
        new(ClaimTypes.Name, user.Username),
        new("display_name", user.DisplayName ?? user.Username)
    };
    claims.AddRange(user.Roles.Distinct().Select(role => new Claim(ClaimTypes.Role, role)));

    await context.SignInAsync(
        CookieAuthenticationDefaults.AuthenticationScheme,
        new ClaimsPrincipal(new ClaimsIdentity(claims, CookieAuthenticationDefaults.AuthenticationScheme)));

    return Results.Ok(new { authenticated = true, user = user.Username, roles = user.Roles.Distinct().ToArray() });
});

app.MapPost("/api/logout", async (HttpContext context) =>
{
    await context.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
    return Results.Ok(new { authenticated = false });
});

app.MapGet("/api/reports", [Authorize] (ReportStore store) => Results.Ok(store.List()));

app.MapGet("/api/reports/current", (ReportStore store) =>
{
    var current = store.List().FirstOrDefault(r => r.Status == ReportStatus.Published);
    if (current is null) return Results.NotFound();

    var report = store.Get(current.Id)!;
    return Results.Ok(new PublicReport(
        new PublicReportMeta(
            report.Meta.Id,
            report.Meta.Title,
            report.Meta.WeekStart,
            report.Meta.WeekEnd,
            report.Meta.Status,
            report.Meta.PublicationMode,
            report.Meta.UpdatedAt),
        report.Content));
});

app.MapGet("/api/reports/by-week", (
    DateOnly weekStart,
    DateOnly weekEnd,
    HttpRequest request,
    ClaimsPrincipal user,
    IConfiguration config,
    ReportStore store) =>
{
    if (user.Identity?.IsAuthenticated != true && !HasValidAgentKey(request, config))
    {
        return Results.Unauthorized();
    }

    var report = store.GetByWeek(weekStart, weekEnd);
    return report is null ? Results.NotFound() : Results.Ok(report);
});

app.MapGet("/api/reports/{id}", [Authorize] (string id, ReportStore store) =>
{
    var report = store.Get(id);
    return report is null ? Results.NotFound() : Results.Ok(report);
});

app.MapPost("/api/reports/upload", [Authorize(Policy = "Editor")] async (
    HttpRequest request,
    ClaimsPrincipal user,
    ReportStore store) =>
{
    if (!request.HasFormContentType)
    {
        return Results.BadRequest("Expected multipart form data.");
    }

    var form = await request.ReadFormAsync();
    var file = form.Files.GetFile("file");
    if (file is null || !file.FileName.EndsWith(".docx", StringComparison.OrdinalIgnoreCase))
    {
        return Results.BadRequest("Upload a .docx file.");
    }

    var weekStart = DateOnly.Parse(form["weekStart"]!);
    var weekEnd = DateOnly.Parse(form["weekEnd"]!);
    var title = string.IsNullOrWhiteSpace(form["title"]) ? file.FileName : form["title"].ToString();

    var report = store.CreateDraft(weekStart, weekEnd, title, user.Identity?.Name ?? "unknown", PublicationMode.Uploaded);
    await using var stream = file.OpenReadStream();
    await store.SaveDocxAsync(report.Id, stream, file.FileName);
    store.AppendAudit(report.Id, "uploaded_docx", user.Identity?.Name ?? "unknown", "Word report uploaded by authenticated editor.");
    return Results.Ok(store.Get(report.Id));
});

app.MapPost("/api/reports/draft", [Authorize(Policy = "Editor")] (
    [FromBody] DraftRequest request,
    ClaimsPrincipal user,
    ReportStore store) =>
{
    var report = store.CreateDraft(
        request.WeekStart,
        request.WeekEnd,
        request.Title,
        user.Identity?.Name ?? "unknown",
        request.Mode);

    store.SaveContent(report.Id, request.Content);
    store.WriteDocx(report.Id, request.Content);
    store.AppendAudit(report.Id, "draft_saved", user.Identity?.Name ?? "unknown", "Draft content saved and repo-local Word document generated.");
    return Results.Ok(store.Get(report.Id));
});

app.MapPut("/api/reports/{id}/content", [Authorize(Policy = "Editor")] (
    string id,
    [FromBody] ReportContent content,
    ClaimsPrincipal user,
    ReportStore store) =>
{
    var report = store.Get(id);
    if (report is null) return Results.NotFound();
    if (report.Meta.Status == ReportStatus.Published) return Results.BadRequest("Published reports cannot be edited. Create a revised draft.");

    store.SaveContent(id, content);
    store.WriteDocx(id, content);
    store.AppendAudit(id, "content_updated", user.Identity?.Name ?? "unknown", "Authenticated editor updated report content.");
    return Results.Ok(store.Get(id));
});

app.MapPut("/api/reports/{id}/source-links", [Authorize(Policy = "Admin")] (
    string id,
    [FromBody] ImplicationSourceLinksRequest request,
    ClaimsPrincipal user,
    ReportStore store) =>
{
    var report = store.Get(id);
    if (report is null) return Results.NotFound();
    if (request.Links.Count != report.Content.Implications.Count)
        return Results.BadRequest("Provide exactly one source link for every implication card.");

    var implications = report.Content.Implications
        .Select((item, index) => item with
        {
            SourceSection = request.Links[index].SourceSection,
            SourceItemIndex = request.Links[index].SourceItemIndex
        })
        .ToList();
    var content = report.Content with { Implications = implications };
    if (content.Implications.Any(item => !HasValidImplicationSource(item, content)))
        return Results.BadRequest("Every source link must point to an existing item in Sections 1, 2, or 3.");

    store.SaveContent(id, content);
    store.WriteDocx(id, content);
    store.AppendAudit(id, "source_links_updated", user.Identity?.Name ?? "unknown", "Administrator updated implication-card navigation links; report text and approval were preserved.");
    return Results.Ok(store.Get(id));
});

app.MapPost("/api/reports/{id}/submit-review", [Authorize(Policy = "Editor")] (
    string id,
    ClaimsPrincipal user,
    ReportStore store) =>
{
    var updated = store.ChangeStatus(id, ReportStatus.PendingReview, user.Identity?.Name ?? "unknown", "submitted_for_review");
    return updated is null ? Results.NotFound() : Results.Ok(updated);
});

app.MapPost("/api/reports/{id}/approve", [Authorize(Policy = "Reviewer")] (
    string id,
    ClaimsPrincipal user,
    ReportStore store) =>
{
    var updated = store.Publish(id, user.Identity?.Name ?? "unknown", PublicationMode.HumanApproved);
    return updated is null ? Results.NotFound() : Results.Ok(updated);
});

app.MapPost("/api/reports/{id}/reject", [Authorize(Policy = "Reviewer")] (
    string id,
    [FromBody] RejectRequest request,
    ClaimsPrincipal user,
    ReportStore store) =>
{
    var updated = store.Reject(id, user.Identity?.Name ?? "unknown", request.Reason);
    return updated is null ? Results.NotFound() : Results.Ok(updated);
});

app.MapPost("/api/reports/{id}/auto-publish", (
    string id,
    HttpRequest request,
    IConfiguration config,
    ReportStore store) =>
{
    if (!HasValidAgentKey(request, config)) return Results.Unauthorized();
    if (!config.GetValue<bool>("Agent:AllowAutoPublish")) return Results.StatusCode(StatusCodes.Status403Forbidden);
    var updated = store.Publish(id, "weekly-trends-agent", PublicationMode.AutoPublished);
    return updated is null ? Results.NotFound() : Results.Ok(updated);
});

app.MapPost("/api/agent/run", (
    [FromBody] AgentRunRequest request,
    HttpRequest httpRequest,
    IConfiguration config,
    ReportStore store) =>
{
    if (!HasValidAgentKey(httpRequest, config)) return Results.Unauthorized();

    var (weekStart, weekEnd) = PreviousMondayToFriday(DateOnly.FromDateTime(DateTime.Today));
    var issues = ValidateAgentContent(request.Content);
    var mode = issues.Count == 0 ? PublicationMode.AgentGenerated : PublicationMode.AgentGeneratedNeedsReview;

    var report = store.CreateDraft(
        request.WeekStart ?? weekStart,
        request.WeekEnd ?? weekEnd,
        request.Title ?? $"Week {FormatOrdinalDate(weekStart)}-{FormatOrdinalDate(weekEnd)} {weekEnd:MMMM yyyy} Report Emerging Trends & Technologies",
        "weekly-trends-agent",
        mode);

    store.SaveContent(report.Id, request.Content);
    store.WriteDocx(report.Id, request.Content);
    store.SaveValidation(report.Id, issues);
    store.ChangeStatus(report.Id, ReportStatus.PendingReview, "weekly-trends-agent", "agent_draft_generated");

    if (request.AutoPublishIfValid && config.GetValue<bool>("Agent:AllowAutoPublish") && issues.Count == 0)
    {
        store.Publish(report.Id, "weekly-trends-agent", PublicationMode.AutoPublished);
    }

    return Results.Ok(store.Get(report.Id));
});

app.MapPost("/api/agent/provider-response", async (
    [FromBody] JsonElement providerRequest,
    HttpRequest httpRequest,
    IConfiguration config,
    ProviderCredentialStore credentials,
    IHttpClientFactory clients,
    CancellationToken cancellationToken) =>
{
    if (!HasValidAgentKey(httpRequest, config)) return Results.Unauthorized();

    var apiKey = credentials.Get();
    if (string.IsNullOrWhiteSpace(apiKey))
    {
        return Results.Problem("The provider API key has not been configured by an administrator.", statusCode: StatusCodes.Status503ServiceUnavailable);
    }

    using var outbound = new HttpRequestMessage(HttpMethod.Post, "https://api.openai.com/v1/responses");
    outbound.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", apiKey);
    outbound.Content = new StringContent(providerRequest.GetRawText(), Encoding.UTF8, "application/json");
    using var response = await clients.CreateClient("OpenAI").SendAsync(outbound, HttpCompletionOption.ResponseContentRead, cancellationToken);
    var body = await response.Content.ReadAsStringAsync(cancellationToken);
    return Results.Content(body, "application/json", Encoding.UTF8, (int)response.StatusCode);
});

app.MapGet("/api/agent/provider-key/status", (
    HttpRequest request,
    IConfiguration config,
    ProviderCredentialStore credentials) =>
{
    if (!HasValidAgentKey(request, config)) return Results.Unauthorized();
    return Results.Ok(new { configured = credentials.Status().Configured });
});

app.MapPost("/api/agent/watchdog-check", (
    [FromBody] WatchdogCheckRequest request,
    HttpRequest httpRequest,
    IConfiguration config,
    ReportStore store) =>
{
    if (!HasValidAgentKey(httpRequest, config)) return Results.Unauthorized();

    var today = request.Today ?? DateOnly.FromDateTime(DateTime.Today);
    var (weekStart, weekEnd) = request.WeekStart.HasValue && request.WeekEnd.HasValue
        ? (request.WeekStart.Value, request.WeekEnd.Value)
        : PreviousMondayToFriday(today);

    var report = store.GetByWeek(weekStart, weekEnd);
    if (report is null)
    {
        store.AppendSystemAudit("watchdog_triggered_agent", "weekly-trends-agent", $"No report found for {weekStart:yyyy-MM-dd} to {weekEnd:yyyy-MM-dd}.");
        return Results.Ok(new WatchdogCheckResponse(weekStart, weekEnd, false, true, null, "No report exists for the target reporting week."));
    }

    var isSyntheticPlaceholder = string.Equals(report.Content.PreparedBy, "Test Deployment", StringComparison.OrdinalIgnoreCase)
        || report.Content.ReportingWeek.Contains("Synthetic deployment verification", StringComparison.OrdinalIgnoreCase);
    var published = report.Meta.Status == ReportStatus.Published && !isSyntheticPlaceholder;
    store.AppendAudit(
        report.Meta.Id,
        published ? "watchdog_skipped" : "watchdog_triggered_agent",
        "weekly-trends-agent",
        published
            ? "Published report already exists for the target reporting week."
            : isSyntheticPlaceholder
                ? "Synthetic deployment placeholder detected; agent fallback should replace it."
                : $"Report exists but status is {report.Meta.Status}; agent fallback should run.");

    return Results.Ok(new WatchdogCheckResponse(
        weekStart,
        weekEnd,
        published,
        !published,
        report.Meta.Id,
        published
            ? "Published report already exists."
            : isSyntheticPlaceholder
                ? "Synthetic deployment placeholder must be replaced."
                : $"Report status is {report.Meta.Status}."));
});

app.MapGet("/api/tools/hash-password", [Authorize(Policy = "Admin")] (
    string password,
    PasswordVerifier verifier) => Results.Ok(new { hash = verifier.Hash(password) }));

app.Run();

static bool HasValidAgentKey(HttpRequest request, IConfiguration config)
{
    var configured = config["Agent:ApiKey"];
    if (string.IsNullOrWhiteSpace(configured)) return false;
    return request.Headers.TryGetValue("X-Agent-Key", out var supplied) && supplied == configured;
}

static (DateOnly Start, DateOnly End) PreviousMondayToFriday(DateOnly today)
{
    var daysSinceMonday = ((int)today.DayOfWeek - (int)DayOfWeek.Monday + 7) % 7;
    var thisMonday = today.AddDays(-daysSinceMonday);
    var previousMonday = thisMonday.AddDays(-7);
    return (previousMonday, previousMonday.AddDays(4));
}

static string FormatOrdinalDate(DateOnly date)
{
    var day = date.Day;
    var suffix = (day % 100) is 11 or 12 or 13 ? "th" : (day % 10) switch
    {
        1 => "st",
        2 => "nd",
        3 => "rd",
        _ => "th"
    };
    return $"{day}{suffix}";
}

static List<string> ValidateAgentContent(ReportContent content)
{
    var issues = new List<string>();
    if (string.IsNullOrWhiteSpace(content.ExecutiveSnapshot)) issues.Add("Executive snapshot is missing.");
    if (content.PriorityTrends.Count < 3) issues.Add("At least three priority trends are expected.");
    if (content.References.Count < 5) issues.Add("At least five references are expected before unattended auto-publication.");
    if (content.References.Any(r => !Uri.TryCreate(r.Url, UriKind.Absolute, out var uri) || (uri.Scheme != Uri.UriSchemeHttps && uri.Scheme != Uri.UriSchemeHttp)))
        issues.Add("Every reference must include a valid HTTP or HTTPS URL.");
    if (content.Implications.Any(i => !HasValidImplicationSource(i, content)))
        issues.Add("Every regulatory or strategic implication must link to an existing item in Sections 1, 2, or 3.");
    if (content.Assumptions.Count == 0) issues.Add("Assumption exposure notes are missing.");
    return issues;
}

static bool HasValidImplicationSource(ImplicationItem implication, ReportContent content) => implication.SourceSection switch
{
    "executiveSnapshot" => implication.SourceItemIndex == 1,
    "priorityTrends" => implication.SourceItemIndex >= 1 && implication.SourceItemIndex <= content.PriorityTrends.Count,
    "horizon" => implication.SourceItemIndex >= 1 && implication.SourceItemIndex <= content.Horizon.Count,
    _ => false
};

sealed class ReportStore(IWebHostEnvironment env, IConfiguration config)
{
    private readonly string _repoRoot = ResolveRepoRoot(env, config);
    private readonly JsonSerializerOptions _json = new(JsonSerializerDefaults.Web) { WriteIndented = true };

    public StorageHealth CheckStorage()
    {
        try
        {
            var root = ReportsRoot();
            var probePath = Path.Combine(root, ".storage-health");
            File.WriteAllText(probePath, DateTimeOffset.UtcNow.ToString("O"));
            File.Delete(probePath);
            return new StorageHealth(true, null);
        }
        catch (Exception ex)
        {
            return new StorageHealth(false, ex.Message);
        }
    }

    public string GetSecretsRoot()
    {
        var root = Path.Combine(ReportsRoot(), ".secrets");
        Directory.CreateDirectory(root);
        return root;
    }

    public AppDiagnostics GetDiagnostics(IConfiguration config)
    {
        var health = CheckStorage();
        var reportsRoot = "";
        string? reportsRootError = null;
        var reports = Array.Empty<ReportSummary>();
        var filesUnderReportsRoot = 0;
        var systemAuditTail = Array.Empty<string>();

        try
        {
            reportsRoot = ReportsRoot();
            reports = List().ToArray();
            filesUnderReportsRoot = Directory.Exists(reportsRoot)
                ? Directory.GetFiles(reportsRoot, "*", SearchOption.AllDirectories).Length
                : 0;

            var systemAuditPath = Path.Combine(reportsRoot, "system-audit.jsonl");
            if (File.Exists(systemAuditPath))
            {
                systemAuditTail = File.ReadLines(systemAuditPath).TakeLast(20).ToArray();
            }
        }
        catch (Exception ex)
        {
            reportsRootError = ex.Message;
        }

        return new AppDiagnostics(
            DateTimeOffset.UtcNow,
            Path.GetFullPath(env.ContentRootPath),
            _repoRoot,
            reportsRoot,
            reportsRootError,
            health,
            !string.IsNullOrWhiteSpace(config["Agent:ApiKey"]),
            config.GetValue<bool>("Agent:AllowAutoPublish"),
            reports.Length,
            reports.GroupBy(r => r.Status.ToString()).ToDictionary(g => g.Key, g => g.Count()),
            reports.Take(10).ToArray(),
            filesUnderReportsRoot,
            systemAuditTail);
    }

    public IReadOnlyList<ReportSummary> List()
    {
        var root = ReportsRoot();
        if (!Directory.Exists(root)) return [];

        return Directory.GetFiles(root, "report.json", SearchOption.AllDirectories)
            .Select(path => JsonSerializer.Deserialize<ReportMeta>(File.ReadAllText(path), _json))
            .Where(meta => meta is not null)
            .Select(meta => new ReportSummary(
                meta!.Id,
                meta.Title,
                meta.WeekStart,
                meta.WeekEnd,
                meta.Status,
                meta.PublicationMode,
                meta.UpdatedAt))
            .OrderByDescending(r => r.WeekStart)
            .ThenByDescending(r => r.UpdatedAt)
            .ToList();
    }

    public ReportBundle? Get(string id)
    {
        var dir = ReportDir(id);
        var metaPath = Path.Combine(dir, "report.json");
        if (!File.Exists(metaPath)) return null;

        var meta = JsonSerializer.Deserialize<ReportMeta>(File.ReadAllText(metaPath), _json)!;
        var contentPath = Path.Combine(dir, "content.json");
        var approvalPath = Path.Combine(dir, "approval.json");
        var validationPath = Path.Combine(dir, "validation.json");
        var auditPath = Path.Combine(dir, "audit.jsonl");

        return new ReportBundle(
            meta,
            File.Exists(contentPath) ? JsonSerializer.Deserialize<ReportContent>(File.ReadAllText(contentPath), _json) ?? new ReportContent() : new ReportContent(),
            File.Exists(approvalPath) ? JsonSerializer.Deserialize<ApprovalRecord>(File.ReadAllText(approvalPath), _json) : null,
            File.Exists(validationPath) ? JsonSerializer.Deserialize<List<string>>(File.ReadAllText(validationPath), _json) ?? [] : [],
            File.Exists(auditPath) ? File.ReadAllLines(auditPath).Where(l => !string.IsNullOrWhiteSpace(l)).Select(l => JsonSerializer.Deserialize<AuditRecord>(l, _json)!).ToList() : []);
    }

    public ReportBundle? GetByWeek(DateOnly weekStart, DateOnly weekEnd)
    {
        var id = $"{weekStart:yyyy-MM-dd}_to_{weekEnd:yyyy-MM-dd}";
        return Get(id);
    }

    public ReportMeta CreateDraft(DateOnly weekStart, DateOnly weekEnd, string title, string actor, PublicationMode mode)
    {
        var id = $"{weekStart:yyyy-MM-dd}_to_{weekEnd:yyyy-MM-dd}";
        var dir = ReportDir(id);
        Directory.CreateDirectory(dir);

        var now = DateTimeOffset.UtcNow;
        var meta = new ReportMeta(
            id,
            title,
            weekStart,
            weekEnd,
            ReportStatus.Draft,
            mode,
            actor,
            now,
            now,
            RelativeToRepo(Path.Combine(dir, "report.docx")));

        SaveMeta(meta);
        AppendAudit(id, "draft_created", actor, $"Draft created with mode {mode}.");
        return meta;
    }

    public void SaveContent(string id, ReportContent content)
    {
        File.WriteAllText(Path.Combine(ReportDir(id), "content.json"), JsonSerializer.Serialize(content, _json));
        Touch(id);
    }

    public async Task SaveDocxAsync(string id, Stream input, string originalFileName)
    {
        var dir = ReportDir(id);
        Directory.CreateDirectory(dir);
        var docxPath = Path.Combine(dir, "report.docx");
        await using var output = File.Create(docxPath);
        await input.CopyToAsync(output);
        File.WriteAllText(Path.Combine(dir, "source-upload.txt"), originalFileName);
        Touch(id);
    }

    public void WriteDocx(string id, ReportContent content)
    {
        var path = Path.Combine(ReportDir(id), "report.docx");
        using var output = File.Create(path);
        using var archive = new ZipArchive(output, ZipArchiveMode.Create);
        WriteZipEntry(archive, "[Content_Types].xml", ContentTypesXml());
        WriteZipEntry(archive, "_rels/.rels", RelationshipsXml());
        WriteZipEntry(archive, "word/_rels/document.xml.rels", WordRelationshipsXml(content));
        WriteZipEntry(archive, "docProps/core.xml", CorePropertiesXml(content.PreparedBy));
        WriteZipEntry(archive, "word/document.xml", DocumentXml(content));
        Touch(id);
    }

    public ReportBundle? ChangeStatus(string id, ReportStatus status, string actor, string action)
    {
        var bundle = Get(id);
        if (bundle is null) return null;
        SaveMeta(bundle.Meta with { Status = status, UpdatedAt = DateTimeOffset.UtcNow });
        AppendAudit(id, action, actor, $"Status changed to {status}.");
        return Get(id);
    }

    public ReportBundle? Publish(string id, string actor, PublicationMode mode)
    {
        var bundle = Get(id);
        if (bundle is null) return null;

        var now = DateTimeOffset.UtcNow;
        var approval = new ApprovalRecord(mode, actor == "weekly-trends-agent" ? null : actor, now, mode == PublicationMode.AutoPublished);
        File.WriteAllText(Path.Combine(ReportDir(id), "approval.json"), JsonSerializer.Serialize(approval, _json));
        SaveMeta(bundle.Meta with { Status = ReportStatus.Published, PublicationMode = mode, UpdatedAt = now });
        AppendAudit(id, mode == PublicationMode.AutoPublished ? "auto_published" : "approved_and_published", actor, "Report published.");
        return Get(id);
    }

    public ReportBundle? Reject(string id, string actor, string reason)
    {
        var bundle = Get(id);
        if (bundle is null) return null;
        SaveMeta(bundle.Meta with { Status = ReportStatus.Rejected, UpdatedAt = DateTimeOffset.UtcNow });
        AppendAudit(id, "rejected", actor, reason);
        return Get(id);
    }

    public void SaveValidation(string id, List<string> issues)
    {
        File.WriteAllText(Path.Combine(ReportDir(id), "validation.json"), JsonSerializer.Serialize(issues, _json));
    }

    public void AppendAudit(string id, string action, string actor, string details)
    {
        var record = new AuditRecord(DateTimeOffset.UtcNow, actor, action, details);
        File.AppendAllText(Path.Combine(ReportDir(id), "audit.jsonl"), JsonSerializer.Serialize(record, _json).ReplaceLineEndings("") + Environment.NewLine);
    }

    public void AppendSystemAudit(string action, string actor, string details)
    {
        var record = new AuditRecord(DateTimeOffset.UtcNow, actor, action, details);
        File.AppendAllText(Path.Combine(ReportsRoot(), "system-audit.jsonl"), JsonSerializer.Serialize(record, _json).ReplaceLineEndings("") + Environment.NewLine);
    }

    private string ReportsRoot()
    {
        var root = Path.GetFullPath(Path.Combine(_repoRoot, config["Reports:Root"] ?? "reports"));
        if (!root.StartsWith(_repoRoot, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("Reports root must remain inside the repository.");
        }
        Directory.CreateDirectory(root);
        return root;
    }

    private static string ResolveRepoRoot(IWebHostEnvironment env, IConfiguration config)
    {
        var configured = config["Reports:RepoRoot"];
        if (!string.IsNullOrWhiteSpace(configured))
        {
            return Path.GetFullPath(configured);
        }

        var contentRoot = Path.GetFullPath(env.ContentRootPath);
        var current = new DirectoryInfo(contentRoot);
        var parent = current.Parent;
        var grandparent = parent?.Parent;
        if (string.Equals(current.Name, "WeeklyReports.Intranet", StringComparison.OrdinalIgnoreCase)
            && string.Equals(parent?.Name, "app", StringComparison.OrdinalIgnoreCase)
            && grandparent is not null)
        {
            return grandparent.FullName;
        }

        return contentRoot;
    }

    private string ReportDir(string id)
    {
        if (!Regex.IsMatch(id, "^[0-9]{4}-[0-9]{2}-[0-9]{2}_to_[0-9]{4}-[0-9]{2}-[0-9]{2}$"))
        {
            throw new InvalidOperationException("Invalid report id.");
        }

        var year = id[..4];
        var dir = Path.GetFullPath(Path.Combine(ReportsRoot(), year, id));
        if (!dir.StartsWith(ReportsRoot(), StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("Report path must remain inside the reports directory.");
        }
        return dir;
    }

    private void SaveMeta(ReportMeta meta)
    {
        Directory.CreateDirectory(ReportDir(meta.Id));
        File.WriteAllText(Path.Combine(ReportDir(meta.Id), "report.json"), JsonSerializer.Serialize(meta, _json));
    }

    private void Touch(string id)
    {
        var bundle = Get(id);
        if (bundle is not null)
        {
            SaveMeta(bundle.Meta with { UpdatedAt = DateTimeOffset.UtcNow });
        }
    }

    private string RelativeToRepo(string path) => Path.GetRelativePath(_repoRoot, path).Replace('\\', '/');

    private static void WriteZipEntry(ZipArchive archive, string name, string content)
    {
        var entry = archive.CreateEntry(name);
        using var writer = new StreamWriter(entry.Open(), Encoding.UTF8);
        writer.Write(content);
    }

    private static string ContentTypesXml() => """<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/></Types>""";

    private static string RelationshipsXml() => """<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>""";

    private static string WordRelationshipsXml(ReportContent content)
    {
        var links = content.References
            .Select((reference, index) => (reference, index))
            .Where(item => IsHttpUrl(item.reference.Url))
            .Select(item => $"<Relationship Id=\"rIdRef{item.index + 1}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"{Xml(item.reference.Url)}\" TargetMode=\"External\"/>");
        return $"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">{string.Join("", links)}</Relationships>";
    }

    private static string CorePropertiesXml(string preparedBy) => $"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?><cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:creator>{Xml(preparedBy)}</dc:creator><cp:lastModifiedBy>{Xml(preparedBy)}</cp:lastModifiedBy><dcterms:created xsi:type="dcterms:W3CDTF">{DateTimeOffset.UtcNow:O}</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">{DateTimeOffset.UtcNow:O}</dcterms:modified></cp:coreProperties>""";

    private static string DocumentXml(ReportContent content)
    {
        var body = new StringBuilder();
        void AddParagraph(string text) => body.Append($"<w:p><w:r><w:t>{Xml(text)}</w:t></w:r></w:p>");
        void AddBookmarkParagraph(string text, int id, string name) => body.Append($"<w:p><w:bookmarkStart w:id=\"{id}\" w:name=\"{name}\"/><w:r><w:t>{Xml(text)}</w:t></w:r><w:bookmarkEnd w:id=\"{id}\"/></w:p>");
        void AddInternalLinkParagraph(string text, string anchor) => body.Append($"<w:p><w:hyperlink w:anchor=\"{anchor}\" w:history=\"1\"><w:r><w:rPr><w:color w:val=\"0563C1\"/><w:u w:val=\"single\"/></w:rPr><w:t>{Xml(text)}</w:t></w:r></w:hyperlink></w:p>");

        var openingParagraphs = new[]
        {
            "NATIONAL COMMUNICATIONS AUTHORITY",
            "Innovation & Policy",
            "EMERGING TRENDS AND TECHNOLOGIES",
            "NCA WEEKLY EMERGING TECHNOLOGIES & TRENDS REPORT",
            $"Reporting Week: {content.ReportingWeek}",
            $"Prepared by: {content.PreparedBy}",
            "1. Executive Snapshot"
        };
        foreach (var paragraph in openingParagraphs) AddParagraph(paragraph);
        AddBookmarkParagraph(content.ExecutiveSnapshot, 1, "snapshot_1");
        AddParagraph("2. Priority Trends to Watch");

        foreach (var (trend, index) in content.PriorityTrends.Select((value, index) => (value, index)))
        {
            var text = $"{trend.Title}: {trend.WhatHappened} Why It Matters: {trend.WhyItMatters} Signal: {trend.Signal} Risk/Opportunity: {trend.RiskOpportunity}";
            AddBookmarkParagraph(text, 100 + index, $"trend_{index + 1}");
        }

        AddParagraph("3. Technologies & Developments on the Horizon");
        foreach (var (item, index) in content.Horizon.Select((value, index) => (value, index)))
            AddBookmarkParagraph($"{item.Title}: {item.Body}", 200 + index, $"horizon_{index + 1}");
        AddParagraph("4. Regulatory & Strategic Implications");
        foreach (var implication in content.Implications)
        {
            var implicationText = $"{implication.Title}: {implication.Body}";
            var anchor = implication.SourceSection switch
            {
                "executiveSnapshot" when implication.SourceItemIndex == 1 => "snapshot_1",
                "priorityTrends" when implication.SourceItemIndex >= 1 && implication.SourceItemIndex <= content.PriorityTrends.Count => $"trend_{implication.SourceItemIndex}",
                "horizon" when implication.SourceItemIndex >= 1 && implication.SourceItemIndex <= content.Horizon.Count => $"horizon_{implication.SourceItemIndex}",
                _ => null
            };
            if (anchor is null) AddParagraph(implicationText);
            else AddInternalLinkParagraph(implicationText, anchor);
        }
        AddParagraph("5. Executive Attention Signals");
        foreach (var signal in content.AttentionSignals) AddParagraph(signal);
        AddParagraph("6. Assumption Exposure & Analytical Notes");
        foreach (var assumption in content.Assumptions) AddParagraph(assumption);
        AddParagraph("7. References");
        foreach (var (reference, index) in content.References.Select((value, index) => (value, index)))
        {
            if (IsHttpUrl(reference.Url))
                body.Append($"<w:p><w:hyperlink r:id=\"rIdRef{index + 1}\" w:history=\"1\"><w:r><w:rPr><w:color w:val=\"0563C1\"/><w:u w:val=\"single\"/></w:rPr><w:t>{Xml(reference.Title)}</w:t></w:r></w:hyperlink></w:p>");
            else
                AddParagraph(reference.Title);
        }

        return $"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>{body}<w:sectPr/></w:body></w:document>""";
    }

    private static string Xml(string? value) => HtmlEncoder.Default.Encode(value ?? "");
    private static bool IsHttpUrl(string? value) => Uri.TryCreate(value, UriKind.Absolute, out var uri)
        && (uri.Scheme == Uri.UriSchemeHttps || uri.Scheme == Uri.UriSchemeHttp);
}

sealed class PasswordVerifier
{
    public string Hash(string password)
    {
        var salt = RandomNumberGenerator.GetBytes(16);
        var hash = Rfc2898DeriveBytes.Pbkdf2(password, salt, 200_000, HashAlgorithmName.SHA256, 32);
        return $"pbkdf2-sha256:200000:{Convert.ToBase64String(salt)}:{Convert.ToBase64String(hash)}";
    }

    public bool Verify(string password, string encoded)
    {
        var parts = encoded.Split(':');
        if (parts.Length != 4 || parts[0] != "pbkdf2-sha256") return false;
        var iterations = int.Parse(parts[1]);
        var salt = Convert.FromBase64String(parts[2]);
        var expected = Convert.FromBase64String(parts[3]);
        var actual = Rfc2898DeriveBytes.Pbkdf2(password, salt, iterations, HashAlgorithmName.SHA256, expected.Length);
        return CryptographicOperations.FixedTimeEquals(actual, expected);
    }
}

sealed class ProviderCredentialStore(ReportStore reports, IDataProtectionProvider dataProtection)
{
    private readonly IDataProtector _protector = dataProtection.CreateProtector("NCA.WeeklyReports.OpenAI.ApiKey.v1");
    private string CredentialPath => Path.Combine(reports.GetSecretsRoot(), "openai-api-key.protected");
    private string MetadataPath => Path.Combine(reports.GetSecretsRoot(), "openai-api-key.json");

    public ProviderKeyStatus Status()
    {
        if (!File.Exists(CredentialPath)) return new ProviderKeyStatus(false, null);
        DateTimeOffset? updatedAt = null;
        if (File.Exists(MetadataPath))
        {
            try { updatedAt = JsonSerializer.Deserialize<ProviderKeyMetadata>(File.ReadAllText(MetadataPath))?.UpdatedAt; }
            catch (JsonException) { }
        }
        return new ProviderKeyStatus(true, updatedAt);
    }

    public ProviderKeyStatus Save(string apiKey)
    {
        var updatedAt = DateTimeOffset.UtcNow;
        File.WriteAllText(CredentialPath, _protector.Protect(apiKey));
        File.WriteAllText(MetadataPath, JsonSerializer.Serialize(new ProviderKeyMetadata(updatedAt)));
        return new ProviderKeyStatus(true, updatedAt);
    }

    public string? Get()
    {
        if (!File.Exists(CredentialPath)) return null;
        try { return _protector.Unprotect(File.ReadAllText(CredentialPath)); }
        catch (CryptographicException) { return null; }
    }

    public ProviderKeyStatus Remove()
    {
        if (File.Exists(CredentialPath)) File.Delete(CredentialPath);
        if (File.Exists(MetadataPath)) File.Delete(MetadataPath);
        return new ProviderKeyStatus(false, null);
    }
}

record LoginRequest(string Username, string Password);
record ProviderKeyRequest(string? ApiKey);
record ProviderKeyStatus(bool Configured, DateTimeOffset? UpdatedAt);
record ProviderKeyMetadata(DateTimeOffset UpdatedAt);
record RejectRequest(string Reason);
record ImplicationSourceLinksRequest(List<ImplicationSourceLink> Links);
record ImplicationSourceLink(string SourceSection, int SourceItemIndex);
record DraftRequest(DateOnly WeekStart, DateOnly WeekEnd, string Title, PublicationMode Mode, ReportContent Content);
record AgentRunRequest(DateOnly? WeekStart, DateOnly? WeekEnd, string? Title, bool AutoPublishIfValid, ReportContent Content);
record WatchdogCheckRequest(DateOnly? Today, DateOnly? WeekStart, DateOnly? WeekEnd);
record WatchdogCheckResponse(DateOnly WeekStart, DateOnly WeekEnd, bool Published, bool ShouldRunAgent, string? ReportId, string Message);
record StorageHealth(bool StorageOk, string? Error);
record AppDiagnostics(
    DateTimeOffset CheckedAt,
    string ContentRoot,
    string RepoRoot,
    string ReportsRoot,
    string? ReportsRootError,
    StorageHealth Storage,
    bool AgentKeyConfigured,
    bool AgentAutoPublishEnabled,
    int ReportCount,
    Dictionary<string, int> ReportsByStatus,
    IReadOnlyList<ReportSummary> LatestReports,
    int FilesUnderReportsRoot,
    IReadOnlyList<string> SystemAuditTail);
record AppUser(string Username, string? DisplayName, string PasswordHash, List<string> Roles);
record ReportSummary(string Id, string Title, DateOnly WeekStart, DateOnly WeekEnd, ReportStatus Status, PublicationMode PublicationMode, DateTimeOffset UpdatedAt);
record ReportMeta(string Id, string Title, DateOnly WeekStart, DateOnly WeekEnd, ReportStatus Status, PublicationMode PublicationMode, string CreatedBy, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt, string DocxPath);
record ReportBundle(ReportMeta Meta, ReportContent Content, ApprovalRecord? Approval, List<string> ValidationIssues, List<AuditRecord> Audit);
record PublicReport(PublicReportMeta Meta, ReportContent Content);
record PublicReportMeta(string Id, string Title, DateOnly WeekStart, DateOnly WeekEnd, ReportStatus Status, PublicationMode PublicationMode, DateTimeOffset UpdatedAt);
record ApprovalRecord(PublicationMode PublicationMode, string? ApprovedBy, DateTimeOffset PublishedAt, bool RequiresPostReview);
record AuditRecord(DateTimeOffset At, string Actor, string Action, string Details);
record ReportContent
{
    public string ReportingWeek { get; init; } = "";
    public string PreparedBy { get; init; } = "Innovation & Policy";
    public string ExecutiveSnapshot { get; init; } = "";
    public List<TrendItem> PriorityTrends { get; init; } = [];
    public List<SectionItem> Horizon { get; init; } = [];
    public List<ImplicationItem> Implications { get; init; } = [];
    public List<string> AttentionSignals { get; init; } = [];
    public List<string> Assumptions { get; init; } = [];
    public List<ReferenceItem> References { get; init; } = [];
}
record TrendItem(string Title, string WhatHappened, string WhyItMatters, string Signal, string RiskOpportunity);
record SectionItem(string Title, string Body);
record ImplicationItem
{
    public string Title { get; init; } = "";
    public string Body { get; init; } = "";
    public string SourceSection { get; init; } = "";
    public int SourceItemIndex { get; init; }
}
record ReferenceItem(string Title, string Url, string? Publisher = null, string? PublishedAt = null);

enum ReportStatus { Draft, PendingReview, Published, Rejected }
enum PublicationMode { Uploaded, AgentGenerated, AgentGeneratedNeedsReview, HumanApproved, AutoPublished }
