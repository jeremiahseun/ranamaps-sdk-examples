// Rana SDK demo: exercises every public call of the web SDK against the live API, and the Rana Kit
// features as soon as the SDK has them. Serve the repository root and open /sdk/demo-web/.
import { Rana } from "../node_modules/@ranamaps/maps-js/dist/index.js";

const $ = (id) => document.getElementById(id);
const EPE = { lat: 6.5844, lng: 3.9846 };
const state = { key: "", map: null, client: null, from: null, to: null, mode: "okada", markers: [], lines: [], kit: [], click: null };

$("origin").textContent = location.origin;
window.demo = state; // for debugging in the browser console

// ---------- call log ----------
function log(name, status, ms, detail) {
  const li = document.createElement("li");
  li.className = status === "ok" ? "ok" : "bad";
  li.innerHTML = `<span class="s">${status === "ok" ? "OK" : "ERR"}</span><span>${name}</span><span class="m">${ms} ms</span>`;
  if (detail) { const d = document.createElement("span"); d.className = "d"; d.textContent = detail; li.append(d); }
  $("log").prepend(li);
}
async function call(name, fn) {
  const t = performance.now();
  try { const r = await fn(); log(name, "ok", Math.round(performance.now() - t)); return r; }
  catch (e) { log(name, "bad", Math.round(performance.now() - t), `${e.code ?? "error"}: ${e.message}`); throw e; }
}
$("clearLog").onclick = () => { $("log").textContent = ""; };

// ---------- key ----------
function setKeyState(text, kind) { const p = $("keyState"); p.textContent = text; p.className = "pill" + (kind ? " " + kind : ""); }
async function useKey(key) {
  state.key = key.trim();
  try { localStorage.setItem("rana-demo-key", state.key); } catch {}
  if (state.map) { state.map.remove(); state.map = null; }
  try { state.client = new Rana.RanaClient(state.key); }
  catch (e) { setKeyState("Bad key", "bad"); $("keyInfo").textContent = e.message; return; }
  state.map = new Rana.Map({ key: state.key, container: "map", style: "day", center: EPE, zoom: 14 });
  state.map.on("click", onMapClick);
  state.map.on("error", (e) => log("map", "bad", 0, e.message));
  state.map.on("load", () => { log("map loaded", "ok", 0); refreshKit(); });
  try {
    const info = await call("describeKey", () => state.client.describeKey());
    setKeyState(info.plan ? `Key OK · ${info.plan}` : "Key OK", "ok");
    $("keyInfo").textContent = `${info.key?.kind ?? "public"} key · plan ${info.plan ?? "unknown"} · organisation ${String(info.organisation_id ?? "").slice(0, 8)}`;
  } catch (e) {
    if (e.code === "network_error") {
      setKeyState("API unreachable", "bad");
      $("keyInfo").textContent = `The browser could not reach the API (${e.message}). Check connectivity, the browser console and the key’s allowed origin.`;
    } else {
      setKeyState(e.code === "client_not_allowed" ? "Origin not allowed" : "Key refused", "bad");
      $("keyInfo").textContent = `${e.code}: ${e.message.replace(/\.$/, "")}. Add ${location.origin} to this key's web origins in Rana Studio.`;
    }
  }
}
$("keyForm").onsubmit = (e) => { e.preventDefault(); useKey($("key").value); };
const fromUrl = new URLSearchParams(location.search).get("key");
let saved = ""; try { saved = localStorage.getItem("rana-demo-key") || ""; } catch {}
$("key").value = fromUrl || saved;
if ($("key").value) useKey($("key").value);

