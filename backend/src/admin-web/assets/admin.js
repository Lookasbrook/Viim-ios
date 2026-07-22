const state = {
  activeView: "overview",
  overview: null,
  users: [],
  trips: [],
  alerts: [],
  incidents: [],
  system: null,
  loaded: new Set()
};

const viewMeta = {
  overview: ["Cockpit opérationnel", "Vue d’ensemble"],
  users: ["Répertoire serveur", "Utilisateurs"],
  trips: ["Données routières", "Trajets"],
  safety: ["Assistance et alertes", "Sécurité"],
  system: ["État des dépendances", "Système"]
};

const numberFormat = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 1 });
const integerFormat = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 0 });
const coordinateFormat = new Intl.NumberFormat("fr-FR", { minimumFractionDigits: 3, maximumFractionDigits: 3 });
const dateTimeFormat = new Intl.DateTimeFormat("fr-FR", {
  timeZone: "Africa/Ouagadougou",
  day: "numeric",
  month: "short",
  hour: "2-digit",
  minute: "2-digit"
});
const dayFormat = new Intl.DateTimeFormat("fr-FR", {
  timeZone: "Africa/Ouagadougou",
  weekday: "narrow",
  day: "numeric"
});
const relativeFormat = new Intl.RelativeTimeFormat("fr", { numeric: "auto" });

document.addEventListener("DOMContentLoaded", () => {
  bindNavigation();
  bindActions();
  loadOverview();
});

function bindNavigation() {
  document.querySelectorAll("[data-view]").forEach((button) => {
    button.addEventListener("click", () => showView(button.dataset.view));
  });
  document.querySelectorAll("[data-go-view]").forEach((button) => {
    button.addEventListener("click", () => showView(button.dataset.goView));
  });
}

function bindActions() {
  document.querySelector("#refresh-button")?.addEventListener("click", refreshCurrentView);
  document.querySelector("#logout-button")?.addEventListener("click", logout);
  document.querySelector("#user-search")?.addEventListener("input", debounce(loadUsers, 280));
  document.querySelectorAll("[data-export]").forEach((button) => {
    button.addEventListener("click", () => exportData(button.dataset.export));
  });
}

async function showView(view) {
  if (!viewMeta[view]) return;
  state.activeView = view;
  document.querySelectorAll("[data-view]").forEach((item) => {
    item.classList.toggle("is-active", item.dataset.view === view);
  });
  document.querySelectorAll(".view").forEach((section) => section.classList.remove("is-active"));
  document.querySelector(`#view-${view}`)?.classList.add("is-active");
  document.querySelector("#view-kicker").textContent = viewMeta[view][0];
  document.querySelector("#view-title").textContent = viewMeta[view][1];
  window.scrollTo({ top: 0, behavior: "smooth" });

  if (view === "users" && !state.loaded.has("users")) await loadUsers();
  if (view === "trips" && !state.loaded.has("trips")) await loadTrips();
  if (view === "safety" && !state.loaded.has("safety")) await loadSafety();
  if (view === "system" && !state.loaded.has("system")) await loadSystem();
}

async function refreshCurrentView() {
  const button = document.querySelector("#refresh-button");
  button.classList.add("is-spinning");
  try {
    const loaders = {
      overview: loadOverview,
      users: loadUsers,
      trips: loadTrips,
      safety: loadSafety,
      system: loadSystem
    };
    await loaders[state.activeView]?.();
  } finally {
    button.classList.remove("is-spinning");
  }
}

async function loadOverview() {
  setRefreshStatus("Actualisation en cours…");
  try {
    state.overview = await api("/admin/api/overview");
    state.loaded.add("overview");
    renderOverview(state.overview);
    hideGlobalError();
    setRefreshStatus(`Actualisé ${relativeTime(state.overview.generatedAt)}`);
  } catch (error) {
    showGlobalError(error.message);
    setRefreshStatus("Données indisponibles");
  }
}

