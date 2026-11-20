import type { LatLng } from "@ranamaps/maps-react-native";

const EARTH = 6371008.8;
const rad = (d: number) => (d * Math.PI) / 180;
const deg = (r: number) => (r * 180) / Math.PI;
const M_PER_DEG = (Math.PI / 180) * EARTH;

export function distance(a: LatLng, b: LatLng) {
  const dLat = rad(b.latitude - a.latitude);
  const dLng = rad(b.longitude - a.longitude);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a.latitude)) *
      Math.cos(rad(b.latitude)) *
      Math.sin(dLng / 2) ** 2;
  return 2 * EARTH * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Initial bearing in degrees clockwise from true north, 0..360. */
export function bearing(a: LatLng, b: LatLng) {
  const dLng = rad(b.longitude - a.longitude);
  const y = Math.sin(dLng) * Math.cos(rad(b.latitude));
  const x =
    Math.cos(rad(a.latitude)) * Math.sin(rad(b.latitude)) -
    Math.sin(rad(a.latitude)) * Math.cos(rad(b.latitude)) * Math.cos(dLng);
  return (deg(Math.atan2(y, x)) + 360) % 360;
}

export function offset(p: LatLng, northM: number, eastM: number): LatLng {
  return {
    latitude: p.latitude + northM / M_PER_DEG,
    longitude: p.longitude + eastM / (M_PER_DEG * Math.cos(rad(p.latitude))),
  };
}

export interface PathIndex {
  points: ReadonlyArray<LatLng>;
  cumulative: number[];
  total: number;
}

export function indexPath(points: ReadonlyArray<LatLng>): PathIndex {
  const cumulative = [0];
  for (let i = 1; i < points.length; i++)
    cumulative.push(cumulative[i - 1] + distance(points[i - 1], points[i]));
  return { points, cumulative, total: cumulative[cumulative.length - 1] };
}

/** Point and travel course `metres` along the path (clamped to its ends). */
export function pointAt(path: PathIndex, metres: number) {
  const d = Math.max(0, Math.min(path.total, metres));
  let i = 1;
  while (i < path.points.length - 1 && path.cumulative[i] < d) i++;
  const a = path.points[i - 1];
  const b = path.points[i];
  const len = path.cumulative[i] - path.cumulative[i - 1] || 1;
  const t = (d - path.cumulative[i - 1]) / len;
  return {
    point: {
      latitude: a.latitude + (b.latitude - a.latitude) * t,
      longitude: a.longitude + (b.longitude - a.longitude) * t,
    },
    course: bearing(a, b),
  };
}

/** Distance along the path of the point nearest to `p`. */
export function progressOf(path: PathIndex, p: LatLng) {
  const kx = M_PER_DEG * Math.cos(rad(p.latitude));
  const local = (q: LatLng) => ({
    x: (q.longitude - p.longitude) * kx,
    y: (q.latitude - p.latitude) * M_PER_DEG,
  });
  let best = Infinity;
  let progress = 0;
  for (let i = 1; i < path.points.length; i++) {
    const a = local(path.points[i - 1]);
    const b = local(path.points[i]);
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const len2 = dx * dx + dy * dy || 1;
    const t = Math.max(0, Math.min(1, -(a.x * dx + a.y * dy) / len2));
    const dist = Math.hypot(a.x + dx * t, a.y + dy * t);
    if (dist < best) {
      best = dist;
      progress =
        path.cumulative[i - 1] +
        t * (path.cumulative[i] - path.cumulative[i - 1]);
    }
  }
  return progress;
}

export function formatDistance(m: number) {
  return m < 1000
    ? `${Math.round(m / 10) * 10} m`
    : `${(m / 1000).toFixed(1)} km`;
}

export function formatDuration(s: number) {
  const min = Math.max(1, Math.round(s / 60));
  return min < 60 ? `${min} min` : `${Math.floor(min / 60)} h ${min % 60} min`;
}
