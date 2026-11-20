import type { LatLng } from "@ranamaps/maps-react-native";
import { offset, pointAt, type PathIndex } from "./geo";

/** JSON payload sent by the simulated tracking backend. */
export interface LocationMessage {
  type: "location";
  seq: number;
  latitude: number;
  longitude: number;
  /** Metres per second. */
  speed: number;
  /** Travel course, degrees clockwise from true north. */
  course: number;
  accuracy: number;
  /** Epoch milliseconds. */
  timestamp: number;
}

export interface FakeSocketOptions {
  speedMps: number;
  intervalMs?: number;
  noiseMetres?: number;
}

/**
 * Minimal WebSocket look-alike. It walks `path` at a fixed speed and emits one
 * JSON string per interval with +/- `noiseMetres` of position noise. Simulated
 * packet loss (`dropNext`) still advances the traveller; the message is lost.
 */
export class FakeLocationSocket {
  onopen: (() => void) | null = null;
  onmessage: ((event: { data: string }) => void) | null = null;
  onclose: (() => void) | null = null;
  readyState: 0 | 1 | 3 = 0;
  private timer?: ReturnType<typeof setInterval>;
  private travelled = 0;
  private seq = 0;
  private dropped = 0;
  private last = Date.now();
  private intervalMs: number;
  private readonly noise: number;

  constructor(
    private readonly path: PathIndex,
    private readonly options: FakeSocketOptions,
  ) {
    this.intervalMs = options.intervalMs ?? 5000;
    this.noise = options.noiseMetres ?? 3;
  }

  open() {
    this.readyState = 1;
    this.last = Date.now();
    this.onopen?.();
    this.tick(0);
    this.schedule();
  }

  close() {
    if (this.readyState === 3) return;
    this.readyState = 3;
    clearInterval(this.timer);
    this.onclose?.();
  }

  dropNext(count: number) {
    this.dropped += count;
  }

  setIntervalMs(ms: number) {
    this.intervalMs = ms;
    if (this.readyState === 1) this.schedule();
  }

  private schedule() {
    clearInterval(this.timer);
    this.timer = setInterval(() => {
      const now = Date.now();
      const dt = (now - this.last) / 1000;
      this.last = now;
      this.tick(dt);
    }, this.intervalMs);
  }

  private tick(dtSeconds: number) {
    this.travelled += this.options.speedMps * dtSeconds;
    const finished = this.travelled >= this.path.total;
    const truth = pointAt(this.path, this.travelled);
    this.seq++;
    if (this.dropped > 0 && !finished) {
      this.dropped--;
      return;
    }
    const jitter = () => (Math.random() * 2 - 1) * this.noise;
    const point: LatLng = offset(truth.point, jitter(), jitter());
    const message: LocationMessage = {
      type: "location",
      seq: this.seq,
      latitude: point.latitude,
      longitude: point.longitude,
      speed: Math.max(
        0,
        this.options.speedMps * (1 + (Math.random() - 0.5) * 0.1),
      ),
      course: truth.course,
      accuracy: 5,
      timestamp: Date.now(),
    };
    this.onmessage?.({ data: JSON.stringify(message) });
    if (finished) this.close();
  }
}
