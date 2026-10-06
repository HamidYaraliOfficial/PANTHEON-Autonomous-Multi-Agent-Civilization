/* PANTHEON — i18n.js
 * Minimal, dependency-free i18n: loads locales/<lang>.json, applies it to
 * every [data-i18n] / [data-i18n-placeholder] element, sets <html lang>
 * and <html dir> (this is what actually flips the whole layout between
 * RTL for Persian and LTR for English/Chinese — see layout.css, which
 * uses logical CSS properties throughout instead of left/right).
 */
const PantheonI18n = (() => {
  const SUPPORTED = ["en", "fa", "zh"];
  const STORAGE_KEY = "pantheon_lang";
  let dict = {};
  let currentLang = "en";

  function detectDefault() {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved && SUPPORTED.includes(saved)) return saved;
    const nav = (navigator.language || "en").slice(0, 2);
    return SUPPORTED.includes(nav) ? nav : "en";
  }

  function get(path) {
    return path.split(".").reduce((o, k) => (o && o[k] !== undefined ? o[k] : null), dict);
  }

  function applyToDom() {
    document.documentElement.setAttribute("lang", currentLang);
    document.documentElement.setAttribute("dir", dict.dir || "ltr");

    document.querySelectorAll("[data-i18n]").forEach((el) => {
      const val = get(el.getAttribute("data-i18n"));
      if (val) el.textContent = val;
    });

    document.querySelectorAll("[data-i18n-placeholder]").forEach((el) => {
      const val = get(el.getAttribute("data-i18n-placeholder"));
      if (val) el.setAttribute("placeholder", val);
    });

    document.querySelectorAll('select[id^="lang-select"]').forEach((el) => {
      el.value = currentLang;
    });
  }

  async function load(lang) {
    if (!SUPPORTED.includes(lang)) lang = "en";
    const res = await fetch(`locales/${lang}.json`, { cache: "no-store" });
    dict = await res.json();
    currentLang = lang;
    localStorage.setItem(STORAGE_KEY, lang);
    applyToDom();
    document.dispatchEvent(new CustomEvent("pantheon:i18n-changed", { detail: { lang } }));
  }

  function init() {
    return load(detectDefault());
  }

  function wireLanguageSelectors() {
    ["lang-select", "lang-select-settings"].forEach((id) => {
      const el = document.getElementById(id);
      if (el) el.addEventListener("change", (e) => load(e.target.value));
    });
  }

  return {
    init,
    load,
    t: get,
    wireLanguageSelectors,
    get currentLang() {
      return currentLang;
    },
  };
})();
