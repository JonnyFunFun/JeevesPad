"use strict";

// Uses Home Assistant's own theme. The page runs inside Home Assistant (ingress serves it
// from the same origin), and Home Assistant sets its theme as CSS variables on its root
// element: light or dark, default or a custom theme. Copy the ones this page uses, and
// follow changes. Opened on its own, style.css's copy of the default theme is used instead.
(function () {
  const MAP = {
    "--bg": "--primary-background-color",
    "--surface": "--card-background-color",
    "--surface-2": "--input-fill-color",
    "--ink": "--primary-text-color",
    "--ink-2": "--secondary-text-color",
    "--line": "--divider-color",
    "--primary": "--primary-color",
    "--on-primary": "--text-primary-color",
    "--ok": "--success-color",
    "--warn": "--warning-color",
    "--bad": "--error-color",
    "--sans": "--ha-font-family-body",
  };

  function haRoot() {
    try {
      if (window.parent !== window && window.parent.document) return window.parent.document.documentElement;
    } catch (e) { /* not inside Home Assistant (another origin) */ }
    return null;
  }

  // Relative luminance of a CSS colour, to tell dark themes from light ones
  function isDark(color) {
    const probe = document.createElement("span");
    probe.style.color = color;
    document.body.append(probe);
    const rgb = getComputedStyle(probe).color.match(/[\d.]+/g);
    probe.remove();
    if (!rgb) return null;
    const [r, g, b] = rgb.slice(0, 3).map((v) => {
      const c = Number(v) / 255;
      return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    });
    return 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.25;
  }

  function apply(root) {
    const ha = getComputedStyle(root);
    const style = document.documentElement.style;
    for (const [ours, theirs] of Object.entries(MAP)) {
      const value = ha.getPropertyValue(theirs).trim();
      if (value) style.setProperty(ours, value);
      else style.removeProperty(ours);
    }
    const bg = ha.getPropertyValue("--primary-background-color").trim();
    const dark = bg ? isDark(bg) : null;
    if (dark === null) document.documentElement.removeAttribute("data-theme");
    else document.documentElement.setAttribute("data-theme", dark ? "dark" : "light");
  }

  function start() {
    const root = haRoot();
    if (!root) return;
    apply(root);
    // Home Assistant rewrites the root's inline style when the theme or dark mode changes
    new MutationObserver(() => apply(root)).observe(root, { attributes: true, attributeFilter: ["style", "class"] });
    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => apply(root));
  }

  if (document.body) start();
  else document.addEventListener("DOMContentLoaded", start);
})();
