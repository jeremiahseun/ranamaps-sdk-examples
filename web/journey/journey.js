export const pickup = { lat: 6.5095, lng: 3.3711 };
export const destinations = [{ name: 'Ikeja', point: { lat: 6.6018, lng: 3.3515 } }, { name: 'Marina', point: { lat: 6.45, lng: 3.39 } }, { name: 'Corner demo', point: { lat: 6.5125, lng: 3.3726 } }];
export function preview(destination, mode = 'car') {
  return { phase: 'preview', destination, mode, progress: 0, live: false, path: destination.name === 'Corner demo' ? [pickup, { lat: 6.511, lng: 3.3711 }, { lat: 6.511, lng: 3.3726 }, destination.point] : [pickup, { lat: (pickup.lat + destination.point.lat) / 2, lng: (pickup.lng + destination.point.lng) / 2 + .003 }, destination.point] };
}
export function advance(state, progress) {
  const value = Math.max(0, Math.min(1, progress));
  return { ...state, progress: value, phase: value === 1 ? 'arrived' : state.phase === 'arrived' ? 'paused' : state.phase };
}
export function pointAt(path, progress) {
  if (!path.length) return pickup;
  const lengths = path.slice(1).map((p, i) => Math.hypot(p.lat - path[i].lat, (p.lng - path[i].lng) * Math.cos((p.lat + path[i].lat) * Math.PI / 360)));
  let distance = lengths.reduce((a, b) => a + b, 0) * Math.max(0, Math.min(1, progress));
  for (let i = 0; i < lengths.length; i++) {
    if (lengths[i] > 0 && distance <= lengths[i]) { const t = distance / lengths[i]; return { lat: path[i].lat + (path[i + 1].lat - path[i].lat) * t, lng: path[i].lng + (path[i + 1].lng - path[i].lng) * t }; }
    distance -= lengths[i];
  }
  return path.at(-1);
}

export function headingAt(path, progress) {
  const a = pointAt(path, Math.max(0, progress - .001)), b = pointAt(path, Math.min(1, progress + .001));
  return (Math.atan2((b.lng - a.lng) * Math.cos((a.lat + b.lat) * Math.PI / 360), b.lat - a.lat) * 180 / Math.PI + 360) % 360;
}