async function loadUsers() {
  const search = document.querySelector("#user-search")?.value?.trim() ?? "";
  setTableLoading("#users-table-body", 7);
  try {
    const result = await api(`/admin/api/users?limit=100&search=${encodeURIComponent(search)}`);
    state.users = result.items;
    state.loaded.add("users");
    document.querySelector("#users-total").textContent = plural(result.total, "utilisateur", "utilisateurs");
    renderUsers(result.items);
    hideGlobalError();
  } catch (error) {
    showGlobalError(error.message);
    renderEmpty("#users-table-body", 7, "Les utilisateurs sont momentanément indisponibles.");
  }
}

async function loadTrips() {
  setTableLoading("#trips-table-body", 7);
  try {
    const result = await api("/admin/api/trips?limit=100");
    state.trips = result.items;
    state.loaded.add("trips");
    document.querySelector("#trips-total").textContent = plural(result.total, "trajet", "trajets");
    renderTrips(result.items);
    hideGlobalError();
  } catch (error) {
    showGlobalError(error.message);
    renderEmpty("#trips-table-body", 7, "Les trajets sont momentanément indisponibles.");
  }
}

async function loadSafety() {
  setTableLoading("#alerts-table-body", 4);
  setTableLoading("#incidents-table-body", 5);
  try {
    const [alerts, incidents] = await Promise.all([
      api("/admin/api/alerts?limit=100"),
      api("/admin/api/incidents?limit=100")
    ]);
    state.alerts = alerts.items;
    state.incidents = incidents.items;
    state.loaded.add("safety");
    document.querySelector("#alerts-total").textContent = plural(alerts.total, "alerte", "alertes");
    document.querySelector("#incidents-total").textContent = plural(incidents.total, "incident", "incidents");
    renderAlerts(alerts.items);
    renderIncidents(incidents.items);
    hideGlobalError();
  } catch (error) {
    showGlobalError(error.message);
    renderEmpty("#alerts-table-body", 4, "Les alertes sont indisponibles.");
    renderEmpty("#incidents-table-body", 5, "Les incidents sont indisponibles.");
  }
}

async function loadSystem() {
  const grid = document.querySelector("#system-grid");
  grid.innerHTML = systemSkeleton();
  try {
    state.system = await api("/admin/api/system");
    state.loaded.add("system");
    renderSystem(state.system);
    hideGlobalError();
  } catch (error) {
    showGlobalError(error.message);
    grid.innerHTML = `<p>Impossible de lire l’état des services.</p>`;
  }
}

function renderOverview(data) {
  const { metrics, interventions, coverage } = data;
  const connected = data.dataSourceStatus === "connected";
  document.querySelector("#server-dot").classList.toggle("is-offline", !connected);
  document.querySelector("#server-status").textContent = connected ? "PostgreSQL connecté" : "Base non configurée";

  const people = metrics.activeDrivers30d || metrics.circleUsers;
  const headline = people === 0 && metrics.alerts7d === 0
    ? "Aucune activité serveur à signaler pour le moment."
    : `${integerFormat.format(people)} ${people > 1 ? "personnes actives" : "personne active"}, ${integerFormat.format(metrics.trips30d)} trajets et ${integerFormat.format(metrics.incidents30d)} incidents.`;
  document.querySelector("#command-headline").textContent = headline;
  document.querySelector("#command-note").textContent = metrics.latestServerActivity
    ? `Dernière activité serveur ${relativeTime(metrics.latestServerActivity)} · Heure de Ouagadougou`
    : "Les trajets locaux restent invisibles tant que leur synchronisation n’est pas activée.";

  setText("#metric-users", integerFormat.format(metrics.circleUsers));
  setText("#metric-users-note", plural(metrics.syncedProfiles, "profil trajets synchronisé", "profils trajets synchronisés"));
  setText("#metric-trips", integerFormat.format(metrics.trips30d));
  setText("#metric-distance", `${numberFormat.format(metrics.distance30d)} km`);
  setText("#metric-alerts", metrics.alertSuccessRate7d === null ? "—" : `${numberFormat.format(metrics.alertSuccessRate7d)} %`);

  renderChart(data.series);
  renderInterventions(interventions);
  renderActivity(data.activity);
  renderCoverage(coverage);

  const interventionCount = interventions.failedAlerts24h + interventions.stalledAlerts + interventions.confirmedIncidents7d;
  const navCount = document.querySelector("#nav-intervention-count");
  navCount.textContent = integerFormat.format(interventionCount);
  navCount.hidden = interventionCount === 0;
}

