import type {
  LatLng,
  LocationRouteStatus,
  Mode,
  RanaMapController,
  Route,
} from "@ranamaps/maps-react-native";
import { FakeLocationSocket, type LocationMessage } from "./fakeSocket";
import { indexPath, offset, progressOf, type PathIndex } from "./geo";

export type Movement = "simulated" | "device";
export type TravelMode = Extract<Mode, "car" | "okada" | "walk">;

export const MODES: Record<
  TravelMode,
  { label: string; speedMps: number; activity: "vehicle" | "walking" }
> = {
  car: { label: "Car", speedMps: 11, activity: "vehicle" },
  okada: { label: "Okada", speedMps: 8, activity: "vehicle" },
  walk: { label: "Walk", speedMps: 1.4, activity: "walking" },
};

export interface NavProgress {
  seq: number;
  remainingM: number;
  etaS: number;
  next?: { text: string; distanceM: number };
  routeStatus?: LocationRouteStatus;
}

interface Maneuver {
  text: string;
  progressM: number;
}

/**
 * Turn-by-turn session. "simulated": a fake websocket walks the route and each
 * JSON message is parsed and fed to the SDK. "device": the native provider
 * drives the puck and the host forwards its own fixes through `deviceFix` for
 * progress only. The SDK's follow camera handles the camera, so no `setCamera`
 * calls are made while navigating.
 */
export class NavigationSession {
  private socket?: FakeLocationSocket;
  private readonly index: PathIndex;
  private readonly maneuvers: Maneuver[];
  private readonly wrongPath: LatLng[];
  private stopped = false;
  private latest?: NavProgress;
  private offStatus?: () => void;

  constructor(
    private readonly map: RanaMapController,
    private readonly path: LatLng[],
    route: Route,
    private readonly mode: TravelMode,
    readonly movement: Movement,
    private readonly handlers: {
      onProgress: (progress: NavProgress) => void;
      onArrived: () => void;
      onError: (error: unknown) => void;
    },
    private intervalMs = 5000,
  ) {
    this.index = indexPath(path);
    this.durationS = route.durationS;
    this.maneuvers = route.legs
      .flatMap((leg) => leg.steps)
      .map((step) => ({
        text: step.instruction,
        progressM: progressOf(this.index, step.location),
      }))
      .filter((m) => m.text);
    // A plausible but different line ~150 m away, used by the "Wrong route" scenario.
    this.wrongPath = path.map((p) => offset(p, 150, 90));
  }

  private readonly durationS: number;

  async start() {
    await this.map.setLocationRoute(this.path);
    this.offStatus = this.map.onLocationRouteChanged((routeStatus) => {
      if (this.latest) this.emit({ ...this.latest, routeStatus });
    });
    if (this.movement === "device") return;
    const socket = new FakeLocationSocket(this.index, {
      speedMps: MODES[this.mode].speedMps,
      intervalMs: this.intervalMs,
      noiseMetres: 3,
    });
    socket.onmessage = (event) => this.receive(event.data);
    socket.onclose = () => {
      if (!this.stopped) {
        this.stop();
        this.handlers.onArrived();
      }
    };
    this.socket = socket;
    socket.open();
  }

  stop() {
    this.stopped = true;
    this.socket?.close();
    this.offStatus?.();
    this.offStatus = undefined;
  }

  dropNext(count: number) {
    this.socket?.dropNext(count);
  }

  setIntervalMs(ms: number) {
    this.intervalMs = ms;
    this.socket?.setIntervalMs(ms);
  }

  setWrongRoute(on: boolean) {
    return this.map.setLocationRoute(on ? this.wrongPath : this.path);
  }

  /** Device mode: advance progress from a real fix (the SDK already has it). */
  deviceFix(point: LatLng) {
    if (this.stopped || this.movement !== "device") return;
    const remainingM = this.advance(point, (this.latest?.seq ?? 0) + 1);
    if (remainingM < 20) {
      this.stop();
      this.handlers.onArrived();
    }
  }

  private receive(raw: string) {
    if (this.stopped) return;
    try {
      const m = JSON.parse(raw) as LocationMessage;
      if (m.type !== "location") return;
      const point = { latitude: m.latitude, longitude: m.longitude };
      void this.map
        .updateLocation({
          point,
          accuracyMetres: m.accuracy,
          heading: m.course,
          courseAccuracyDegrees: 10,
          speedMetresPerSecond: m.speed,
          timestampMs: m.timestamp,
        })
        .catch(this.handlers.onError);
      if (MODES[this.mode].activity === "walking") {
        // Walking takes its direction from the compass stream, not travel course.
        void this.map
          .updateDeviceHeading({
            heading: m.course,
            accuracyDegrees: 15,
            timestampMs: m.timestamp,
          })
          .catch(this.handlers.onError);
      }
      this.advance(point, m.seq);
    } catch (error) {
      this.handlers.onError(error);
    }
  }

  /** Emits progress for `point`; returns the metres left on the route. */
  private advance(point: LatLng, seq: number) {
    const progress = progressOf(this.index, point);
    const remainingM = Math.max(0, this.index.total - progress);
    const upcoming = this.maneuvers.find((x) => x.progressM > progress + 5);
    this.emit({
      seq,
      remainingM,
      etaS: this.durationS * (remainingM / (this.index.total || 1)),
      next: upcoming && {
        text: upcoming.text,
        distanceM: upcoming.progressM - progress,
      },
      routeStatus: this.latest?.routeStatus,
    });
    return remainingM;
  }

  private emit(progress: NavProgress) {
    this.latest = progress;
    this.handlers.onProgress(progress);
  }
}
