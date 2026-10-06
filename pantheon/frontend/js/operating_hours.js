/* PANTHEON — operating_hours.js
 * Lets the operator type in a weekly open-hours schedule (per day, one or
 * more start/end windows, plus a UTC offset) and shows a live "open now /
 * opens in Xh Ym" status pill computed from that schedule via the
 * PantheonCore.OperatingHours backend module. Nothing here is hard-coded:
 * every day/window shown comes from what the user has actually entered.
 */
const PantheonOperatingHours = (() => {
  const WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];
  let schedule = null;
  let statusData = null;
  let countdownTimer = null;
  let pollTimer = null;

  function buildWindowRow(win) {
    const tpl = document.getElementById("tpl-window").content.cloneNode(true);
    const el = tpl.querySelector(".oh-window");
    const labels = el.querySelectorAll("label");
    labels[0].textContent = PantheonI18n.t("settings.start") || "Start";
    labels[1].textContent = PantheonI18n.t("settings.end") || "End";
    el.querySelector(".oh-start").value = win.start || "09:00";
    el.querySelector(".oh-end").value = win.end || "17:00";
    const removeBtn = el.querySelector(".oh-remove");
    removeBtn.textContent = PantheonI18n.t("settings.removeWindow") || "Remove";
    removeBtn.addEventListener("click", () => el.remove());
    return el;
  }

  function renderDays() {
    const container = document.getElementById("oh-days");
    if (!container || !schedule) return;
    container.innerHTML = "";

    const tzInput = document.getElementById("oh-tz-offset");
    if (tzInput) tzInput.value = schedule.timezone_offset_minutes ?? 0;

    WEEKDAYS.forEach((day) => {
      const rowTpl = document.getElementById("tpl-day-row").content.cloneNode(true);
      const row = rowTpl.querySelector(".oh-day-row");
      row.dataset.day = day;
      row.querySelector(".oh-day-name").textContent = PantheonI18n.t(`settings.days.${day}`) || day;

      const windowsContainer = row.querySelector(".oh-windows");
      const windows = schedule[day] || [];
      windows.forEach((w) => windowsContainer.appendChild(buildWindowRow(w)));

      const addBtn = row.querySelector(".oh-add");
      addBtn.textContent = PantheonI18n.t("settings.addWindow") || "Add time window";
      addBtn.addEventListener("click", () => {
        windowsContainer.appendChild(buildWindowRow({ start: "09:00", end: "17:00" }));
      });

      container.appendChild(row);
    });
  }

  function collectSchedule() {
    const tzInput = document.getElementById("oh-tz-offset");
    const out = { timezone_offset_minutes: parseInt((tzInput && tzInput.value) || "0", 10) };

    document.querySelectorAll(".oh-day-row").forEach((row) => {
      const day = row.dataset.day;
      const windows = [];
      row.querySelectorAll(".oh-window").forEach((w) => {
        const start = w.querySelector(".oh-start").value;
        const end = w.querySelector(".oh-end").value;
        if (start && end) windows.push({ start, end });
      });
      out[day] = windows;
    });

    return out;
  }

  async function fetchSchedule() {
    const res = await fetch("/api/operating-hours");
    schedule = await res.json();
    renderDays();
  }

  async function save() {
    const payload = collectSchedule();
    const res = await fetch("/api/operating-hours", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    schedule = await res.json();
    await refreshStatus();
  }

  async function refreshStatus() {
    try {
      const res = await fetch("/api/operating-hours/status");
      statusData = await res.json();
      renderStatus();
    } catch (_e) {
      /* backend not reachable yet — the connection banner already covers this */
    }
  }

  function renderStatus() {
    const pill = document.getElementById("oh-status-pill");
    if (!pill || !statusData) return;

    if (statusData.open) {
      pill.textContent = PantheonI18n.t("settings.statusOpenNow") || "Open now";
      pill.className = "pill on";
    } else {
      pill.textContent = PantheonI18n.t("settings.statusClosedNow") || "Closed now";
      pill.className = "pill off";
    }

    updateCountdownText();
  }

  function fmtDuration(totalSeconds) {
    const d = Math.floor(totalSeconds / 86400);
    const h = Math.floor((totalSeconds % 86400) / 3600);
    const m = Math.floor((totalSeconds % 3600) / 60);
    const s = totalSeconds % 60;
    const parts = [];
    if (d > 0) parts.push(`${d}${PantheonI18n.t("time.d") || "d"}`);
    if (d > 0 || h > 0) parts.push(`${h}${PantheonI18n.t("time.h") || "h"}`);
    parts.push(`${m}${PantheonI18n.t("time.m") || "m"}`);
    if (d === 0 && h === 0) parts.push(`${s}${PantheonI18n.t("time.s") || "s"}`);
    return parts.join(" ");
  }

  function updateCountdownText() {
    const el = document.getElementById("oh-countdown");
    if (!el || !statusData) return;

    if (statusData.next_state === "none" || statusData.changes_at == null) {
      el.textContent = statusData.next_state === "none" ? PantheonI18n.t("settings.neverOpens") || "" : "";
      return;
    }

    const changesAt = new Date(statusData.changes_at).getTime();
    const secondsLeft = Math.max(0, Math.round((changesAt - Date.now()) / 1000));
    const label = statusData.open
      ? PantheonI18n.t("settings.closesIn") || "Closes in"
      : PantheonI18n.t("settings.opensIn") || "Opens in";

    el.textContent = `${label}: ${fmtDuration(secondsLeft)}`;

    if (secondsLeft <= 0) refreshStatus();
  }

  function startTimers() {
    if (countdownTimer) clearInterval(countdownTimer);
    if (pollTimer) clearInterval(pollTimer);
    countdownTimer = setInterval(updateCountdownText, 1000);
    pollTimer = setInterval(refreshStatus, 30_000);
  }

  async function init() {
    await fetchSchedule();
    await refreshStatus();
    startTimers();

    const saveBtn = document.getElementById("oh-save");
    if (saveBtn) saveBtn.addEventListener("click", save);

    document.addEventListener("pantheon:i18n-changed", () => {
      renderDays();
      renderStatus();
    });
  }

  return { init };
})();