function renderChart(series) {
  const chart = document.querySelector("#activity-chart");
  const normalized = series.length ? series : emptySeries(14);
  const maximum = Math.max(1, ...normalized.flatMap((day) => [day.trips, day.alerts + day.incidents, day.registrations]));
  chart.innerHTML = normalized.map((day) => {
    const safety = day.alerts + day.incidents;
    const title = `${formatShortDate(day.date)} : ${day.trips} trajets, ${safety} événements sécurité, ${day.registrations} inscriptions`;
    return `<div class="chart-day" title="${escapeHTML(title)}">
      <i class="chart-bar chart-bar--trip h-${barLevel(day.trips, maximum)}"></i>
      <i class="chart-bar chart-bar--safety h-${barLevel(safety, maximum)}"></i>
      <i class="chart-bar chart-bar--user h-${barLevel(day.registrations, maximum)}"></i>
      <span class="chart-label">${escapeHTML(dayFormat.format(new Date(day.date)))}</span>
    </div>`;
  }).join("");
}

function renderInterventions(data) {
  const items = [
    ["Alertes en échec", "Ces dernières 24 h", data.failedAlerts24h, data.failedAlerts24h > 0 ? "is-danger" : ""],
    ["Alertes bloquées", "En attente depuis plus de 5 min", data.stalledAlerts, data.stalledAlerts > 0 ? "is-warning" : ""],
    ["Collisions confirmées", "Ces 7 derniers jours", data.confirmedIncidents7d, data.confirmedIncidents7d > 0 ? "is-danger" : ""],
    ["Notifications non lues", "Dans les cercles proches", data.unreadNotifications, data.unreadNotifications > 0 ? "is-warning" : ""]
  ];
  const total = data.failedAlerts24h + data.stalledAlerts + data.confirmedIncidents7d;
  setText("#intervention-total", integerFormat.format(total));
  document.querySelector("#intervention-list").innerHTML = items.map(([label, detail, value, tone]) => `
    <div class="intervention-item ${tone}"><i aria-hidden="true"></i><span><strong>${escapeHTML(label)}</strong><small>${escapeHTML(detail)}</small></span><b>${integerFormat.format(value)}</b></div>
  `).join("");
}

function renderActivity(items) {
  const feed = document.querySelector("#activity-feed");
  if (!items.length) {
    feed.innerHTML = `<li class="activity-item"><span class="activity-icon">·</span><div><strong>Le fil est calme</strong><p>Les nouvelles opérations apparaîtront ici.</p></div></li>`;
    return;
  }
  feed.innerHTML = items.slice(0, 10).map((item) => {
    const content = activityContent(item);
    return `<li class="activity-item" data-kind="${escapeHTML(item.kind)}">
      <span class="activity-icon" aria-hidden="true">${content.icon}</span>
      <div><strong>${escapeHTML(content.title)}</strong><p>${escapeHTML(content.detail)}</p><time datetime="${escapeHTML(item.occurredAt)}">${escapeHTML(relativeTime(item.occurredAt))}</time></div>
    </li>`;
  }).join("");
}

function renderCoverage(coverage) {
  const rows = [
    ["Cercle de confiance", "Comptes, liens et statistiques partagées", coverage.circle],
    ["Alertes et incidents", "Preuves d’envoi et événements connectés", coverage.alerts],
    ["Profils et trajets", "Uniquement après synchronisation explicite", coverage.trips],
    ["Données médicales", "Jamais conservées sur le serveur", coverage.medical]
  ];
  document.querySelector("#coverage-list").innerHTML = rows.map(([label, detail, status]) => {
    const display = coverageStatus(status);
    return `<div class="coverage-row"><span><strong>${escapeHTML(label)}</strong><small>${escapeHTML(detail)}</small></span><em class="status-pill ${display.className}">${escapeHTML(display.label)}</em></div>`;
  }).join("");
}