// ---------- helpers ----------
const fmtKm = (m) => m >= 1000 ? `${(m / 1000).toFixed(1)} km` : `${Math.round(m)} m`;
const fmtMin = (s) => s >= 3600 ? `${Math.floor(s / 3600)} h ${Math.round((s % 3600) / 60)} min` : `${Math.max(1, Math.round(s / 60))} min`;
function pin(point, content, style) { const m = state.map.addMarker(point, content, style); state.markers.push(m); return m; }
function clearMap() {
  state.markers.forEach((m) => m.remove()); state.lines.forEach((l) => l.remove()); state.kit.forEach((k) => k.remove?.());
  state.markers = []; state.lines = []; state.kit = [];
  $("clickCard").hidden = true;
}
$("clear").onclick = clearMap;
function needMap() { if (!state.map) { setKeyState("Add a key first", "bad"); return false; } return true; }
function setStop(which, point, label) {
  state[which] = point;
  $(which === "from" ? "fromText" : "toText").textContent = label;
  $(which === "from" ? "fromText" : "toText").className = "";
}
function stopButtons(point, label) {
  const row = document.createElement("div"); row.className = "row";
  for (const [which, text] of [["from", "Set as start"], ["to", "Set as end"]]) {
    const b = document.createElement("button"); b.type = "button"; b.textContent = text;
    b.onclick = () => setStop(which, point, label); row.append(b);
  }
  return row;
}

// ---------- search ----------
let searchTimer;
$("q").oninput = () => {
  clearTimeout(searchTimer);
  const q = $("q").value.trim();
  if (q.length < 2 || !state.client) { $("results").textContent = ""; return; }
  searchTimer = setTimeout(async () => {
    const near = state.map ? state.map.getCenter() : EPE;
    let r; try { r = await call(`places.autocomplete "${q}"`, () => state.client.places.autocomplete(q, { near, limit: 6 })); } catch { return; }
    $("results").textContent = "";
    if (!r.suggestions.length) {
      try {
        const g = await call(`geocode "${q}"`, () => state.client.geocode(q, { near, limit: 5 }));
        g.results.forEach((x) => addResult(x.label, x.kind, () => showPoint(x.point, x.label)));
      } catch {}
      return;
    }
    r.suggestions.forEach((s) => addResult(s.name, s.secondary || s.kind, () => openPlace(s.place_id, s.point, s.name)));
  }, 250);
};
function addResult(title, sub, onPick) {
  const li = document.createElement("li"); const b = document.createElement("button"); b.type = "button";
  b.innerHTML = `${title}<span>${sub ?? ""}</span>`; b.onclick = onPick; li.append(b); $("results").append(li);
}
function showPoint(point, label) {
  if (!needMap()) return;
  pin(point, Rana.MarkerContent.pin()); state.map.flyTo({ center: point, zoom: 16 });
  const c = $("placeCard"); c.hidden = false; c.innerHTML = `<b>${label}</b><span class="muted">${point.lat.toFixed(5)}, ${point.lng.toFixed(5)}</span>`;
  c.append(stopButtons(point, label));
}
async function openPlace(id, point, name) {
  if (!needMap()) return;
  showPoint(point, name);
  try {
    const d = await call("places.details", () => state.client.places.details(id));
    const c = $("placeCard");
    if (d.source === "osm") { // OpenStreetMap POI, stop or street (API 1.1.0-beta): no gates or photos.
      const a = d.address ?? {};
      c.innerHTML = `<b>${d.name}</b><span class="muted">${d.osm.kind}${a.street ? " · " + (a.housenumber ? a.housenumber + " " : "") + a.street : ""}</span>` +
        (d.openingHours ? `<span>${d.openingHours}</span>` : "") + `<span class="muted">${d.attribution}</span>`;
      c.append(stopButtons({ lat: d.lat, lng: d.lng }, d.name));
      return;
    }
    c.innerHTML = `<b>${d.name}</b><span class="muted">${d.kind}${d.street ? " · " + (d.house_number ? d.house_number + " " : "") + d.street : ""}</span>` +
      (d.how_to_find ? `<span>${d.how_to_find}</span>` : "") + (d.gates.length ? `<span class="muted">${d.gates.length} gate(s): ${d.gates.map((g) => `${g.name} (${g.status})`).join(", ")}</span>` : "");
    c.append(stopButtons(d.point, d.name));
  } catch {}
}

