"use strict";

// --- helpers ------------------------------------------------------------------------

function h(tag, attrs, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === undefined || v === null || v === false) continue;
    if (k === "class") el.className = v;
    else if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
    else if (k === "value") el.value = v;
    else if (k === "checked") el.checked = !!v;
    else if (k === "style") el.style.cssText = v;
    else el.setAttribute(k, v === true ? "" : v);
  }
  return append(el, children);
}

// Adds children like h() does: nested lists are flattened, and null/undefined/false
// (from `condition && element`) are skipped rather than shown as text
function append(el, children) {
  for (const child of children.flat(Infinity)) {
    if (child === null || child === undefined || child === false) continue;
    el.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return el;
}

// Replaces an element's contents; use instead of replaceChildren, which shows false and lists as text
function fill(el, ...children) {
  el.replaceChildren();
  return append(el, children);
}

async function api(path, opts = {}) {
  const init = { method: opts.method || "GET", headers: {} };
  if (opts.body instanceof FormData) init.body = opts.body;
  else if (opts.body !== undefined) {
    init.body = JSON.stringify(opts.body);
    init.headers["Content-Type"] = "application/json";
  }
  const res = await fetch("api/" + path, init);
  let data = null;
  try { data = await res.json(); } catch (e) { /* empty body */ }
  if (!res.ok) throw new Error((data && data.error) || `Request failed (${res.status})`);
  return data;
}

function toast(message, bad = false) {
  const el = h("div", { class: "toast" + (bad ? " bad" : "") }, message);
  document.getElementById("toasts").append(el);
  setTimeout(() => el.remove(), bad ? 7000 : 3500);
}

function ago(seconds) {
  if (seconds === undefined || seconds === null) return "";
  if (seconds < 60) return "just now";
  const m = Math.round(seconds / 60);
  if (m < 60) return `${m} min`;
  const hrs = Math.round(m / 60);
  return hrs < 48 ? `${hrs} h` : `${Math.round(hrs / 24)} days`;
}

const SIZES = [["xsmall", "X-Small"], ["small", "Small"], ["wide", "Wide"], ["tall", "Tall"], ["large", "Large"]];
const ICONS = [["living_room", "Living room"], ["bed", "Bedroom"], ["kitchen", "Kitchen"], ["bath", "Bathroom"],
  ["house", "House"], ["garage", "Garage"], ["work", "Office"], ["crib", "Nursery"]];
const TIMEOUTS = [[0, "Never"], [60, "1 minute"], [120, "2 minutes"], [180, "3 minutes"], [300, "5 minutes"],
  [600, "10 minutes"], [900, "15 minutes"], [1800, "30 minutes"]];
const MODELS = { "iPad2,5": "iPad mini", "iPad2,6": "iPad mini", "iPad2,7": "iPad mini", "iPad4,4": "iPad mini 2",
  "iPad4,5": "iPad mini 2", "iPad4,7": "iPad mini 3", "iPad2,1": "iPad 2", "iPad2,2": "iPad 2", "iPad2,3": "iPad 2",
  "iPad2,4": "iPad 2", "iPad3,1": "iPad (3rd gen)", "iPad3,4": "iPad (4th gen)", "iPad4,1": "iPad Air", "iPad4,2": "iPad Air" };

function select(options, value, attrs = {}) {
  return h("select", attrs, options.map(([v, label]) => h("option", { value: v, selected: String(v) === String(value) }, label)));
}

// --- state ---------------------------------------------------------------------------

const app = { tab: "pads", state: null, entities: null, entitiesLoading: null };

async function loadState() {
  try {
    app.state = await api("state");
  } catch (e) {
    if (!app.state) {
      document.getElementById("main").replaceChildren(h("div", { class: "empty" }, h("h2", {}, "Can't reach the wallPad manager"), e.message));
    }
    return;
  }
  if (!document.getElementById("sheet").hidden && app.sheetLocks) return; // don't disturb an open editor
  render();
}

async function loadEntities() {
  if (app.entities) return app.entities;
  if (!app.entitiesLoading) {
    app.entitiesLoading = api("entities").then((list) => {
      app.entities = list;
      const dl = document.getElementById("entity-list");
      dl.replaceChildren(...list.map((e) => h("option", { value: e.entity_id }, e.name)));
      return list;
    }).catch((e) => { app.entitiesLoading = null; toast(e.message, true); return []; });
  }
  return app.entitiesLoading;
}

function entityName(id) {
  const e = (app.entities || []).find((x) => x.entity_id === id);
  return e ? e.name : "";
}

function pads() { return (app.state && app.state.wallpads) || []; }
function onlinePads(exceptId) { return pads().filter((p) => p.online && p.id !== exceptId); }

// --- tabs ----------------------------------------------------------------------------

document.querySelectorAll(".tabs button").forEach((btn) => btn.addEventListener("click", () => {
  app.tab = btn.dataset.tab;
  document.querySelectorAll(".tabs button").forEach((b) => b.setAttribute("aria-selected", b === btn));
  history.replaceState(null, "", "#" + app.tab);
  render();
}));
{
  const initial = document.querySelector(`.tabs button[data-tab="${location.hash.slice(1)}"]`);
  if (initial) {
    app.tab = initial.dataset.tab;
    document.querySelectorAll(".tabs button").forEach((b) => b.setAttribute("aria-selected", b === initial));
  }
}

function render() {
  const main = document.getElementById("main");
  if (!app.state) return;
  const views = { pads: renderPads, setup: renderSetup, app: renderApp, fleet: renderFleet };
  // Keep form contents on tabs with forms: only the wallPads tab re-renders on refresh
  if (app.rendered === app.tab && app.tab !== "pads") return;
  app.rendered = app.tab;
  main.replaceChildren(views[app.tab]());
}

// --- wallPads ------------------------------------------------------------------------

function renderPads() {
  const list = pads();
  const toolbar = h("div", { class: "toolbar" },
    h("button", { class: "btn", onclick: async () => { await refreshAll(); } }, "Refresh status"),
    h("button", { class: "btn", onclick: addByAddress }, "Add by address…"),
    h("span", { class: "spacer" }),
    list.length > 1 && h("button", { class: "btn", onclick: () => openCopySheet() }, "Copy settings between wallPads…"));

  if (list.length === 0) {
    return h("div", {}, toolbar, h("div", { class: "empty" },
      h("h2", {}, "No wallPads yet"),
      h("p", {}, "wallPads show up here when Jeeves is running on them on this network."),
      h("p", {}, h("button", { class: "btn primary", onclick: () => switchTab("setup") }, "Set up an iPad"))));
  }
  return h("div", {}, toolbar, h("div", { class: "grid" }, list.map(padCard)));
}

async function refreshAll() {
  await Promise.all(onlinePads().map((p) => api(`wallpads/${encodeURIComponent(p.id)}/refresh`, { method: "POST" }).catch(() => null)));
  await loadState();
}

function switchTab(tab) {
  document.querySelector(`.tabs button[data-tab="${tab}"]`).click();
}

function padCard(pad) {
  const s = pad.status || {};
  const features = s.features || [];
  const canCommand = pad.online && features.includes("command");
  const brightness = typeof s.brightness === "number" ? s.brightness : null;
  const dark = !pad.online || s.dimmed;
  const glowOpacity = dark ? 0 : brightness === null ? 0.55 : 0.15 + brightness * 0.85;
  const battery = typeof s.battery === "number" && s.battery >= 0 ? Math.round(s.battery * 100) : null;
  const charging = s.batteryState === "charging" || s.batteryState === "full";
  const id = encodeURIComponent(pad.id);

  const chips = [];
  if (pad.online) chips.push(h("span", { class: "chip on" }, h("span", { class: "dot" }), "On the network"));
  else chips.push(h("span", { class: "chip" }, h("span", { class: "dot" }), "Not seen"));
  if (s.dimmed) chips.push(h("span", { class: "chip" }, "Dimmed"));
  if (pad.online && s.haConfigured === false) chips.push(h("span", { class: "chip warn" }, h("span", { class: "dot" }), "Not set up"));
  else if (pad.online && s.haConnected === false) chips.push(h("span", { class: "chip warn" }, h("span", { class: "dot" }), "Home Assistant unreachable"));

  const screen = h("div", { class: "screen" + (dark ? " dark" : "") },
    h("div", { class: "glow", style: `opacity:${glowOpacity}` }),
    h("div", {}, h("div", { class: "name" }, pad.name),
      h("div", { class: "meta" }, [MODELS[s.model] || s.model, s.systemVersion && `iOS ${s.systemVersion}`].filter(Boolean).join(" · "))),
    h("div", { class: "state" }, chips));
  const tablet = h("div", { class: "tablet", title: brightness !== null ? `Screen brightness ${Math.round(brightness * 100)}%` : "" }, screen,
    battery !== null && h("div", { class: "battery" + (battery < 20 && !charging ? " low" : "") }, h("i", { style: `width:${battery}%` })));

  const facts = h("dl", { class: "facts" },
    h("dt", {}, "Address"), h("dd", { class: "mono" }, pad.address || "—"),
    h("dt", {}, "Jeeves"), h("dd", {}, s.appVersion ? `${s.appVersion} (${s.appBuild})` : pad.app_version || "—"),
    battery !== null && [h("dt", {}, "Battery"), h("dd", {}, `${battery}%${charging ? (s.batteryState === "full" ? ", full" : ", charging") : ""}`)],
    s.idleSeconds !== undefined && [h("dt", {}, "Last touched"), h("dd", {}, ago(s.idleSeconds) === "just now" ? "just now" : `${ago(s.idleSeconds)} ago`)]);

  let note = null;
  if (pad.online && pad.sync_enabled === false) note = "Fleet sync is off on this iPad. Enrol it to manage its settings.";
  else if (pad.status_error) note = pad.status_error;

  const slider = canCommand && brightness !== null && h("label", { class: "brightness" }, "Brightness",
    h("input", { type: "range", min: 5, max: 100, value: Math.round(brightness * 100), "aria-label": `Brightness of ${pad.name}`,
      onchange: (e) => runCommand(pad, "brightness", Number(e.target.value) / 100) }));

  const actions = h("div", { class: "actions" },
    canCommand && h("button", { class: "btn small", onclick: () => runCommand(pad, "identify") }, "Identify"),
    canCommand && h("button", { class: "btn small", onclick: () => runCommand(pad, "home") }, "Go Home"),
    pad.online && h("button", { class: "btn small", onclick: () => openSettings(pad) }, "Settings"),
    pad.online && h("button", { class: "btn small", onclick: () => openDashboards(pad) }, "Dashboards"),
    h("button", { class: "btn small", onclick: () => openMaintenance(pad) }, "Maintenance"));

  return h("article", { class: "pad" + (pad.online ? "" : " offline"), "aria-label": pad.name },
    tablet, facts, note && h("p", { class: "note" }, note), slider, actions);
}

async function runCommand(pad, command, value) {
  try {
    await api(`wallpads/${encodeURIComponent(pad.id)}/command`, { method: "POST", body: { command, value } });
    const done = { identify: `${pad.name} is showing its name`, home: `${pad.name} went back to Home`,
      brightness: `Set ${pad.name}'s brightness`, reload: `Reloaded ${pad.name}`, wake: `Woke ${pad.name}` };
    toast(done[command] || "Done");
    if (command === "brightness") setTimeout(() => api(`wallpads/${encodeURIComponent(pad.id)}/refresh`, { method: "POST" }).then(loadState), 800);
  } catch (e) { toast(e.message, true); }
}

async function addByAddress() {
  const host = prompt("IP address or host name of the iPad (it's managed over SSH until Jeeves is found on the network):");
  if (!host) return;
  try { await api("wallpads", { method: "POST", body: { host } }); await loadState(); }
  catch (e) { toast(e.message, true); }
}

// --- side sheet ------------------------------------------------------------------------

function openSheet(title, body, footer, { lock = true } = {}) {
  const sheet = document.getElementById("sheet");
  const scrim = document.getElementById("scrim");
  const close = () => { sheet.hidden = true; scrim.hidden = true; app.sheetLocks = false; document.removeEventListener("keydown", onKey); loadState(); };
  const onKey = (e) => { if (e.key === "Escape") close(); };
  fill(sheet,
    h("header", {}, h("h2", {}, title), h("button", { class: "btn icon", "aria-label": "Close", onclick: close }, "✕")),
    h("div", { class: "body" }, body),
    footer && h("footer", {}, footer));
  sheet.hidden = false; scrim.hidden = false; app.sheetLocks = lock;
  scrim.onclick = close;
  document.addEventListener("keydown", onKey);
  const first = sheet.querySelector("input, select, textarea, button.primary");
  if (first) first.focus();
  return close;
}

// Runs an SSH action; asks for the root password if the iPad rejects the one on file
async function withPassword(pad, fn) {
  try { return await fn(null); }
  catch (e) {
    if (!/rejected the root password/.test(e.message)) throw e;
    const password = prompt(`${pad.name} rejected the root password. Enter its root password (it's remembered for this wallPad):`);
    if (!password) throw new Error("Cancelled");
    return await fn(password);
  }
}

// --- settings editor -------------------------------------------------------------------

async function openSettings(pad) {
  let view;
  try { view = await api(`wallpads/${encodeURIComponent(pad.id)}/settings`); }
  catch (e) { toast(e.message, true); return; }
  loadEntities();
  const v = view;
  const f = {
    ha_url: h("input", { type: "url", value: v.connection.ha_url, placeholder: "http://homeassistant.local:8123" }),
    ha_token: h("input", { type: "password", autocomplete: "off", placeholder: v.connection.ha_token_set ? "Saved — enter a new token to replace it" : "Long-lived access token" }),
    battery: h("input", { type: "checkbox", checked: v.connection.battery_reporting }),
    w_source: select([["automatic", "First weather entity in Home Assistant"], ["entity", "A specific weather entity"], ["none", "None (sensors only)"]], v.weather.source),
    w_entity: h("input", { list: "entity-list", value: v.weather.entity_id, placeholder: "weather.home" }),
    w_temp: h("input", { list: "entity-list", value: v.weather.temperature_entity_id, placeholder: "Use the weather entity's temperature" }),
    w_readings: h("textarea", { rows: 3, placeholder: "One sensor per line, e.g. sensor.outdoor_humidity" }, v.weather.reading_entity_ids.join("\n")),
    timeout: select(TIMEOUTS, v.idle.home_timeout),
    dims: h("input", { type: "checkbox", checked: v.idle.dims_when_idle }),
    jf_enabled: h("input", { type: "checkbox", checked: v.jellyfin.enabled }),
    jf_url: h("input", { type: "url", value: v.jellyfin.server_url, placeholder: "http://jellyfin.local:8096" }),
  };
  const others = onlinePads(pad.id);
  const also = others.map((p) => ({ pad: p, box: h("input", { type: "checkbox" }) }));

  const body = h("div", {},
    h("h3", {}, "Home Assistant"),
    h("label", { class: "field" }, h("span", {}, "Address"), f.ha_url),
    h("label", { class: "field" }, h("span", {}, "Access token"), f.ha_token,
      h("small", {}, "Use an administrator's token if people will register phones from this panel.")),
    h("label", { class: "check" }, f.battery, h("span", {}, "Report battery level to Home Assistant")),
    h("h3", {}, "Home weather"),
    h("label", { class: "field" }, h("span", {}, "Conditions and forecast from"), f.w_source),
    h("label", { class: "field" }, h("span", {}, "Weather entity"), f.w_entity),
    h("label", { class: "field" }, h("span", {}, "Temperature from"), f.w_temp),
    h("label", { class: "field" }, h("span", {}, "Extra readings"), f.w_readings),
    h("h3", {}, "When idle"),
    h("label", { class: "field" }, h("span", {}, "Go back to Home after"), f.timeout),
    h("label", { class: "check" }, f.dims, h("span", {}, "Dim the screen at twice that time")),
    h("h3", {}, "Jellyfin"),
    h("label", { class: "check" }, f.jf_enabled, h("span", {}, "Show Jellyfin")),
    h("label", { class: "field" }, h("span", {}, "Server address"), f.jf_url),
    others.length > 0 && [h("h3", {}, "Also apply to"),
      also.map(({ pad: p, box }) => h("label", { class: "check" }, box, h("span", {}, p.name)))]);

  const save = h("button", { class: "btn primary" }, "Save settings");
  const close = openSheet(`${pad.name}: settings`, body, [h("span", { class: "spacer" }), save]);
  save.onclick = async () => {
    const settings = {
      connection: { ha_url: f.ha_url.value, ha_token: f.ha_token.value, battery_reporting: f.battery.checked },
      weather: { source: f.w_source.value, entity_id: f.w_entity.value.trim(), temperature_entity_id: f.w_temp.value.trim(),
        reading_entity_ids: f.w_readings.value.split(/\s+/).map((s) => s.trim()).filter(Boolean) },
      idle: { home_timeout: Number(f.timeout.value), dims_when_idle: f.dims.checked },
      jellyfin: { enabled: f.jf_enabled.checked, server_url: f.jf_url.value },
    };
    save.disabled = true;
    try {
      const res = await api(`wallpads/${encodeURIComponent(pad.id)}/settings`, { method: "PUT",
        body: { settings, sections: Object.keys(settings), also: also.filter((a) => a.box.checked).map((a) => a.pad.id) } });
      reportCopies(res.copied);
      toast(`Saved ${pad.name}'s settings`);
      close();
    } catch (e) { toast(e.message, true); save.disabled = false; }
  };
}

function reportCopies(results) {
  const failed = Object.entries(results || {}).filter(([, err]) => err);
  failed.forEach(([id, err]) => toast(`${(pads().find((p) => p.id === id) || {}).name || id}: ${err}`, true));
}

// --- dashboard editor --------------------------------------------------------------------

async function openDashboards(pad) {
  let view;
  try { view = await api(`wallpads/${encodeURIComponent(pad.id)}/settings`); }
  catch (e) { toast(e.message, true); return; }
  await loadEntities();
  const dash = view.dashboards;
  const model = { home: dash.home_cards.map((c) => ({ ...c })), rooms: dash.rooms.map((r) => ({ ...r, cards: r.cards.map((c) => ({ ...c })) })) };
  const body = h("div", {});
  const others = onlinePads(pad.id);
  const also = others.map((p) => ({ pad: p, box: h("input", { type: "checkbox" }) }));

  function move(list, i, delta) {
    const j = i + delta;
    if (j < 0 || j >= list.length) return;
    [list[i], list[j]] = [list[j], list[i]];
    draw();
  }

  function cardList(cards) {
    return h("div", { class: "cards" },
      cards.length > 0 && h("div", { class: "list-head" }, h("span", {}, "Entity"), h("span", {}, "Card name"), h("span", {}, "Size"), h("span", {})),
      cards.map((card, i) => h("div", { class: "card-row" },
        h("input", { list: "entity-list", value: card.entity_id, placeholder: "light.kitchen", "aria-label": "Entity",
          oninput: (e) => { card.entity_id = e.target.value.trim(); } }),
        h("input", { value: card.name, placeholder: entityName(card.entity_id) || "Home Assistant's name", "aria-label": "Card name",
          oninput: (e) => { card.name = e.target.value; } }),
        select(SIZES, card.size, { "aria-label": "Size", onchange: (e) => { card.size = e.target.value; } }),
        h("div", { class: "moves" },
          h("button", { class: "btn icon small", "aria-label": "Move up", onclick: () => move(cards, i, -1) }, "↑"),
          h("button", { class: "btn icon small", "aria-label": "Move down", onclick: () => move(cards, i, 1) }, "↓"),
          h("button", { class: "btn icon small danger", "aria-label": "Remove card", onclick: () => { cards.splice(i, 1); draw(); } }, "✕")))),
      h("div", {}, h("button", { class: "btn small", onclick: () => { cards.push({ entity_id: "", name: "", size: "small" }); draw(); } }, "Add a card")));
  }

  function draw() {
    fill(body,
      h("p", { class: "lede" }, "Cards appear in this order. Card names and sizes only change how this wallPad shows them; nothing is renamed in Home Assistant."),
      h("h3", {}, "Home"),
      cardList(model.home),
      h("h3", {}, "Rooms"),
      !dash.rooms_editable && h("p", { class: "note" }, "This version of Jeeves can't have its rooms edited from here. Update the app to edit rooms."),
      dash.rooms_editable && [
        model.rooms.length === 0 && h("p", { class: "muted" }, "No rooms yet."),
        model.rooms.map((room, i) => h("section", { class: "room", "aria-label": room.name || "New room" },
          h("div", { class: "room-head" },
            h("input", { value: room.name, placeholder: "Room name", "aria-label": "Room name", oninput: (e) => { room.name = e.target.value; } }),
            select(ICONS, room.icon, { "aria-label": "Icon", onchange: (e) => { room.icon = e.target.value; } }),
            h("div", { class: "moves" },
              h("button", { class: "btn icon small", "aria-label": "Move room up", onclick: () => move(model.rooms, i, -1) }, "↑"),
              h("button", { class: "btn icon small", "aria-label": "Move room down", onclick: () => move(model.rooms, i, 1) }, "↓"),
              h("button", { class: "btn icon small danger", "aria-label": "Delete room", onclick: () => {
                if (confirm(`Delete ${room.name || "this room"} from ${pad.name}?`)) { model.rooms.splice(i, 1); draw(); } } }, "✕"))),
          cardList(room.cards))),
        h("button", { class: "btn", onclick: () => { model.rooms.push({ room_id: "", name: "", icon: "living_room", cards: [] }); draw(); } }, "Add a room")],
      others.length > 0 && [h("h3", {}, "Also apply to"),
        also.map(({ pad: p, box }) => h("label", { class: "check" }, box, h("span", {}, p.name)))]);
  }
  draw();

  const save = h("button", { class: "btn primary" }, "Save dashboards");
  const close = openSheet(`${pad.name}: dashboards`, body, [h("span", { class: "spacer" }), save]);
  save.onclick = async () => {
    const clean = (cards) => cards.filter((c) => c.entity_id);
    const dashboards = { home_cards: clean(model.home),
      rooms: dash.rooms_editable ? model.rooms.map((r) => ({ ...r, cards: clean(r.cards) })) : null };
    save.disabled = true;
    try {
      const res = await api(`wallpads/${encodeURIComponent(pad.id)}/settings`, { method: "PUT",
        body: { settings: { dashboards }, sections: ["dashboards"], also: also.filter((a) => a.box.checked).map((a) => a.pad.id) } });
      reportCopies(res.copied);
      toast(`Saved ${pad.name}'s dashboards`);
      close();
    } catch (e) { toast(e.message, true); save.disabled = false; }
  };
}

// --- maintenance (SSH) -----------------------------------------------------------------

function openMaintenance(pad) {
  const id = encodeURIComponent(pad.id);
  const out = h("div", {});
  const sshHost = h("input", { value: pad.ssh_host || "", placeholder: pad.host || "IP address" });

  async function ssh(action, label, confirmText) {
    if (confirmText && !confirm(confirmText)) return;
    try {
      const res = await withPassword(pad, (password) => api(`wallpads/${id}/ssh/${action}`, { method: "POST", body: { password } }));
      if (action === "logs") out.replaceChildren(h("div", { class: "log" }, res.result.text));
      else if (action === "check") {
        const r = res.result;
        out.replaceChildren(h("dl", { class: "facts" },
          h("dt", {}, "Model"), h("dd", {}, MODELS[r.model] || r.model || "?"),
          h("dt", {}, "iOS"), h("dd", {}, r.ios || "?"),
          h("dt", {}, "Jeeves installed"), h("dd", {}, r.installed === "1" ? "Yes" : "No"),
          h("dt", {}, "uicache"), h("dd", {}, r.uicache === "1" ? "Installed" : "Missing: install UIKit Tools from Cydia"),
          h("dt", {}, "Remote launch"), h("dd", {}, r.open === "1" || r.uiopen === "1" ? "Available" : "Missing: install Open from Cydia")));
      } else toast(label);
    } catch (e) { if (e.message !== "Cancelled") toast(e.message, true); }
  }

  async function enrol() {
    const source = onlinePads(pad.id).length ? prompt(
      "Also copy settings from another wallPad? Type its name, or leave empty to only add this iPad to the fleet:", "") : "";
    if (source === null) return;
    let settingsSource = null;
    if (source) {
      const from = pads().find((p) => p.name.toLowerCase() === source.trim().toLowerCase());
      if (!from) { toast(`There's no wallPad called ${source}`, true); return; }
      settingsSource = `copy:${from.id}`;
    }
    try {
      const job = await withPassword(pad, (password) => api(`wallpads/${id}/enrol`, { method: "POST", body: { password, settings_source: settingsSource } }));
      showJob(job, out);
    } catch (e) { if (e.message !== "Cancelled") toast(e.message, true); }
  }

  async function updateApp() {
    try { showJob(await api("update-app", { method: "POST", body: { wallpads: [pad.id] } }), out); }
    catch (e) { toast(e.message, true); }
  }

  const body = h("div", {},
    h("p", { class: "lede" }, "These actions use SSH, so they work even when Jeeves isn't running. They use the root password from the app's configuration unless this wallPad has its own."),
    h("div", { class: "toolbar" },
      h("button", { class: "btn", onclick: () => ssh("restart_app", `Restarted Jeeves on ${pad.name}`) }, "Restart Jeeves"),
      h("button", { class: "btn", onclick: updateApp }, "Install the current app package"),
      h("button", { class: "btn", onclick: enrol }, "Enrol in this fleet"),
      h("button", { class: "btn", onclick: () => ssh("logs") }, "Show logs"),
      h("button", { class: "btn", onclick: () => ssh("check") }, "Check the iPad")),
    h("div", { class: "toolbar" },
      pad.online && pad.status && (pad.status.features || []).includes("command") &&
        h("button", { class: "btn", onclick: () => runCommand(pad, "reload") }, "Reload the screen"),
      h("button", { class: "btn", onclick: () => ssh("respring", `Restarted ${pad.name}'s home screen`, `Restart the home screen of ${pad.name}?`) }, "Respring"),
      h("button", { class: "btn danger", onclick: () => ssh("reboot", `${pad.name} is rebooting`, `Reboot ${pad.name}? On many iOS 9 jailbreaks you have to re-run the jailbreak app on the iPad afterwards.`) }, "Reboot")),
    out,
    h("h3", {}, "Connection"),
    h("label", { class: "field" }, h("span", {}, "SSH address"), sshHost, h("small", {}, "Leave empty to use the address it's found at.")),
    h("div", { class: "toolbar" },
      h("button", { class: "btn small", onclick: async () => {
        try { await api(`wallpads/${id}`, { method: "PATCH", body: { ssh_host: sshHost.value } }); toast("Saved"); } catch (e) { toast(e.message, true); } } }, "Save address"),
      pad.has_ssh_password && h("button", { class: "btn small", onclick: async () => {
        try { await api(`wallpads/${id}`, { method: "PATCH", body: { ssh_password: "" } }); toast("Forgot its root password"); } catch (e) { toast(e.message, true); } } }, "Forget its root password"),
      h("button", { class: "btn small", onclick: () => ssh("forget_host_key", "Forgot its SSH host key") }, "Forget SSH host key"),
      h("span", { class: "spacer" }),
      h("button", { class: "btn small danger", onclick: async () => {
        if (!confirm(`Remove ${pad.name} from this list? Jeeves on the iPad isn't changed, and it reappears if it's found on the network.`)) return;
        try { await api(`wallpads/${id}`, { method: "DELETE" }); closeSheet(); } catch (e) { toast(e.message, true); } } }, "Remove from list")));

  const closeSheet = openSheet(`${pad.name}: maintenance`, body, null, { lock: false });
}

// --- jobs ------------------------------------------------------------------------------

function showJob(job, container) {
  const state = h("span", { class: "job-state" });
  const log = h("div", { class: "log", role: "log" });
  container.replaceChildren(h("p", {}, h("strong", {}, job.title), " — ", state), log);
  const draw = (j) => {
    state.textContent = { running: "working…", done: "finished", failed: "failed" }[j.state];
    state.className = "job-state " + j.state;
    log.replaceChildren(...j.log.map((l) => h("div", { class: /^(Failed|Couldn't)/.test(l.line) ? "fail" : "" }, l.line)));
    log.scrollTop = log.scrollHeight;
  };
  draw(job);
  const timer = setInterval(async () => {
    try {
      const j = await api(`jobs/${job.id}`);
      draw(j);
      if (j.state !== "running") { clearInterval(timer); loadState(); }
    } catch (e) { clearInterval(timer); }
  }, 1500);
}

function packageNote(pkg) {
  if (pkg.active === "custom") return `Jeeves ${pkg.custom.version} from your uploaded package will be installed (see the App package tab).`;
  if (pkg.active === "published") return `Jeeves ${pkg.published.version} from the published release will be installed. To install your own build, upload it on the App package tab.`;
  return "The published release will be downloaded and installed. To install your own build, upload it on the App package tab first.";
}

// --- set up an iPad --------------------------------------------------------------------

function renderSetup() {
  const st = app.state;
  const host = h("input", { placeholder: "192.168.1.50", autocomplete: "off" });
  const password = h("input", { type: "password", autocomplete: "off", placeholder: st.default_password ? "alpine (the default)" : "The root password from the app's configuration" });
  const sources = pads().filter((p) => p.online);
  const choice = { value: sources.length ? "copy" : (st.has_wallpad_token ? "ha" : "none") };
  const copyFrom = select(sources.map((p) => [p.id, p.name]), sources[0] && sources[0].id);
  const haUrl = h("input", { type: "url", value: st.wallpad_ha_url || "", placeholder: "http://192.168.1.10:8123" });
  const haToken = h("input", { type: "password", autocomplete: "off", placeholder: st.has_wallpad_token ? "From the app's configuration" : "Long-lived access token" });
  const radio = (value, label, extra) => h("div", {},
    h("label", { class: "check" }, h("input", { type: "radio", name: "src", value, checked: choice.value === value, disabled: value === "copy" && !sources.length,
      onchange: () => { choice.value = value; } }), h("span", {}, label)),
    extra && h("div", { style: "margin-left: 26px" }, extra));
  const out = h("div", {});
  const start = h("button", { class: "btn primary" }, "Install Jeeves");
  start.onclick = async () => {
    const settings_source = choice.value === "copy" ? `copy:${copyFrom.value}` : choice.value === "ha" ? "ha" : null;
    try {
      const job = await api("provision", { method: "POST", body: { host: host.value, password: password.value,
        settings_source, ha_url: haUrl.value, ha_token: haToken.value } });
      showJob(job, out);
    } catch (e) { toast(e.message, true); }
  };

  return h("div", {},
    h("section", { class: "panel" },
      h("h2", {}, "Set up an iPad"),
      h("p", { class: "lede" }, "Installs Jeeves on a jailbroken iPad over SSH, adds it to this fleet and starts it."),
      h("h3", {}, "Before you start"),
      h("ol", { class: "steps" },
        h("li", {}, "Jailbreak the iPad (Jeeves is made for iOS 9.3.5)."),
        h("li", {}, "In Cydia, install OpenSSH, UIKit Tools and Open."),
        h("li", {}, "Connect it to the same network as Home Assistant and note its IP address (Settings → Wi-Fi → ⓘ)."),
        h("li", {}, packageNote(st.package))),
      h("div", { class: "row" },
        h("label", { class: "field" }, h("span", {}, "IP address"), host),
        h("label", { class: "field" }, h("span", {}, "Root password"), password)),
      h("h3", {}, "Settings for the new wallPad"),
      radio("copy", "Copy everything from another wallPad", sources.length ? h("label", { class: "field" }, copyFrom) : h("small", { class: "muted" }, "No wallPads are on the network right now.")),
      radio("ha", "Just connect it to Home Assistant", h("div", { class: "row" },
        h("label", { class: "field" }, h("span", {}, "Address"), haUrl),
        h("label", { class: "field" }, h("span", {}, "Access token"), haToken))),
      radio("none", "Nothing: I'll set it up on the iPad"),
      h("div", { class: "toolbar", style: "margin-top: 18px" }, start),
      out));
}

// --- app package -------------------------------------------------------------------------

function renderApp() {
  const out = h("div", {});
  const panels = h("div", {});
  const file = h("input", { type: "file", accept: ".ipa", "aria-label": "Jeeves.ipa file" });
  const url = h("input", { type: "url", placeholder: "Latest GitHub release (default)", "aria-label": "Download address" });

  const facts = (p) => h("dl", { class: "facts" },
    h("dt", {}, "Version"), h("dd", {}, `${p.version} (${p.build})`),
    h("dt", {}, "From"), h("dd", { class: "mono" }, p.source),
    h("dt", {}, "Added"), h("dd", {}, new Date(p.added * 1000).toLocaleString()));
  const inUse = (slot) => app.state.package.active === slot && h("span", { class: "badge" }, "In use");

  async function busy(button, work) {
    button.disabled = true;
    try { app.state.package = await work(); draw(); }
    catch (e) { toast(e.message, true); }
    button.disabled = false;
  }

  const upload = h("button", { class: "btn primary", onclick: () => {
    if (!file.files.length) { toast("Choose a Jeeves.ipa file first", true); return; }
    const form = new FormData();
    form.append("file", file.files[0]);
    busy(upload, async () => {
      const info = await api("package/upload", { method: "POST", body: form });
      toast(`Uploaded Jeeves ${info.custom.version}. wallPads will get this package.`);
      file.value = "";
      return info;
    });
  } }, "Upload");
  const remove = h("button", { class: "btn danger", onclick: () => {
    const fallback = app.state.package.published;
    if (!confirm(fallback
      ? `Remove your package? wallPads will get the published release (Jeeves ${fallback.version}) from now on. Nothing changes on wallPads until you update them.`
      : "Remove your package? There's no published release downloaded, so the next update or setup downloads one.")) return;
    busy(remove, async () => { const info = await api("package/custom", { method: "DELETE" }); toast("Removed your package"); return info; });
  } }, "Remove my package");
  const download = h("button", { class: "btn", onclick: () => busy(download, async () => {
    const info = await api("package/download", { method: "POST", body: { url: url.value } });
    toast(info.active === "custom"
      ? `Downloaded Jeeves ${info.published.version}. Your uploaded package is still the one in use.`
      : `Downloaded Jeeves ${info.published.version}`);
    return info;
  }) }, "Download");

  function draw() {
    const pkg = app.state.package;
    fill(panels, 
      h("section", { class: "panel" + (pkg.active === "custom" ? " active" : "") },
        h("div", { class: "panel-head" }, h("h2", {}, "Your package"), inUse("custom")),
        h("p", { class: "lede" }, "Upload a Jeeves.ipa of your own, such as one you built with build_ipa.sh. While it's here, it's installed instead of the published release."),
        pkg.custom ? facts(pkg.custom) : h("p", { class: "muted" }, "None uploaded."),
        h("div", { class: "row", style: "margin-top: 14px; align-items: center" }, file,
          h("div", { class: "toolbar", style: "flex: 0 0 auto; margin: 0" }, upload, pkg.custom && remove))),
      h("section", { class: "panel" + (pkg.active === "published" ? " active" : "") },
        h("div", { class: "panel-head" }, h("h2", {}, "Published release"), inUse("published")),
        h("p", { class: "lede" }, pkg.custom
          ? "Used when you remove your package."
          : "Downloaded from the JeevesPad releases on GitHub, or another address."),
        pkg.published ? facts(pkg.published) : h("p", { class: "muted" }, "Not downloaded yet. Setting up or updating a wallPad downloads it if there's no package."),
        h("div", { class: "row", style: "margin-top: 14px" }, url, h("div", { style: "flex: 0 0 auto" }, download))),
      updatePanel());
  }

  function updatePanel() {
    const pkg = app.state.package;
    const active = pkg.active && pkg[pkg.active];
    const targets = pads().map((p) => ({ pad: p, box: h("input", { type: "checkbox", checked: true }) }));
    const update = h("button", { class: "btn primary", onclick: async () => {
      const ids = targets.filter((t) => t.box.checked).map((t) => t.pad.id);
      const what = active ? `${pkg.active === "custom" ? "your package" : "the published release"} (Jeeves ${active.version})` : "the published release";
      if (!confirm(`Install ${what} on ${ids.length} wallPad(s)? Jeeves restarts on each; settings are kept.`)) return;
      try { showJob(await api("update-app", { method: "POST", body: { wallpads: ids } }), out); }
      catch (e) { toast(e.message, true); }
    } }, active ? `Install Jeeves ${active.version} on selected wallPads` : "Update selected wallPads");
    return h("section", { class: "panel" }, h("h2", {}, "Update wallPads"),
      targets.length === 0 ? h("p", { class: "muted" }, "No wallPads yet.") :
        [targets.map(({ pad, box }) => h("label", { class: "check" }, box, h("span", {}, pad.name,
          h("span", { class: "muted" }, " — now ", (pad.status && pad.status.appVersion) || pad.app_version || "version unknown")))),
         h("div", { class: "toolbar" }, update)],
      out);
  }

  draw();
  return panels;
}

// --- fleet ---------------------------------------------------------------------------------

function renderFleet() {
  const st = app.state;
  const code = h("span", { class: "code" }, "••••-••••-••••-••••");
  let shown = false;
  const toggle = h("button", { class: "btn small", onclick: () => { shown = !shown; code.textContent = shown ? st.fleet_code : "••••-••••-••••-••••"; toggle.textContent = shown ? "Hide" : "Show"; } }, "Show");
  const copy = h("button", { class: "btn small", onclick: async () => {
    try { await navigator.clipboard.writeText(st.fleet_code); toast("Copied the fleet code"); } catch (e) { toast("Couldn't copy; use Show and copy it by hand", true); } } }, "Copy");
  return h("div", {},
    h("section", { class: "panel" }, h("h2", {}, "Fleet code"),
      h("p", { class: "lede" }, "wallPads share settings with each other and with Home Assistant only when they use the same fleet code. It also encrypts everything sent between them, including the Home Assistant token."),
      h("div", { class: "toolbar" }, code, toggle, copy),
      h("p", { class: "muted" }, st.fleet_code_generated
        ? "This code was generated by the app. To use your own, set Fleet code in the app's configuration."
        : "This code is set in the app's configuration."),
      h("h3", {}, "Adding wallPads that already run Jeeves"),
      h("ol", { class: "steps" },
        h("li", {}, "Over SSH: open the wallPad's Maintenance and choose Enrol in this fleet. Jeeves restarts with fleet sync on and this code."),
        h("li", {}, "Or on the iPad: Settings → Fleet, turn on Fleet sync and enter this code."))),
    h("section", { class: "panel" }, h("h2", {}, "Copy settings between wallPads"),
      h("p", { class: "lede" }, "Make one wallPad the model for others."),
      h("button", { class: "btn", disabled: pads().length < 2, onclick: () => openCopySheet() }, "Choose wallPads…")));
}

function openCopySheet() {
  const online = onlinePads();
  if (online.length < 2) { toast("At least two wallPads need to be on the network", true); return; }
  const source = select(online.map((p) => [p.id, p.name]), online[0].id);
  const targets = online.map((p) => ({ pad: p, box: h("input", { type: "checkbox" }) }));
  const sections = [["connection", "Home Assistant connection"], ["dashboards", "Home cards and rooms"], ["weather", "Home weather"],
    ["idle", "When idle"], ["jellyfin", "Jellyfin"]].map(([key, label]) => ({ key, label, box: h("input", { type: "checkbox", checked: true }) }));
  const body = h("div", {},
    h("label", { class: "field" }, h("span", {}, "Copy from"), source),
    h("h3", {}, "To"), targets.map(({ pad, box }) => h("label", { class: "check" }, box, h("span", {}, pad.name))),
    h("h3", {}, "Settings"), sections.map(({ label, box }) => h("label", { class: "check" }, box, h("span", {}, label))),
    h("p", { class: "muted" }, "Each wallPad keeps its own battery webhook, Jellyfin sign-in and wake-on-motion setting."));
  const go = h("button", { class: "btn primary" }, "Copy settings");
  const close = openSheet("Copy settings", body, [h("span", { class: "spacer" }), go]);
  go.onclick = async () => {
    const ids = targets.filter((t) => t.box.checked && t.pad.id !== source.value).map((t) => t.pad.id);
    const chosen = sections.filter((s) => s.box.checked).map((s) => s.key);
    if (!ids.length || !chosen.length) { toast("Choose at least one wallPad and one kind of setting", true); return; }
    go.disabled = true;
    try {
      const res = await api("copy-settings", { method: "POST", body: { source: source.value, targets: ids, sections: chosen } });
      const failed = Object.values(res.results).filter(Boolean).length;
      reportCopies(res.results);
      toast(`Copied settings to ${ids.length - failed} of ${ids.length} wallPads`, failed > 0);
      close();
    } catch (e) { toast(e.message, true); go.disabled = false; }
  };
}

// --- start --------------------------------------------------------------------------------

loadState();
setInterval(() => { if (app.tab === "pads") loadState(); }, 10000);