function renderUsers(items) {
  if (!items.length) return renderEmpty("#users-table-body", 7, "Aucun utilisateur serveur ne correspond à cette recherche.");
  document.querySelector("#users-table-body").innerHTML = items.map((user) => `
    <tr>
      <td><span class="data-main">${escapeHTML(user.name)}</span><span class="data-sub">${escapeHTML(user.vehicle ?? "Véhicule non transmis")}</span></td>
      <td>${pill(user.source === "circle" ? "Cercle" : "Profil trajets", user.source === "circle" ? "" : "is-neutral")}</td>
      <td><span class="data-main">${escapeHTML(relativeTime(user.lastActivity))}</span><span class="data-sub">Inscrit ${escapeHTML(formatDate(user.createdAt))}</span></td>
      <td class="data-number">${integerFormat.format(user.tripsCount)}</td>
      <td class="data-number">${numberFormat.format(user.distanceKm)} km</td>
      <td class="data-number">${user.averageScore ?? "—"}</td>
      <td><span class="data-main">${escapeHTML(user.phone ?? "Non exposé")}</span><span class="data-sub">${user.pushReady ? "Notifications actives" : "Pas de jeton push"}</span></td>
    </tr>`).join("");
}

function renderTrips(items) {
  if (!items.length) return renderEmpty("#trips-table-body", 7, "Aucun trajet n’a été reçu par le serveur. Les trajets restent actuellement sur l’iPhone.");
  document.querySelector("#trips-table-body").innerHTML = items.map((trip) => `
    <tr>
      <td><span class="data-main">${escapeHTML(trip.userName)}</span><span class="data-sub">${escapeHTML(vehicleLabel(trip.vehicleType))}</span></td>
      <td><span class="data-main">${escapeHTML(formatDate(trip.startDate))}</span><span class="data-sub">Reçu ${escapeHTML(relativeTime(trip.receivedAt))}</span></td>
      <td class="data-number">${escapeHTML(formatDuration(trip.durationSec))}</td>
      <td class="data-number">${numberFormat.format(trip.distanceKm)} km</td>
      <td class="data-number">${numberFormat.format(trip.averageSpeedKmh)} km/h</td>
      <td class="data-number">${trip.score ?? "—"}</td>
      <td>${trip.calibration ? pill("Calibration", "is-warning") : pill("Analysé", "")}</td>
    </tr>`).join("");
}

function renderAlerts(items) {
  if (!items.length) return renderEmpty("#alerts-table-body", 4, "Aucune alerte enregistrée.");
  document.querySelector("#alerts-table-body").innerHTML = items.map((alert) => `
    <tr><td><span class="data-main">${escapeHTML(alertKindLabel(alert.kind))}</span><span class="data-sub">${escapeHTML(shortId(alert.id))}</span></td><td>${escapeHTML(alert.recipient ?? "Masqué")}</td><td>${escapeHTML(formatDate(alert.createdAt))}</td><td>${statusPill(alert.status)}</td></tr>
  `).join("");
}

function renderIncidents(items) {
  if (!items.length) return renderEmpty("#incidents-table-body", 5, "Aucun incident enregistré dans les cercles.");
  document.querySelector("#incidents-table-body").innerHTML = items.map((incident) => `
    <tr><td><span class="data-main">${escapeHTML(incident.sourceName)}</span><span class="data-sub">${escapeHTML(shortId(incident.id))}</span></td><td>${escapeHTML(formatDate(incident.occurredAt))}</td><td class="data-number">${coordinateLabel(incident)}</td><td>${incident.readCount}/${incident.recipientsCount}</td><td>${severityPill(incident.severity)}</td></tr>
  `).join("");
}

