// Theme manager for dark mode support.
// Reads preference from <meta name="theme"> (server-rendered) or localStorage,
// falls back to system preference.

const STORAGE_KEY = "shroud-theme";

function getPreference() {
  const meta = document.querySelector('meta[name="theme"]');
  const serverPref = meta ? meta.content : null;
  if (serverPref && serverPref !== "system") return serverPref;

  const stored = localStorage.getItem(STORAGE_KEY);
  if (stored && stored !== "system") return stored;

  return "system";
}

function resolveTheme(preference) {
  if (preference === "dark") return "dark";
  if (preference === "light") return "light";
  // "system" — use OS preference
  return window.matchMedia("(prefers-color-scheme: dark)").matches
    ? "dark"
    : "light";
}

function applyTheme(preference) {
  const resolved = resolveTheme(preference);
  document.documentElement.classList.toggle("dark", resolved === "dark");
}

export function setTheme(preference) {
  localStorage.setItem(STORAGE_KEY, preference);
  applyTheme(preference);
}

export function initTheme() {
  const pref = getPreference();
  applyTheme(pref);

  // Re-evaluate when OS preference changes (relevant when set to "system")
  window
    .matchMedia("(prefers-color-scheme: dark)")
    .addEventListener("change", () => {
      const current = getPreference();
      if (current === "system") applyTheme("system");
    });
}