// ---------- map click: reverse geocode ----------
async function onMapClick(p) {
  const point = { lat: p.lat, lng: p.lng };
  state.click?.remove(); state.click = state.map.addMarker(point, Rana.MarkerContent.pin());
  const c = $("clickCard"); c.hidden = false; c.innerHTML = `<b>Looking up…</b>`;
  let label = `${point.lat.toFixed(5)}, ${point.lng.toFixed(5)}`;
  try {
    const a = await call("reverseGeocode", () => state.client.reverseGeocode(point));
    label = a.label || a.formatted || [a.house_number, a.street, a.area ?? a.locality].filter(Boolean).join(" ") || label;
    c.innerHTML = `<b>${label}</b><span class="muted">${point.lat.toFixed(5)}, ${point.lng.toFixed(5)}</span>`;
  } catch (e) { c.innerHTML = `<b>${label}</b><span class="muted">${e.code}: ${e.message}</span>`; }
  c.append(stopButtons(point, label));
}

// ---------- directions ----------
const MODES = [["okada", "Okada"], ["car", "Car"], ["keke", "Keke"], ["bicycle", "Bicycle"], ["walk", "Walk"]];
function chips(el, list, current, onPick) {
  el.textContent = "";
  list.forEach(([k, name]) => { const b = document.createElement("button"); b.type = "button"; b.textContent = name; b.setAttribute("aria-pressed", String(k === current)); b.onclick = () => { onPick(k); chips(el, list, k, onPick); }; el.append(b); });
}
chips($("modes"), MODES, state.mode, (k) => { state.mode = k; });
$("go").onclick = async () => {
  if (!needMap()) return;
  if (!state.from || !state.to) { $("routeOut").textContent = "Pick a start and an end first."; return; }
  state.lines.forEach((l) => l.remove()); state.lines = [];
  try {
    const r = await call(`directions (${state.mode})`, () => state.client.directions({ origin: state.from, destination: state.to, mode: state.mode, alternatives: true }));
    const [best, ...alts] = r.routes;
    alts.forEach((a) => state.lines.push(state.map.showRoute(a.geometry, { color: "#9E9484", width: 4, preset: "alternative" })));
    state.lines.push(state.map.showRoute(best.geometry, { mode: state.mode, stops: true }));
    if (!state.map.addPolyline) { pin(state.from, Rana.MarkerContent.labelledPin("A"), { color: "#161412" }); pin(state.to, Rana.MarkerContent.labelledPin("B"), { color: "#161412" }); }
    state.map.fitPoints([state.from, state.to], 60);
    $("routeOut").className = "";
    $("routeOut").textContent = `${fmtKm(best.distance_m)} · ${fmtMin(best.duration_s)} by ${state.mode}` + (alts.length ? ` · ${alts.length} other way(s)` : "");
  } catch (e) { $("routeOut").textContent = `${e.code}: ${e.message}`; }
};
$("matrix").onclick = async () => {
  if (!state.client) return;
  const c = state.map ? state.map.getCenter() : EPE;
  const o = [c, { lat: c.lat + 0.01, lng: c.lng }], d = [{ lat: c.lat, lng: c.lng + 0.012 }, { lat: c.lat - 0.008, lng: c.lng - 0.006 }];
  try {
    const r = await call("matrix 2x2", () => state.client.matrix({ origins: o, destinations: d, mode: state.mode }));
    $("routeOut").className = "";
    $("routeOut").textContent = "Matrix: " + r.rows.map((row, i) => `from ${i + 1}: ` + row.cells.map((x) => x.duration_s == null ? "none" : fmtMin(x.duration_s)).join(" / ")).join(" · ");
  } catch (e) { $("routeOut").textContent = `${e.code}: ${e.message}`; }
};