function renderSystem(data) {
  const services = [
    ["API Viim", "◇", data.api?.status, data.api?.version ? `Version ${data.api.version}` : "Service applicatif"],
    ["PostgreSQL", "▦", data.database?.status, "Stockage des opérations serveur"],
    ["WhatsApp", "↗", data.whatsapp?.status, data.whatsapp?.code ? `Réponse fournisseur ${data.whatsapp.code}` : "Canal NEwAGENT-IA"],
    ["Accès admin", "◆", data.admin?.status, "Session signée et lecture seule"]
  ];
  document.querySelector("#system-grid").innerHTML = services.map(([name, symbol, status, detail]) => {
    const normalized = systemStatus(status);
    return `<article class="system-card"><div class="system-card-head"><span class="system-symbol" aria-hidden="true">${symbol}</span>${pill(normalized.label, normalized.className)}</div><h3>${escapeHTML(name)}</h3><p>${escapeHTML(detail)}</p></article>`;
  }).join("");
}

function activityContent(item) {
  const name = item.actor || "Viim";
  if (item.kind === "trip") return {
    icon: "↗",
    title: `${name} · nouveau trajet`,
    detail: `${numberFormat.format(Number(item.metadata.distanceKm ?? 0))} km · score ${item.metadata.score ?? "non calculé"}`
  };
  if (item.kind === "alert") return {
    icon: "!",
    title: `${alertKindLabel(item.metadata.alertKind)} · ${statusLabel(item.metadata.status)}`,
    detail: `Destinataire ${item.metadata.recipient ?? "masqué"}`
  };
  if (item.kind === "incident") return {
    icon: "△",
    title: `${name} · incident ${severityLabel(item.metadata.severity)}`,
    detail: "Signal enregistré dans le cercle de confiance"
  };
  return {
    icon: "+",
    title: `${name} a rejoint Viim`,
    detail: item.metadata.source === "circle" ? "Compte du cercle créé" : "Profil trajets créé"
  };
}

function coverageStatus(status) {
  if (status === "active") return { label: "Actif", className: "" };
  if (status === "never_stored") return { label: "Hors serveur", className: "is-neutral" };
  return { label: "En attente", className: "is-warning" };
}

function systemStatus(status) {
  if (status === "ok") return { label: "Opérationnel", className: "" };
  if (status === "not_configured") return { label: "Non configuré", className: "is-warning" };
  return { label: "Dégradé", className: "is-danger" };
}

function statusPill(status) {
  const tones = { failed: "is-danger", queued: "is-warning", sent: "", delivered: "" };
  return pill(statusLabel(status), tones[status] ?? "is-neutral");
}

function severityPill(severity) {
  const tones = { confirmed: "is-danger", suspected: "is-warning", test: "is-neutral" };
  return pill(severityLabel(severity), tones[severity] ?? "is-neutral");
}

function pill(label, className = "") {
  return `<span class="status-pill ${className}">${escapeHTML(label)}</span>`;
}

function statusLabel(status) {
  return ({ queued: "En attente", sent: "Envoyée", delivered: "Livrée", failed: "Échec" })[status] ?? status ?? "Inconnu";
}

function severityLabel(severity) {
  return ({ confirmed: "confirmé", suspected: "suspecté", test: "test" })[severity] ?? severity ?? "inconnu";
}

function alertKindLabel(kind) {
  return ({ alert_test: "Test WhatsApp", location_share: "Partage de position", collision: "Alerte collision" })[kind] ?? "Alerte";
}

function vehicleLabel(type) {
  return ({ moto: "Moto", voiture: "Voiture", velo: "Vélo" })[type] ?? type ?? "Véhicule";
}

function coordinateLabel(incident) {
  if (incident.latitude === null || incident.longitude === null) return "—";
  return `${coordinateFormat.format(incident.latitude)}, ${coordinateFormat.format(incident.longitude)}`;
}

function setTableLoading(selector, columns) {
  const body = document.querySelector(selector);
  body.innerHTML = `<tr class="empty-row"><td colspan="${columns}">Lecture des données…</td></tr>`;
}

function renderEmpty(selector, columns, message) {
  document.querySelector(selector).innerHTML = `<tr class="empty-row"><td colspan="${columns}">${escapeHTML(message)}</td></tr>`;
}

function systemSkeleton() {
  return Array.from({ length: 4 }, () => `<article class="system-card"><span class="data-sub">Vérification…</span></article>`).join("");
}

