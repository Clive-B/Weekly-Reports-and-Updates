let session = null;
let reports = [];
let selected = null;

const $ = id => document.getElementById(id);

async function api(path, options = {}) {
  const response = await fetch(path, {
    credentials: "same-origin",
    headers: options.body instanceof FormData ? {} : { "Content-Type": "application/json" },
    ...options
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(text || response.statusText);
  }

  const contentType = response.headers.get("content-type") || "";
  return contentType.includes("application/json") ? response.json() : response.text();
}

function hasRole(role) {
  return session?.roles?.includes(role);
}

function showAuthenticated(authenticated) {
  $("appPanel").classList.remove("hidden");
  $("editorPanel").classList.toggle("hidden", !authenticated);
  $("reportPicker").classList.toggle("hidden", !authenticated);
  $("editorSignInBtn").classList.toggle("hidden", authenticated);
  $("logoutBtn").classList.toggle("hidden", !authenticated);
  if (authenticated) $("loginPanel").classList.add("hidden");
}

async function loadSession() {
  session = await api("/api/session");
  showAuthenticated(session.authenticated);
  $("sessionText").textContent = session.authenticated
    ? `${session.user} (${session.roles.join(", ")})`
    : "Public view";

  await loadReports();
}

function openLogin() {
  $("loginError").textContent = "";
  $("loginPanel").classList.remove("hidden");
  $("username").focus();
}

function closeLogin() {
  $("loginPanel").classList.add("hidden");
  $("loginError").textContent = "";
  $("password").value = "";
}

async function login() {
  $("loginError").textContent = "";
  try {
    await api("/api/login", {
      method: "POST",
      body: JSON.stringify({ username: $("username").value, password: $("password").value })
    });
    $("password").value = "";
    await loadSession();
  } catch {
    $("loginError").textContent = "Sign in failed. Check the username and password.";
  }
}

async function logout() {
  await api("/api/logout", { method: "POST", body: "{}" });
  selected = null;
  await loadSession();
}

async function loadReports() {
  if (session?.authenticated) {
    reports = await api("/api/reports");
    renderReportList();
    if (!selected && reports.length) await selectReport(reports[0].id);
    return;
  }

  reports = [];
  try {
    selected = await api("/api/reports/current");
    renderSelected();
  } catch {
    selected = null;
    renderNoPublishedReport();
  }
}

function renderNoPublishedReport() {
  $("reportTitle").textContent = "No published report available";
  $("reportMeta").textContent = "An editor must publish a report before it appears in the public view.";
  $("previewWeek").textContent = "Awaiting publication";
  $("previewPreparedBy").textContent = "Innovation Unit";
  $("previewStatus").textContent = "Not published";
  $("previewMode").textContent = "Public read-only";
  $("snapshotText").textContent = "The latest approved weekly report will appear here once published.";
  renderTrends([]);
  renderMiniCards("horizonContainer", []);
  renderMiniCards("implicationsContainer", []);
  renderListCards("attentionContainer", []);
  renderListCards("notesContainer", []);
  renderReferences([]);
}

function renderReportList() {
  const list = $("reportList");
  list.innerHTML = "";
  if (!reports.length) {
    list.innerHTML = `<p class="muted">No repo-stored reports yet.</p>`;
    return;
  }

  reports.forEach(report => {
    const button = document.createElement("button");
    button.className = `report-item ${selected?.meta?.id === report.id ? "active" : ""}`;
    button.innerHTML = `<strong>${escapeHtml(report.title)}</strong><span>${report.weekStart} to ${report.weekEnd} · ${report.status} · ${report.publicationMode}</span>`;
    button.addEventListener("click", () => selectReport(report.id));
    list.appendChild(button);
  });
}

async function selectReport(id) {
  selected = await api(`/api/reports/${id}`);
  renderReportList();
  renderSelected();
}

function renderSelected() {
  if (!selected) return;
  const { meta, content, approval, validationIssues, audit } = selected;
  $("reportTitle").textContent = meta.title;
  $("reportMeta").textContent = `${meta.weekStart} to ${meta.weekEnd} · ${meta.status} · ${meta.publicationMode}${meta.docxPath ? ` · ${meta.docxPath}` : ""}`;

  $("submitReviewBtn").classList.toggle("hidden", !(hasRole("Editor") || hasRole("Admin")) || meta.status !== "Draft");
  $("approveBtn").classList.toggle("hidden", !(hasRole("Reviewer") || hasRole("Admin")) || meta.status !== "PendingReview");
  $("rejectBtn").classList.toggle("hidden", !(hasRole("Reviewer") || hasRole("Admin")) || meta.status !== "PendingReview");

  $("contentWeek").value = content.reportingWeek || `${meta.weekStart} to ${meta.weekEnd}`;
  $("preparedBy").value = content.preparedBy || "Innovation Unit";
  $("snapshot").value = content.executiveSnapshot || "";
  $("trendsJson").value = JSON.stringify(content.priorityTrends || [], null, 2);
  $("horizonJson").value = JSON.stringify(content.horizon || [], null, 2);
  $("implicationsJson").value = JSON.stringify(content.implications || [], null, 2);
  $("attentionJson").value = JSON.stringify(content.attentionSignals || [], null, 2);
  $("assumptionsJson").value = JSON.stringify(content.assumptions || [], null, 2);
  $("referencesJson").value = JSON.stringify(content.references || [], null, 2);

  $("validationBox").classList.toggle("hidden", !validationIssues?.length);
  $("validationBox").innerHTML = validationIssues?.length
    ? `<strong>Validation issues:</strong><ul>${validationIssues.map(issue => `<li>${escapeHtml(issue)}</li>`).join("")}</ul>`
    : "";

  const approvalLine = approval ? `\nApproval: ${JSON.stringify(approval, null, 2)}\n` : "";
  $("auditLog").textContent = `${approvalLine}\n${(audit || []).map(a => `${a.at} | ${a.actor} | ${a.action} | ${a.details}`).join("\n")}`;
  renderPreview(meta, content);
}

function renderPreview(meta, content) {
  $("previewWeek").textContent = content.reportingWeek || `${meta.weekStart} to ${meta.weekEnd}`;
  $("previewPreparedBy").textContent = content.preparedBy || "Innovation Unit";
  $("previewStatus").textContent = meta.status || "";
  $("previewMode").textContent = meta.publicationMode || "";
  $("snapshotText").textContent = content.executiveSnapshot || "Select a report or add content to preview the executive snapshot.";

  renderTrends(content.priorityTrends || []);
  renderMiniCards("horizonContainer", content.horizon || []);
  renderMiniCards("implicationsContainer", content.implications || []);
  renderListCards("attentionContainer", content.attentionSignals || []);
  renderListCards("notesContainer", content.assumptions || []);
  renderReferences(content.references || []);
}

function renderTrends(trends) {
  const container = $("trendsContainer");
  container.innerHTML = "";
  $("trendPill").textContent = trends.length ? `Top ${trends.length} This Week` : "Awaiting Update";

  if (!trends.length) {
    container.innerHTML = `<div class="mini-card"><p>No priority trends have been added yet.</p></div>`;
    return;
  }

  trends.forEach((trend, index) => {
    const card = document.createElement("article");
    card.className = "trend";
    card.innerHTML = `
      <div class="trend-head">
        <h3>${escapeHtml(trend.title || `Trend ${index + 1}`)}</h3>
        <span class="time-badge">Trend ${index + 1}</span>
      </div>
      <div class="trend-grid">
        <div class="field"><div class="label">What Happened</div><div class="text">${escapeHtml(trend.whatHappened || "")}</div></div>
        <div class="field"><div class="label">Why It Matters</div><div class="text">${escapeHtml(trend.whyItMatters || "")}</div></div>
        <div class="field"><div class="label">Regulatory / Strategic Signal</div><div class="text">${escapeHtml(trend.signal || "")}</div></div>
        <div class="field"><div class="label">Risk / Opportunity Assessment</div><div class="text">${escapeHtml(trend.riskOpportunity || "")}</div></div>
      </div>
    `;
    container.appendChild(card);
  });
}

function renderMiniCards(containerId, items) {
  const container = $(containerId);
  container.innerHTML = "";
  if (!items.length) {
    container.innerHTML = `<div class="mini-card"><p>No entries have been added yet.</p></div>`;
    return;
  }

  items.forEach(item => {
    const card = document.createElement("article");
    card.className = "mini-card";
    card.innerHTML = `<h4>${escapeHtml(item.title || "Untitled")}</h4><p>${escapeHtml(item.body || "")}</p>`;
    container.appendChild(card);
  });
}

function renderListCards(containerId, items) {
  const container = $(containerId);
  container.innerHTML = "";
  const card = document.createElement("article");
  card.className = "mini-card attention-card";

  if (!items.length) {
    card.innerHTML = `<p>No entries have been added yet.</p>`;
  } else {
    card.innerHTML = `<ul>${items.map(item => `<li>${escapeHtml(item)}</li>`).join("")}</ul>`;
  }

  container.appendChild(card);
}

function renderReferences(references) {
  const list = $("referencesList");
  list.innerHTML = "";
  if (!references.length) {
    list.innerHTML = `<li>No references have been added yet.</li>`;
    return;
  }

  references.forEach(reference => {
    const li = document.createElement("li");
    const title = reference.title || reference.url || "Reference";
    const suffix = reference.url ? ` - ${reference.url}` : "";
    li.textContent = `${title}${suffix}`;
    list.appendChild(li);
  });
}

async function uploadWord() {
  const file = $("wordFile").files[0];
  if (!file) return;
  const data = new FormData();
  data.append("weekStart", $("weekStart").value);
  data.append("weekEnd", $("weekEnd").value);
  data.append("title", $("uploadTitle").value || file.name);
  data.append("file", file);
  selected = await api("/api/reports/upload", { method: "POST", body: data });
  await loadReports();
  renderSelected();
}

function readJsonField(id) {
  const text = $(id).value.trim();
  return text ? JSON.parse(text) : [];
}

async function saveContent() {
  $("contentError").textContent = "";
  if (!selected) return;
  try {
    const content = {
      reportingWeek: $("contentWeek").value,
      preparedBy: $("preparedBy").value,
      executiveSnapshot: $("snapshot").value,
      priorityTrends: readJsonField("trendsJson"),
      horizon: readJsonField("horizonJson"),
      implications: readJsonField("implicationsJson"),
      attentionSignals: readJsonField("attentionJson"),
      assumptions: readJsonField("assumptionsJson"),
      references: readJsonField("referencesJson")
    };
    selected = await api(`/api/reports/${selected.meta.id}/content`, { method: "PUT", body: JSON.stringify(content) });
    await loadReports();
    renderSelected();
  } catch (error) {
    $("contentError").textContent = error.message;
  }
}

async function action(path) {
  if (!selected) return;
  selected = await api(`/api/reports/${selected.meta.id}/${path}`, { method: "POST", body: "{}" });
  await loadReports();
  renderSelected();
}

async function reject() {
  if (!selected) return;
  const reason = prompt("Reason for rejection:");
  if (!reason) return;
  selected = await api(`/api/reports/${selected.meta.id}/reject`, {
    method: "POST",
    body: JSON.stringify({ reason })
  });
  await loadReports();
  renderSelected();
}

function switchTab(tab) {
  document.querySelectorAll(".tab").forEach(button => button.classList.toggle("active", button.dataset.tab === tab));
  ["upload", "content", "audit"].forEach(name => {
    $(`${name}Tab`).classList.toggle("hidden", name !== tab);
  });
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, char => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#039;"
  }[char]));
}

document.addEventListener("DOMContentLoaded", () => {
  $("editorSignInBtn").addEventListener("click", openLogin);
  $("closeLoginBtn").addEventListener("click", closeLogin);
  $("loginBtn").addEventListener("click", login);
  $("password").addEventListener("keydown", event => { if (event.key === "Enter") login(); });
  $("logoutBtn").addEventListener("click", logout);
  $("refreshBtn").addEventListener("click", loadReports);
  $("uploadBtn").addEventListener("click", uploadWord);
  $("saveContentBtn").addEventListener("click", saveContent);
  $("submitReviewBtn").addEventListener("click", () => action("submit-review"));
  $("approveBtn").addEventListener("click", () => action("approve"));
  $("rejectBtn").addEventListener("click", reject);
  document.querySelectorAll(".tab").forEach(button => button.addEventListener("click", () => switchTab(button.dataset.tab)));
  loadSession();
});
