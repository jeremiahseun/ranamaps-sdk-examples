import { Rana, DirectionsReroutingProvider, JourneyTraceRecorder } from '../node_modules/@ranamaps/maps-js/dist/index.js';
import { pickup, destinations, preview, advance, pointAt, headingAt } from './journey.js';
const $ = id => /** @type {HTMLElement & { value: string, disabled: boolean }} */ (/** @type {unknown} */ (document.getElementById(id)));
/** @type {import('../node_modules/@ranamaps/maps-js/dist/index.js').RanaMap | undefined} */
let map;
/** @type {import('../node_modules/@ranamaps/maps-js/dist/index.js').JourneyTraceRecorder | undefined} */
let trace;
function configureTrace() {
  map?.setJourneyTraceRecorder(null); trace = undefined;
  if (map && state && /** @type {HTMLInputElement} */ (/** @type {unknown} */ ($('trace-preview'))).checked) {
    trace = new JourneyTraceRecorder(new Rana.RanaClient($('key').value.trim()), { consent: true, source: 'simulated', mode: state.mode }, status => { $('trace-status').textContent = `Simulated trace: ${status.buffered} buffered · ${status.uploaded} learned${status.error ? ` · ${status.error.code}` : ''}`; });
    map.setJourneyTraceRecorder(trace);
  } else $('trace-status').textContent = 'Trace preview: off';
  $('trace-flush').disabled = !trace;
}
$('trace-preview').onchange = configureTrace;
$('trace-flush').onclick = async () => { try { if ((trace?.status.buffered ?? 0) < 2) return message('Start simulation to collect at least two fixes.'); await trace?.flush(); message('Trace batch validated. Simulated fixes are never learned.'); } catch (error) { message(error.message); } };
let smooth = true, phoneHeading = 0, routeAware = true, detour = false, automaticRerouting = false;
let state, route, endMarker, timer, generation = 0, night = false, tilted = false, right = false, layers = [];
const replay = { callback: null, start(onLocation) { this.callback = onLocation; }, stop() { this.callback = null; }, timestamp: 0, emit(point, heading = 0) { this.timestamp = Math.max(Date.now(), this.timestamp + 1); this.callback?.({ point, accuracyMetres: 8, heading, timestampMs: this.timestamp }); } };
function refreshReroutingStatus() {
  const value = map?.reroutingStatus ?? { state: 'disabled', requestsMade: 0 };
  $('rerouting-status').textContent = `Automatic rerouting: ${value.state} · ${value.requestsMade} requests`;
  if (value.error) message(`${value.error.code}: ${value.error.message}`);
}
function acceptedReroute(result) {
  if (!state) return;
  generation++; detour = false; $('detour').textContent = 'Simulate GPS detour';
  state = { ...state, path: [...result.path], progress: 0, live: true };
  draw(false); message('Automatic reroute loaded. Movement remains simulated.');
}
function mapEvents() { return { onLocate: () => { emitPosition(); map?.setTracking("follow-heading"); }, onError: error => message(error.message), onMarkerDrag: (_, point, phase) => { if (phase === 'ended') select({ name: 'Dropped pin', point }); }, onReroutingChanged: refreshReroutingStatus, onRerouted: acceptedReroute }; }
function configureRerouting() {
  if (map && state && routeAware && automaticRerouting) map.setAutomaticRerouting({ destination: state.destination.point, mode: state.mode }, new DirectionsReroutingProvider(new Rana.RanaClient($('key').value.trim())));
  else map?.setAutomaticRerouting(null);
  refreshReroutingStatus();
}
function configureMotion() {
  map?.applySettings({ location: { mode: 'puck', motion: smooth ? 'smooth' : 'direct', activity: $('mode').value === 'walk' ? 'walking' : 'vehicle' }, attribution: { corner: right ? 'bottom-right' : 'bottom-left' }, events: mapEvents() });
  padding();
}
function emitPosition() {
  const point = pointAt(state?.path ?? [], state?.progress ?? 0);
  const heading = headingAt(state?.path ?? [], state?.progress ?? 0), radians = heading * Math.PI / 180;
  replay.emit(detour ? { lat: point.lat - Math.sin(radians) * .0008, lng: point.lng + Math.cos(radians) * .0008 / Math.cos(point.lat * Math.PI / 180) } : point, heading);
  if ($('mode').value === 'walk') map?.updateDeviceHeading({ heading: phoneHeading, accuracyDegrees: 5 });
  $('heading-mode').textContent = $('mode').value === 'walk' ? `Walking compass · sample phone ${phoneHeading}°` : `Vehicle course · ${smooth ? 'smooth' : 'direct'} movement`;
  $('phone').hidden = $('mode').value !== 'walk';
  const routeState = map?.locationRouteStatus.state ?? 'none';
  $('route-status').textContent = `Route match: ${{ matched: 'Matched', 'off-route': 'Off route', uncertain: 'Uncertain', none: 'None' }[routeState]}`;
}
function message(text) { $('status').textContent = text; }
function padding() {
  if (!map) return;
  const rect = $('map').getBoundingClientRect(), panel = $('sheet').getBoundingClientRect();
  map.setPadding({ top: Math.max(0, $('header').getBoundingClientRect().bottom - rect.top + 12), bottom: Math.max(0, rect.bottom - panel.top) });
}
function fit() { if (state) map?.fitPoints(state.path, 36); }
function pause() { clearInterval(timer); timer = undefined; if (state?.phase === 'running') state = { ...state, phase: 'paused' }; render(); }
function render() {
  $('title').textContent = state ? `${state.destination.name} · ${state.phase}` : 'Where are we going?';
  $('play').disabled = $('live').disabled = $('progress').disabled = !state;
  $('play').textContent = state?.phase === 'running' ? 'Pause' : state?.phase === 'arrived' ? 'Replay simulation' : 'Start simulation';
  $('progress').value = String((state?.progress ?? 0) * 100);
  $('detour').disabled = !state;
  $('auto-reroute').disabled = !state || !routeAware;
}
function position(value) {
  if (!state) return;
  state = advance(state, value);
  route?.setProgress(state.progress); emitPosition();
  if (state.phase === 'arrived') { clearInterval(timer); timer = undefined; }
  render();
}
function configureRoute() { map?.setLocationRoute(routeAware && state ? state.path : null); configureRerouting(); }
function draw(installMovement = true) {
  if (installMovement) configureRoute();
  route?.remove(); endMarker?.remove();
  if (!state) return;
  route = map.addPolyline(state.path, { preset: state.mode, arrows: true, progress: state.progress });
  endMarker = map.addMarker(state.destination.point, Rana.MarkerContent.pin('flag'), { accessibilityLabel: state.destination.name, draggable: true });
  position(state.progress); if (installMovement) fit();
}
function select(destination) {
  if (!map) return message('Connect the map first.');
  pause(); generation++; $('live').textContent = 'Use live directions';
  state = preview(destination, $('mode').value); configureTrace(); draw(); render();
  message('Illustrative route · replayed location. Live directions are optional.');
}
$('connect').onsubmit = event => {
  event.preventDefault();
  try {
    map = new Rana.Map({ key: $('key').value.trim(), container: 'map', center: pickup, zoom: 12, settings: { location: { mode: 'puck', motion: 'smooth', activity: 'vehicle' }, events: mapEvents() } });
    map.setLocationProvider(replay);
    map.on('load', () => {
      const label = document.createElement('button'); label.className = 'pickup'; label.textContent = 'Your pickup'; label.onclick = () => message('Fixture pickup in Lagos.');
      map.addMarker(pickup, Rana.MarkerContent.view(label, 'bottom')); replay.emit(pickup); padding();
      if (!state) message('Choose Ikeja or Marina, or tap the map to drop a pin.');
    });
    map.on('click', point => select({ name: 'Dropped pin', point }));
    $('connect').hidden = true; padding();
  } catch (error) { message(error.message); }
};
$('key').value = new URLSearchParams(location.search).get('key') ?? '';
$('destinations').onclick = event => { const index = /** @type {HTMLElement} */ (event.target).dataset.destination; if (index !== undefined) select(destinations[Number(index)]); };
$('mode').onchange = () => { configureMotion(); if (state) select(state.destination); emitPosition(); };
$('auto-reroute').onchange = () => { automaticRerouting = /** @type {HTMLInputElement} */ (/** @type {unknown} */ ($('auto-reroute'))).checked; configureRerouting(); };
$('route-aware').onchange = () => { routeAware = /** @type {HTMLInputElement} */ (/** @type {unknown} */ ($('route-aware'))).checked; configureRoute(); emitPosition(); render(); };
$('detour').onclick = () => { detour = !detour; $('detour').textContent = detour ? 'Rejoin route' : 'Simulate GPS detour'; emitPosition(); };
$('motion').onchange = () => { smooth = /** @type {HTMLInputElement} */ (/** @type {unknown} */ ($('motion'))).checked; configureMotion(); emitPosition(); };
$('phone').onclick = () => { phoneHeading = (phoneHeading + 45) % 360; map?.updateDeviceHeading({ heading: phoneHeading, accuracyDegrees: 5 }); $('heading-mode').textContent = `Walking compass · sample phone ${phoneHeading}°`; };
$('progress').oninput = event => { const value = Number(/** @type {HTMLInputElement} */ (event.target).value) / 100; pause(); position(value); };
$('play').onclick = () => {
  if (!state) return;
  if (state.phase === 'running') return pause();
  if (state.progress >= 1) position(0);
  state = { ...state, phase: 'running' }; map.setTracking('follow-heading');
  timer = setInterval(() => position(state.progress + .01), 600); render();
};
$('reset').onclick = () => { map?.setJourneyTraceRecorder(null); trace = undefined; $('trace-flush').disabled = true; $('trace-status').textContent = 'Trace preview: off'; /** @type {HTMLInputElement} */ (/** @type {unknown} */ ($('trace-preview'))).checked = false; automaticRerouting = false; /** @type {HTMLInputElement} */ (/** @type {unknown} */ ($('auto-reroute'))).checked = false; detour = false; $('detour').textContent = 'Simulate GPS detour'; pause(); generation++; route?.remove(); endMarker?.remove(); state = undefined; configureRoute(); map?.setTracking('none'); emitPosition(); map?.setCamera({ center: pickup, zoom: 12 }); render(); message('Reset. Choose a destination.'); };
$('fit').onclick = fit;
$('recenter').onclick = () => { if (map) { emitPosition(); map.setTracking('follow-heading'); } };
$('night').onclick = () => { night = !night; map?.setStyle(night ? 'night' : 'day'); $('night').textContent = night ? 'Day' : 'Night'; };
$('tilt').onclick = () => { tilted = !tilted; map?.setCamera({ pitch: tilted ? 45 : 0 }); $('tilt').textContent = tilted ? '2D' : '3D'; };
$('credit').onclick = () => { right = !right; map?.setAttribution({ corner: right ? 'bottom-right' : 'bottom-left' }); $('credit').textContent = right ? 'Credit on left' : 'Credit on right'; };
$('live').onclick = async () => {
  if (!state) return;
  pause(); const request = ++generation, current = state; $('live').disabled = true; $('live').textContent = 'Requesting…';
  try {
    const result = await new Rana.RanaClient($('key').value.trim()).directions({ origin: pickup, destination: current.destination.point, mode: current.mode, geometry: 'geojson' });
    if (request !== generation) return;
    const geometry = result.routes[0]?.geometry;
    if (!geometry || typeof geometry === 'string' || geometry.coordinates.length < 2) throw new Error('No usable route returned.');
    state = { ...current, phase: 'preview', progress: 0, live: true, path: geometry.coordinates.map(([lng, lat]) => ({ lat, lng })) }; draw();
    message('Live directions · movement remains simulated.');
  } catch (error) { if (request === generation) message(error.message); }
  finally { if (request === generation) { $('live').textContent = 'Use live directions'; render(); } }
};
$('layers').onclick = () => {
  if (!map) return;
  if (layers.length) { layers.reverse().forEach(layer => layer.remove()); layers = []; $('layers').textContent = 'Show demo layers'; return; }
  layers.push(map.addPoints(destinations.map(d => d.point), { cluster: true }), map.addCircle(pickup, 400, { label: '400 m' }));
  const source = map.addGeoJsonSource('demo-places', { type: 'FeatureCollection', features: destinations.map(d => ({ type: 'Feature', properties: { name: d.name }, geometry: { type: 'Point', coordinates: [d.point.lng, d.point.lat] } })) });
  layers.push(source, map.addLayer('demo-place-labels', 'demo-places', { kind: 'symbol', text: { get: 'name' }, textSize: 14, color: '#305c35' }));
  $('layers').textContent = 'Hide demo layers';
};
function height(value) { const maximum = Math.max(240, Math.min(600, innerHeight - 190)); const next = Math.max(240, Math.min(maximum, value)); $('sheet').style.height = `${next}px`; $('handle').setAttribute('aria-valuemax', String(maximum)); $('handle').setAttribute('aria-valuenow', String(Math.round(next))); padding(); }
let drag;
$('handle').onpointerdown = event => { drag = { y: event.clientY, height: $('sheet').getBoundingClientRect().height }; $('handle').setPointerCapture(event.pointerId); };
$('handle').onpointermove = event => { if (drag) height(drag.height + drag.y - event.clientY); };
$('handle').onpointerup = $('handle').onpointercancel = () => { drag = undefined; fit(); };
$('handle').onkeydown = event => { if (['ArrowUp', 'ArrowDown', 'Home', 'End'].includes(event.key)) { event.preventDefault(); height(event.key === 'Home' ? 240 : event.key === 'End' ? 600 : $('sheet').offsetHeight + (event.key === 'ArrowUp' ? 32 : -32)); fit(); } };
$('size').onclick = () => { const expanded = $('sheet').offsetHeight > 360; height(expanded ? 260 : 560); $('size').textContent = expanded ? 'Expand' : 'Collapse'; fit(); };
const observer = new ResizeObserver(padding); observer.observe($('sheet')); observer.observe($('header')); observer.observe($('map'));
document.addEventListener('visibilitychange', () => { if (document.hidden) pause(); });
window.addEventListener('pagehide', event => { pause(); generation++; if (!event.persisted) { observer.disconnect(); map?.remove(); } });
