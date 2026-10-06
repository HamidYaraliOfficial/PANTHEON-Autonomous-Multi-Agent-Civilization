/* PANTHEON — app.js
 * Orchestrates the whole dashboard: theme + language selectors, sidebar
 * navigation, the World Builder Wizard form, the REST calls behind every
 * view, and the WebSocket connection that drives the live event feed and
 * keeps the overview stats current without polling.
 */
const PantheonApp = (() => {
  const THEMES = [
    { id: "win11", labelKey: "settings.themeWindows" },
    { id: "light", labelKey: "settings.themeLight" },
    { id: "dark", labelKey: "settings.themeDark" },
    { id: "red", labelKey: "settings.themeRed" },
    { id: "blue", labelKey: "settings.themeBlue" },
  ];
  const THEME_STORAGE_KEY = "pantheon_theme";

  let ws = null;
  let wsReconnectTimer = null;

  // -------------------------------------------------------------- theme --

  function applyTheme(themeId) {
    document.documentElement.setAttribute("data-theme", themeId);
    localStorage.setItem(THEME_STORAGE_KEY, themeId);
    document.querySelectorAll('select[id^="theme-select"]').forEach((el) => (el.value = themeId));
  }

  function populateThemeSelectors() {
    document.querySelectorAll("#theme-select, #theme-select-settings").forEach((sel) => {
      sel.innerHTML = "";
      THEMES.forEach((t) => {
        const opt = document.createElement("option");
        opt.value = t.id;
        opt.textContent = PantheonI18n.t(t.labelKey) || t.id;
        sel.appendChild(opt);
      });
    });
    applyTheme(localStorage.getItem(THEME_STORAGE_KEY) || "win11");
  }

  function wireThemeSelectors() {
    document.querySelectorAll("#theme-select, #theme-select-settings").forEach((sel) => {
      sel.addEventListener("change", (e) => applyTheme(e.target.value));
    });
  }

  // ------------------------------------------------------------ nav/views --

  function wireNav() {
    document.querySelectorAll(".nav-item").forEach((btn) => {
      btn.addEventListener("click", () => switchView(btn.dataset.view));
    });
  }

  function switchView(viewId) {
    document.querySelectorAll(".nav-item").forEach((b) => b.classList.toggle("active", b.dataset.view === viewId));
    document.querySelectorAll(".view").forEach((v) => v.classList.toggle("active", v.id === `view-${viewId}`));

    if (viewId === "regions") loadRegions();
    if (viewId === "civilizations") loadCivilizations();
    if (viewId === "economy") loadEconomy();
    if (viewId === "culture") loadCulture();
  }

  // ------------------------------------------------------------------ api --

  async function api(path, opts) {
    const res = await fetch(path, opts);
    if (!res.ok) throw new Error(`HTTP ${res.status} on ${path}`);
    return res.status === 204 ? null : res.json();
  }

  function setConnected(isOn) {
    const dot = document.getElementById("conn-dot");
    const label = document.getElementById("conn-label");
    if (dot) dot.classList.toggle("on", isOn);
    if (label) label.textContent = isOn ? PantheonI18n.t("common.connected") : PantheonI18n.t("common.disconnected");
  }

  // -------------------------------------------------------------- overview --

  async function refreshStatus() {
    try {
      const s = await api("/api/status");
      setText("stat-tick", s.tick);
      setText("stat-day", s.day);
      setText("stat-year", s.year);
      setText("stat-population", s.population);
      setText("stat-regions", s.region_count);
      setText("stat-civs", s.civilization_count);

      const pill = document.getElementById("clock-state");
      if (pill) {
        pill.textContent = s.running ? PantheonI18n.t("overview.running") : PantheonI18n.t("overview.paused");
        pill.className = "pill " + (s.running ? "on" : "off");
      }

      const range = document.getElementById("speed-range");
      if (range && document.activeElement !== range) range.value = s.speed;
      setText("speed-value", `${s.speed}×`);
    } catch (_e) {
      /* status endpoint not reachable — connection dot already reflects this via the socket */
    }
  }

  function setText(id, value) {
    const el = document.getElementById(id);
    if (el) el.textContent = value;
  }

  async function bootstrapWorld(evt) {
    evt.preventDefault();
    const f = evt.target;
    const payload = {
      name: f.name.value,
      seed: parseInt(f.seed.value, 10) || 0,
      num_regions: parseInt(f.num_regions.value, 10) || 1,
      num_civilizations: parseInt(f.num_civilizations.value, 10) || 1,
      agents_per_region: parseInt(f.agents_per_region.value, 10) || 1,
      resource_abundance: parseFloat(f.resource_abundance.value) || 1.0,
    };
    await api("/api/world/bootstrap", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    await refreshStatus();
  }

  function wireClockControls() {
    document.getElementById("bootstrap-form").addEventListener("submit", bootstrapWorld);

    document.getElementById("btn-start").addEventListener("click", async () => {
      await api("/api/world/start", { method: "POST" });
      refreshStatus();
    });

    document.getElementById("btn-pause").addEventListener("click", async () => {
      await api("/api/world/pause", { method: "POST" });
      refreshStatus();
    });

    document.getElementById("speed-range").addEventListener("change", async (e) => {
      const multiplier = parseInt(e.target.value, 10);
      setText("speed-value", `${multiplier}×`);
      await api("/api/world/speed", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ multiplier }),
      });
    });
  }

  // --------------------------------------------------------------- regions --

  async function loadRegions() {
    const container = document.getElementById("regions-list");
    container.innerHTML = `<div class="card">${PantheonI18n.t("common.loading")}</div>`;

    try {
      const regions = await api("/api/regions");
      container.innerHTML = "";

      if (regions.length === 0) {
        container.innerHTML = `<div class="card">${PantheonI18n.t("common.none")}</div>`;
        return;
      }

      for (const region of regions) {
        const market = await api(`/api/regions/${region.id}/market`).catch(() => null);
        container.appendChild(renderRegionCard(region, market));
      }
    } catch (_e) {
      container.innerHTML = "";
    }
  }

  function renderRegionCard(region, market) {
    const div = document.createElement("div");
    div.className = "card";

    const resourceTags = Object.entries(region.resources || {})
      .map(([k, v]) => `<span class="tag">${escapeHtml(k)}: ${Math.round(v)}</span>`)
      .join("");

    let marketBlock = "";
    if (market) {
      const rows = Object.entries(market.prices || {})
        .map(([res, price]) => {
          const stock = (market.stock || {})[res];
          const priceStr = typeof price === "number" ? price.toFixed(2) : price;
          const stockStr = typeof stock === "number" ? Math.round(stock) : stock;
          return `<div class="needs-bar-row"><span>${escapeHtml(res)}</span><span>${PantheonI18n.t("regions.stock")}: ${stockStr}</span><span>${priceStr}</span></div>`;
        })
        .join("");
      marketBlock = `<p>${PantheonI18n.t("regions.market")}</p><div class="needs-bars">${rows}</div>`;
    }

    div.innerHTML = `
      <div class="card-header"><h2>${escapeHtml(region.id)}</h2><span class="pill">${escapeHtml(region.biome)}</span></div>
      <dl class="kv">
        <dt>${PantheonI18n.t("regions.fertility")}</dt><dd>${region.fertility}</dd>
        <dt>${PantheonI18n.t("regions.waterAccess")}</dt><dd>${region.water_access}</dd>
        <dt>${PantheonI18n.t("regions.hazard")}</dt><dd>${escapeHtml(String(region.hazard_profile))}</dd>
      </dl>
      <p>${PantheonI18n.t("regions.resources")}</p>
      <div class="tag-list">${resourceTags}</div>
      ${marketBlock}
    `;
    return div;
  }

  // ---------------------------------------------------------- civilizations --

  async function loadCivilizations() {
    const container = document.getElementById("civs-list");
    container.innerHTML = `<div class="card">${PantheonI18n.t("common.loading")}</div>`;

    try {
      const civs = await api("/api/civilizations");
      container.innerHTML = "";

      if (civs.length === 0) {
        container.innerHTML = `<div class="card">${PantheonI18n.t("common.none")}</div>`;
        return;
      }

      for (const civ of civs) {
        const culture = await api(`/api/civilizations/${civ.id}/culture`).catch(() => null);
        container.appendChild(renderCivCard(civ, culture));
      }
    } catch (_e) {
      container.innerHTML = "";
    }
  }

  function renderCivCard(civ, culture) {
    const div = document.createElement("div");
    div.className = "card";

    const norms = ((culture && culture.norms) || []).map((n) => `<span class="tag">${escapeHtml(n.content)}</span>`).join("");
    const symbols = ((culture && culture.symbols) || []).map((s) => `<span class="tag">${escapeHtml(s.content)}</span>`).join("");

    div.innerHTML = `
      <div class="card-header"><h2>${escapeHtml(civ.name)}</h2><span class="pill">${escapeHtml(civ.id)}</span></div>
      <dl class="kv">
        <dt>${PantheonI18n.t("civilizations.homeRegions")}</dt><dd>${(civ.home_regions || []).join(", ")}</dd>
        <dt>${PantheonI18n.t("civilizations.founded")}</dt><dd>${civ.founded_tick}</dd>
      </dl>
      <p>${PantheonI18n.t("civilizations.norms")}</p>
      <div class="tag-list">${norms || "—"}</div>
      <p>${PantheonI18n.t("civilizations.symbols")}</p>
      <div class="tag-list">${symbols || "—"}</div>
    `;
    return div;
  }

  // --------------------------------------------------------------- economy --

  async function loadEconomy() {
    const container = document.getElementById("economy-list");
    container.innerHTML = `<div class="card">${PantheonI18n.t("common.loading")}</div>`;

    try {
      const regions = await api("/api/regions");
      container.innerHTML = "";

      for (const region of regions) {
        const market = await api(`/api/regions/${region.id}/market`).catch(() => null);
        if (market) container.appendChild(renderRegionCard(region, market));
      }
    } catch (_e) {
      container.innerHTML = "";
    }
  }

  // --------------------------------------------------------------- culture --

  async function loadCulture() {
    const container = document.getElementById("culture-list");
    container.innerHTML = `<div class="card">${PantheonI18n.t("common.loading")}</div>`;

    try {
      const civs = await api("/api/civilizations");
      container.innerHTML = "";

      for (const civ of civs) {
        const [culture, language] = await Promise.all([
          api(`/api/civilizations/${civ.id}/culture`).catch(() => null),
          api(`/api/civilizations/${civ.id}/language`).catch(() => null),
        ]);
        container.appendChild(renderCultureCard(civ, culture, language));
      }
    } catch (_e) {
      container.innerHTML = "";
    }
  }

  function renderCultureCard(civ, culture, language) {
    const div = document.createElement("div");
    div.className = "card";

    const stories = ((culture && culture.stories) || []).slice(0, 5).map((s) => `<li>${escapeHtml(s.content)}</li>`).join("");
    const lexiconEntries = language ? Object.entries(language.lexicon || {}) : [];
    const lexiconRows = lexiconEntries
      .slice(0, 12)
      .map(([concept, entry]) => `<span class="tag">${escapeHtml(concept)} → ${escapeHtml(entry.word)}</span>`)
      .join("");

    div.innerHTML = `
      <div class="card-header"><h2>${escapeHtml(civ.name)}</h2></div>
      <p>${PantheonI18n.t("civilizations.stories")}</p>
      <ul>${stories || `<li>—</li>`}</ul>
      <p>${PantheonI18n.t("civilizations.lexicon")}</p>
      <div class="tag-list">${lexiconRows || "—"}</div>
    `;
    return div;
  }

  // ---------------------------------------------------------------- agents --

  function wireAgentSearch() {
    document.getElementById("agent-search-btn").addEventListener("click", doAgentSearch);
    document.getElementById("agent-search").addEventListener("keydown", (e) => {
      if (e.key === "Enter") doAgentSearch();
    });
  }

  async function doAgentSearch() {
    const id = document.getElementById("agent-search").value.trim();
    const detail = document.getElementById("agent-detail");
    if (!id) return;

    detail.style.display = "block";
    detail.innerHTML = PantheonI18n.t("common.loading");

    try {
      const agent = await api(`/api/agents/${encodeURIComponent(id)}`);
      detail.innerHTML = renderAgentDetail(agent);
    } catch (_e) {
      detail.innerHTML = `<p>${PantheonI18n.t("agents.notFound")}</p>`;
    }
  }

  function renderAgentDetail(agent) {
    const needsRows = Object.entries(agent.needs || {})
      .map(([k, v]) => {
        const pct = Math.round((v || 0) * 100);
        return `<div class="needs-bar-row"><span>${escapeHtml(k)}</span><div class="needs-bar-track"><div class="needs-bar-fill" style="width:${pct}%"></div></div><span>${pct}%</span></div>`;
      })
      .join("");

    const personalityRows = Object.entries(agent.personality || {})
      .map(([k, v]) => {
        const pct = Math.round((v || 0) * 100);
        return `<div class="needs-bar-row"><span>${escapeHtml(k)}</span><div class="needs-bar-track"><div class="needs-bar-fill" style="width:${pct}%"></div></div><span>${pct}%</span></div>`;
      })
      .join("");

    const memoryItems = (agent.memory || [])
      .slice(0, 10)
      .map((m) => `<li>${escapeHtml(m.kind || "event")} — ${escapeHtml(JSON.stringify(m).slice(0, 140))}</li>`)
      .join("");

    const relTags = Object.entries(agent.relationships || {})
      .map(([who, val]) => `<span class="tag">${escapeHtml(who)}: ${Number(val).toFixed(2)}</span>`)
      .join("");

    return `
      <div class="card-header"><h2>${escapeHtml(agent.name || agent.id)}</h2><span class="pill">${escapeHtml(agent.activity)}</span></div>
      <dl class="kv">
        <dt>${PantheonI18n.t("common.id")}</dt><dd>${escapeHtml(String(agent.id))}</dd>
        <dt>${PantheonI18n.t("agents.archetype")}</dt><dd>${escapeHtml(String(agent.archetype))}</dd>
        <dt>${PantheonI18n.t("agents.wealth")}</dt><dd>${agent.wealth}</dd>
      </dl>
      <p>${PantheonI18n.t("agents.needs")}</p>
      <div class="needs-bars">${needsRows}</div>
      <p>${PantheonI18n.t("agents.personality")}</p>
      <div class="needs-bars">${personalityRows}</div>
      <p>${PantheonI18n.t("agents.relationships")}</p>
      <div class="tag-list">${relTags || "—"}</div>
      <p>${PantheonI18n.t("agents.memory")}</p>
      <ul>${memoryItems || "<li>—</li>"}</ul>
    `;
  }

  // ------------------------------------------------------------- websocket --

  function connectSocket() {
    const proto = location.protocol === "https:" ? "wss" : "ws";
    ws = new WebSocket(`${proto}://${location.host}/ws`);

    ws.onopen = () => setConnected(true);
    ws.onclose = () => {
      setConnected(false);
      scheduleReconnect();
    };
    ws.onerror = () => setConnected(false);

    ws.onmessage = (evt) => {
      let msg;
      try {
        msg = JSON.parse(evt.data);
      } catch (_e) {
        return;
      }

      if (msg.type === "event") {
        pushEventToFeed(msg.topic, msg.event);
        if (msg.topic === "world_tick") refreshStatus();
      }
    };
  }

  function scheduleReconnect() {
    clearTimeout(wsReconnectTimer);
    wsReconnectTimer = setTimeout(connectSocket, 3000);
  }

  function pushEventToFeed(topic, event) {
    const feed = document.getElementById("event-feed");
    if (!feed) return;
    const li = document.createElement("li");
    li.innerHTML = `<span class="event-topic">${escapeHtml(topic)}</span>${escapeHtml(JSON.stringify(event))}`;
    feed.appendChild(li);
    while (feed.children.length > 300) feed.removeChild(feed.firstChild);
  }

  // -------------------------------------------------------------- helpers --

  function escapeHtml(str) {
    return String(str).replace(/[&<>"']/g, (c) => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
    }[c]));
  }

  // ---------------------------------------------------------------- init --

  async function init() {
    await PantheonI18n.init();
    PantheonI18n.wireLanguageSelectors();
    populateThemeSelectors();
    wireThemeSelectors();
    wireNav();
    wireClockControls();
    wireAgentSearch();

    document.getElementById("regions-refresh").addEventListener("click", loadRegions);
    document.getElementById("civs-refresh").addEventListener("click", loadCivilizations);

    connectSocket();
    await refreshStatus();
    setInterval(refreshStatus, 5000);

    await PantheonOperatingHours.init();

    document.addEventListener("pantheon:i18n-changed", () => {
      populateThemeSelectors();
      refreshStatus();
    });
  }

  return { init };
})();

document.addEventListener("DOMContentLoaded", () => {
  PantheonApp.init();
});