async function api(path) {
  const response = await fetch(path, { headers: { Accept: "application/json" } });
  if (response.status === 401) {
    window.location.replace("/admin/login");
    throw new Error("Votre session a expiré.");
  }
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    if (body.error === "admin_not_configured") throw new Error("L’accès admin n’est pas configuré sur le serveur.");
    throw new Error("Le serveur ne peut pas fournir ces données pour le moment.");
  }
  return response.json();
}

async function logout() {
  await fetch("/admin/api/logout", { method: "POST" }).catch(() => {});
  window.location.replace("/admin/login");
}

function exportData(kind) {
  const exports = {
    users: {
      rows: state.users,
      columns: ["name", "source", "phone", "vehicle", "tripsCount", "distanceKm", "averageScore", "createdAt", "lastActivity"]
    },
    trips: {
      rows: state.trips,
      columns: ["userName", "startDate", "endDate", "distanceKm", "durationSec", "averageSpeedKmh", "maxSpeedKmh", "score", "vehicleType", "role", "receivedAt"]
    }
  };
  const selected = exports[kind];
  if (!selected?.rows.length) return;
  const lines = [selected.columns.join(",")];
  for (const row of selected.rows) {
    lines.push(selected.columns.map((column) => csvCell(row[column])).join(","));
  }
  const blob = new Blob([`\ufeff${lines.join("\n")}`], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `viim-${kind}-${new Date().toISOString().slice(0, 10)}.csv`;
  link.click();
  URL.revokeObjectURL(url);
}

function csvCell(value) {
  const text = value === null || value === undefined ? "" : String(value);
  return `"${text.replaceAll('"', '""')}"`;
}

function barLevel(value, maximum) {
  if (!value) return 0;
  return Math.max(1, Math.min(10, Math.ceil((value / maximum) * 10)));
}

function emptySeries(days) {
  return Array.from({ length: days }, (_, index) => {
    const date = new Date();
    date.setDate(date.getDate() - (days - 1 - index));
    return { date: date.toISOString(), trips: 0, alerts: 0, incidents: 0, registrations: 0 };
  });
}

function formatDate(value) {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? dateTimeFormat.format(date).replace(":", " h ") : "—";
}

function formatShortDate(value) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("fr-FR", { day: "numeric", month: "short", timeZone: "Africa/Ouagadougou" }).format(new Date(value));
}

function relativeTime(value) {
  if (!value) return "jamais";
  const seconds = Math.round((new Date(value).getTime() - Date.now()) / 1_000);
  if (!Number.isFinite(seconds)) return "date inconnue";
  const absolute = Math.abs(seconds);
  if (absolute < 60) return relativeFormat.format(seconds, "second");
  if (absolute < 3_600) return relativeFormat.format(Math.round(seconds / 60), "minute");
  if (absolute < 86_400) return relativeFormat.format(Math.round(seconds / 3_600), "hour");
  return relativeFormat.format(Math.round(seconds / 86_400), "day");
}

function formatDuration(seconds) {
  const hours = Math.floor(Number(seconds) / 3_600);
  const minutes = Math.max(0, Math.round((Number(seconds) % 3_600) / 60));
  return hours ? `${hours} h ${String(minutes).padStart(2, "0")}` : `${minutes} min`;
}

function shortId(value) { return value ? `${String(value).slice(0, 8)}…` : "—"; }
function plural(value, singular, pluralValue) { return `${integerFormat.format(value)} ${value > 1 ? pluralValue : singular}`; }
function setText(selector, value) { const element = document.querySelector(selector); if (element) element.textContent = value; }

function setRefreshStatus(value) { setText("#refresh-status", value); }
function showGlobalError(message) { const box = document.querySelector("#global-error"); box.textContent = message; box.hidden = false; }
function hideGlobalError() { document.querySelector("#global-error").hidden = true; }

function escapeHTML(value) {
  return String(value ?? "").replace(/[&<>'"]/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;"
  })[character]);
}

function debounce(operation, delay) {
  let timeout;
  return (...argumentsList) => {
    clearTimeout(timeout);
    timeout = setTimeout(() => operation(...argumentsList), delay);
  };
}