// ---------- nearby and snap ----------
const KINDS = [["health", "Health"], ["fuel", "Fuel"], ["bank", "Bank"], ["food", "Food"], ["market", "Market"]];
chips($("kinds"), KINDS, null, async (k) => {
  if (!needMap()) return;
  const c = state.map.getCenter();
  try {
    const r = await call(`places.nearby ${k}`, () => state.client.places.nearby({ lat: c.lat, lng: c.lng, radius_m: 2000, kind: k, limit: 20 }));
    r.results.forEach((x) => pin(x.point, Rana.MarkerContent.badge(x.name), { accessibilityLabel: x.name }));
    $("routeOut").className = "";
    $("routeOut").textContent = r.results.length ? `${r.results.length} ${k} place(s) within 2 km.` : `No ${k} within 2 km of the map centre.`;
    if (r.results.length) state.map.fitPoints(r.results.map((x) => x.point), 60);
  } catch {}
});
$("snap").onclick = async () => {
  if (!needMap()) return;
  const c = state.map.getCenter();
  const raw = Array.from({ length: 8 }, (_, i) => ({ lat: c.lat + i * 0.0007 + (i % 2 ? 0.00025 : -0.00025), lng: c.lng + i * 0.0006 + (i % 3 ? 0.0002 : -0.0002) }));
  state.lines.push(state.map.showRoute(raw, { color: "#B9B09C", width: 3 }));
  try {
    const r = await call("snapToRoads", () => state.client.snapToRoads({ points: raw, mode: "car", interpolate: true }));
    state.lines.push(state.map.showRoute(r.geometry, { mode: "car" }));
    $("routeOut").className = ""; $("routeOut").textContent = `Snapped ${r.points.length} points, ${fmtKm(r.distance_m)} of road.`;
  } catch (e) { $("routeOut").textContent = `${e.code}: ${e.message}`; }
};

// ---------- Rana Kit features (switch on when the SDK has them) ----------
function refreshKit() {
  let missing = 0;
  document.querySelectorAll("[data-needs]").forEach((b) => { const ok = !!state.map && typeof state.map[b.dataset.needs] === "function"; b.disabled = !ok; if (!ok) missing++; });
  $("kitState").textContent = missing ? `${missing} of 4 need the next web SDK release (in progress).` : "All Rana Kit features are available.";
}
refreshKit();
$("kitVehicle").onclick = () => {
  const c = state.map.getCenter(); let i = 0;
  const v = state.map.addVehicle(c, Rana.VehicleAppearance.kit("okada"), { heading: 45 }); state.kit.push(v);
  const t = setInterval(() => { i++; v.update({ lat: c.lat + i * 0.0004, lng: c.lng + i * 0.0004 }, 45, 900); if (i > 12) clearInterval(t); }, 1000);
};
$("kitPoints").onclick = () => {
  const c = state.map.getCenter();
  const pts = Array.from({ length: 300 }, () => ({ lat: c.lat + (Math.random() - 0.5) * 0.05, lng: c.lng + (Math.random() - 0.5) * 0.05 }));
  state.kit.push(state.map.addPoints(pts, { cluster: true }));
};
$("kitAvoid").onclick = () => {
  const c = state.map.getCenter(), d = 0.004;
  state.kit.push(state.map.addPolygon([[{ lat: c.lat - d, lng: c.lng - d }, { lat: c.lat - d, lng: c.lng + d }, { lat: c.lat + d, lng: c.lng + d }, { lat: c.lat + d, lng: c.lng - d }]], { style: "avoid" }));
};
$("kitRadius").onclick = () => { state.kit.push(state.map.addCircle(state.map.getCenter(), 500, { label: "500 m" })); };

// ---------- map style ----------
chips($("styles"), [["day", "Day"], ["night", "Night"]], "day", (s) => { if (state.map) state.map.setStyle(s); });
