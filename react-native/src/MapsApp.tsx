import React, {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import {
  ActivityIndicator,
  Keyboard,
  Platform,
  Pressable,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  TextInput,
  View,
  useWindowDimensions,
} from "react-native";
import {
  MarkerContent,
  RanaMap,
  createClient,
  decodePolyline,
  type LatLng,
  type MapOptions,
  type PlaceSuggestion,
  type RanaClient,
  type RanaEvent,
  type RanaMapController,
  type RanaMarker,
  type RanaPolyline,
  type Route,
} from "@ranamaps/maps-react-native";
import { BottomSheet, type BottomSheetHandle } from "./BottomSheet";
import {
  LAGOS,
  requestLocationPermission,
} from "./deviceLocation";
import { formatDistance, formatDuration, indexPath } from "./geo";
import {
  MODES,
  NavigationSession,
  type Movement,
  type NavProgress,
  type TravelMode,
} from "./navigation";

const TOP = Platform.OS === "android" ? (StatusBar.currentHeight ?? 24) : 54;
const FIRST_FIX_ZOOM = 16.5;
/** Idle: location dot, no camera tracking; the first fix eases to the user. */
const MAP_OPTIONS: MapOptions = {
  center: LAGOS,
  zoom: 14,
  settings: {
    location: {
      tracking: "none",
      appearance: { kind: "dot" },
      motion: "smooth",
      activity: "generic",
      firstFixZoom: FIRST_FIX_ZOOM,
    },
  },
};

type Phase = "browse" | "place" | "route" | "navigating";
interface Place {
  name: string;
  address: string;
  point: LatLng;
}
interface Trip {
  route: Route;
  path: LatLng[];
}

export default function MapsApp() {
  const { height: windowHeight } = useWindowDimensions();
  const snaps = useMemo(
    () => [140, 310, Math.round(windowHeight * 0.7)] as const,
    [windowHeight],
  );

  const [phase, setPhase] = useState<Phase>("browse");
  const [query, setQuery] = useState("");
  const [suggestions, setSuggestions] = useState<PlaceSuggestion[]>([]);
  const [searching, setSearching] = useState(false);
  const [place, setPlace] = useState<Place | null>(null);
  const [mode, setMode] = useState<TravelMode>("car");
  const [trip, setTrip] = useState<Trip | null>(null);
  const [loadingRoute, setLoadingRoute] = useState(false);
  const [night, setNight] = useState(false);
  const [following, setFollowing] = useState(false);
  const [permission, setPermission] = useState<"pending" | "granted" | "denied">(
    "pending",
  );
  const [mapReady, setMapReady] = useState(false);
  const [hasOrigin, setHasOrigin] = useState(false);
  const [movement, setMovement] = useState<Movement>("simulated");
  const [progress, setProgress] = useState<NavProgress | null>(null);
  const [devOpen, setDevOpen] = useState(false);
  const [wrongRoute, setWrongRoute] = useState(false);
  const [intervalMs, setIntervalMs] = useState(5000);
  const [notice, setNotice] = useState<string | null>(null);

  const map = useRef<RanaMapController | null>(null);
  const client = useRef<RanaClient | null>(null);
  const marker = useRef<RanaMarker | null>(null);
  const line = useRef<RanaPolyline | null>(null);
  const session = useRef<NavigationSession | null>(null);
  const sheet = useRef<BottomSheetHandle>(null);
  const skipSearch = useRef(false);
  const nightRef = useRef(false);
  /** Latest real device fix (or Lagos when permission is denied). */
  const origin = useRef<LatLng | null>(null);

  const fail = useCallback((error: unknown) => {
    setNotice(error instanceof Error ? error.message : String(error));
  }, []);

  // --- Map padding: the sheet's visible height always becomes bottom padding.
  const padding = useRef({
    top: TOP + 72,
    bottom: snaps[0] as number,
    sent: null as object | null,
    busy: false,
  });
  const flushPadding = useCallback(async () => {
    const p = padding.current;
    if (p.busy) return;
    p.busy = true;
    try {
      // Coalesce: only the most recent value is sent while a call is in flight.
      while (map.current) {
        const want = { top: p.top, bottom: Math.round(p.bottom) };
        if (p.sent && JSON.stringify(p.sent) === JSON.stringify(want)) break;
        p.sent = want;
        await map.current.setPadding(want);
      }
    } catch (e) {
      fail(e);
    } finally {
      p.busy = false;
    }
  }, [fail]);
  const onSheetHeight = useCallback(
    (h: number) => {
      padding.current.bottom = h;
      void flushPadding();
    },
    [flushPadding],
  );
  useEffect(() => {
    padding.current.top = TOP + (phase === "navigating" ? 120 : 72);
    void flushPadding();
  }, [phase, flushPadding]);

  /** `update` re-applies the full settings, so repeat padding and style. */
  const applyLocation = useCallback(
    (location: NonNullable<NonNullable<MapOptions["settings"]>["location"]>) =>
      map.current?.update({
        style: { kind: nightRef.current ? "night" : "day" },
        settings: {
          padding: {
            top: padding.current.top,
            bottom: Math.round(padding.current.bottom),
          },
          location: {
            appearance: { kind: "puck" },
            motion: "smooth",
            firstFixZoom: FIRST_FIX_ZOOM,
            ...location,
          },
        },
      }),
    [],
  );

  const onReady = useCallback(
    async (controller: RanaMapController) => {
      try {
        map.current = controller;
        client.current = await createClient();
        void flushPadding();
        setMapReady(true);
      } catch (e) {
        fail(e);
      }
    },
    [fail, flushPadding],
  );

  // --- Location: ask for permission on launch, then track the device.
  const setOrigin = useCallback((point: LatLng) => {
    origin.current = point;
    setHasOrigin(true);
  }, []);
  useEffect(() => {
    let alive = true;
    (async () => {
      const granted = await requestLocationPermission();
      if (!alive) return;
      setPermission(granted ? "granted" : "denied");
      if (!granted) setOrigin(LAGOS);
    })().catch(fail);
    return () => {
      alive = false;
    };
  }, [setOrigin, fail]);

  // Idle: native provider shows the dot (or the Lagos fallback when denied).
  useEffect(() => {
    if (!mapReady || permission === "pending") return;
    const m = map.current;
    if (!m) return;
    const connected =
      permission === "granted"
        ? m.useNativeLocationProvider({ intervalMs: 1000 })
        : m.updateLocation({
            point: LAGOS,
            accuracyMetres: 5,
            timestampMs: Date.now(),
          });
    connected.catch(fail);
  }, [mapReady, permission, fail]);

  useEffect(
    () => () => {
      session.current?.stop();
      void client.current?.dispose();
    },
    [],
  );

  // --- Live, debounced search.
  useEffect(() => {
    if (skipSearch.current) {
      skipSearch.current = false;
      return;
    }
    const text = query.trim();
    if (text.length < 2) {
      setSuggestions([]);
      setSearching(false);
      return;
    }
    const abort = new AbortController();
    setSearching(true);
    const timer = setTimeout(async () => {
      try {
        const found = await client.current?.places.autocomplete(
          { query: text, near: origin.current, limit: 8 },
          abort.signal,
        );
        if (!abort.signal.aborted) setSuggestions([...(found ?? [])]);
      } catch (e) {
        if (!abort.signal.aborted) fail(e);
      } finally {
        if (!abort.signal.aborted) setSearching(false);
      }
    }, 300);
    return () => {
      clearTimeout(timer);
      abort.abort();
    };
  }, [query, fail]);

  const clearRoute = useCallback(async () => {
    const old = line.current;
    line.current = null;
    setTrip(null);
    await old?.remove().catch(() => undefined);
  }, []);

  const selectSuggestion = useCallback(
    async (s: PlaceSuggestion) => {
      Keyboard.dismiss();
      skipSearch.current = true;
      setQuery(s.name);
      setSuggestions([]);
      setNotice(null);
      setPlace({ name: s.name, address: s.secondary, point: s.point });
      setPhase("place");
      sheet.current?.snapTo(1);
      try {
        await clearRoute();
        await marker.current?.remove().catch(() => undefined);
        marker.current = await map.current!.addMarker(
          s.point,
          MarkerContent.badge(s.name),
        );
        await map.current!.moveTo(s.point, 15);
        const details = await client.current?.places.details(s.placeId);
        const street = [details?.houseNumber, details?.street]
          .filter(Boolean)
          .join(" ");
        if (street)
          setPlace((p) =>
            p ? { ...p, address: `${street}, ${s.secondary}` } : p,
          );
      } catch (e) {
        fail(e);
      }
    },
    [clearRoute, fail],
  );

  const closePlace = useCallback(async () => {
    setPlace(null);
    setQuery("");
    setPhase("browse");
    sheet.current?.snapTo(0);
    await clearRoute();
    await marker.current?.remove().catch(() => undefined);
    marker.current = null;
  }, [clearRoute]);

  const getDirections = useCallback(
    async (next: TravelMode) => {
      const from = origin.current;
      if (!place || !from || !map.current || !client.current) return;
      setMode(next);
      setPhase("route");
      setLoadingRoute(true);
      setNotice(null);
      sheet.current?.snapTo(1);
      try {
        const result = await client.current.directions({
          origin: from,
          destination: place.point,
          mode: next,
        });
        const route = result.routes[0];
        if (!route) throw new Error("No route found");
        const path = decodePolyline(route.geometry);
        await clearRoute();
        line.current = await map.current.showRoute(route, { mode: next });
        setTrip({ route, path });
        // Fit inside the padding that sits above the (mid-snap) sheet.
        await map.current.setPadding({ top: TOP + 72, bottom: snaps[1] });
        await map.current.fitPoints(path, 40);
      } catch (e) {
        fail(e);
      } finally {
        setLoadingRoute(false);
      }
    },
    [place, clearRoute, snaps, fail],
  );

  // --- Navigation.
  const endNavigation = useCallback(
    async (arrived: boolean) => {
      session.current?.stop();
      session.current = null;
      setProgress(null);
      setWrongRoute(false);
      setDevOpen(false);
      setPhase("route");
      sheet.current?.snapTo(1);
      setNotice(arrived ? "You have arrived" : null);
      try {
        await map.current?.setLocationRoute(null);
        await map.current?.setTracking("none");
        await applyLocation({
          tracking: "none",
          appearance: { kind: "dot" },
          activity: "generic",
        });
        // Reconnect the real source (it was detached while simulating).
        if (permission === "granted")
          await map.current?.useNativeLocationProvider({ intervalMs: 1000 });
        else
          await map.current?.updateLocation({
            point: LAGOS,
            accuracyMetres: 5,
            timestampMs: Date.now(),
          });
        if (trip) await map.current?.fitPoints(trip.path, 40);
      } catch (e) {
        fail(e);
      }
    },
    [applyLocation, trip, permission, fail],
  );

  const startNavigation = useCallback(async () => {
    if (!map.current || !trip) return;
    try {
      setNotice(null);
      setFollowing(true);
      setProgress(null);
      setPhase("navigating");
      sheet.current?.snapTo(0);
      // Simulated: detach the native provider so two sources don't fight.
      if (movement === "simulated") await map.current.setLocationProvider(null);
      await applyLocation({
        tracking: "followHeading",
        activity: MODES[mode].activity,
      });
      const total = indexPath(trip.path).total || 1;
      const nav = new NavigationSession(
        map.current,
        trip.path,
        trip.route,
        mode,
        movement,
        {
          onProgress: (p) => {
            setProgress(p);
            void line.current
              ?.setProgress(1 - p.remainingM / total)
              .catch(() => undefined);
          },
          onArrived: () => void endNavigation(true),
          onError: fail,
        },
        intervalMs,
      );
      session.current = nav;
      await nav.start();
    } catch (e) {
      fail(e);
    }
  }, [trip, mode, movement, intervalMs, applyLocation, endNavigation, fail]);

  const onMapEvent = useCallback((e: RanaEvent) => {
    if (e.type === "tap") {
      Keyboard.dismiss();
      setSuggestions([]);
    }
    // The SDK reports each accepted fix. While the simulated socket drives the map, those fixes are fake: ignore them.
    if (e.type === "location") {
      const point = (e.value as { point: LatLng }).point;
      const nav = session.current;
      if (nav?.movement === "simulated") return;
      setOrigin(point);
      nav?.deviceFix(point);
    }
    if (e.type === "error" && /permission_denied/.test(JSON.stringify(e.value))) {
      setPermission("denied");
      setOrigin(LAGOS);
    }
    if (e.type === "trackingChanged") {
      const v = e.value as unknown;
      const name =
        typeof v === "string"
          ? v
          : String((v as { tracking?: string })?.tracking ?? v);
      setFollowing(!/none/i.test(name));
    }
  }, [setOrigin]);

  const recenter = () => {
    setFollowing(true);
    map.current
      ?.setTracking(phase === "navigating" ? "followHeading" : "follow")
      .catch(fail);
  };
  const chooseMovement = setMovement;
  const toggleStyle = () => {
    nightRef.current = !nightRef.current;
    setNight(nightRef.current);
    map.current
      ?.setStyle({ kind: nightRef.current ? "night" : "day" })
      .catch(fail);
  };
  const toggleWrongRoute = () => {
    const next = !wrongRoute;
    setWrongRoute(next);
    session.current?.setWrongRoute(next).catch(fail);
  };
  const chooseInterval = (ms: number) => {
    setIntervalMs(ms);
    session.current?.setIntervalMs(ms);
  };

  const navigating = phase === "navigating";
  return (
    <View style={styles.root}>
      <RanaMap
        style={StyleSheet.absoluteFill}
        options={MAP_OPTIONS}
        onReady={onReady}
        onEvent={onMapEvent}
        onError={fail}
      />

      {permission === "denied" ? (
        <View style={[styles.card, styles.locationOff]}>
          <Text style={styles.sub}>Location off — using Lagos</Text>
        </View>
      ) : null}

      {navigating ? (
        <View style={[styles.card, styles.banner]}>
          <Text style={styles.bannerText} numberOfLines={2}>
            {progress?.next?.text ?? "Follow the route"}
          </Text>
          {progress?.next ? (
            <Text style={styles.sub}>
              in {formatDistance(progress.next.distanceM)}
            </Text>
          ) : null}
        </View>
      ) : (
        <View style={styles.searchWrap}>
          <View style={[styles.card, styles.searchBar]}>
            <TextInput
              style={styles.input}
              placeholder="Search places"
              placeholderTextColor="#8a8f98"
              value={query}
              onChangeText={setQuery}
              returnKeyType="search"
              autoCorrect={false}
            />
            {searching ? <ActivityIndicator /> : null}
            {query ? (
              <Pressable
                onPress={() => (place ? closePlace() : setQuery(""))}
                accessibilityLabel="Clear search"
                hitSlop={10}
              >
                <Text style={styles.clear}>✕</Text>
              </Pressable>
            ) : null}
          </View>
          {suggestions.length > 0 ? (
            <View style={[styles.card, styles.results]}>
              {suggestions.map((s) => (
                <Pressable
                  key={s.placeId}
                  style={styles.row}
                  onPress={() => selectSuggestion(s)}
                >
                  <Text style={styles.rowTitle} numberOfLines={1}>
                    {s.name}
                  </Text>
                  <Text style={styles.sub} numberOfLines={1}>
                    {s.secondary}
                  </Text>
                </Pressable>
              ))}
            </View>
          ) : null}
        </View>
      )}

      <View style={styles.fabs} pointerEvents="box-none">
        <Fab label={night ? "Day" : "Night"} onPress={toggleStyle} />
        {navigating ? (
          <Fab label="Dev" onPress={() => setDevOpen((o) => !o)} />
        ) : null}
        {!following && permission === "granted" ? (
          <Fab label="Recenter" primary onPress={recenter} />
        ) : null}
      </View>

      {navigating && devOpen ? (
        <View style={[styles.card, styles.dev]}>
          <Text style={styles.rowTitle}>Scenarios</Text>
          <Chips>
            {movement === "simulated" ? (
              <>
                <Chip
                  label="Drop next update"
                  onPress={() => session.current?.dropNext(1)}
                />
                <Chip
                  label="Drop 3 updates"
                  onPress={() => session.current?.dropNext(3)}
                />
              </>
            ) : null}
            <Chip
              label={wrongRoute ? "Restore route" : "Wrong route"}
              active={wrongRoute}
              onPress={toggleWrongRoute}
            />
          </Chips>
          {movement === "simulated" ? (
            <Chips>
              <Chip
                label="1 s"
                active={intervalMs === 1000}
                onPress={() => chooseInterval(1000)}
              />
              <Chip
                label="5 s"
                active={intervalMs === 5000}
                onPress={() => chooseInterval(5000)}
              />
            </Chips>
          ) : null}
          <Text style={styles.sub}>
            fix #{progress?.seq ?? 0} · match{" "}
            {progress?.routeStatus?.state ?? "-"}
            {progress?.routeStatus?.distanceFromRouteMetres != null
              ? ` · ${Math.round(progress.routeStatus.distanceFromRouteMetres)} m off`
              : ""}
          </Text>
        </View>
      ) : null}

      <BottomSheet
        ref={sheet}
        snaps={snaps}
        initialIndex={0}
        onHeight={onSheetHeight}
      >
        {phase === "browse" ? (
          <>
            <Text style={styles.title}>Rana Maps</Text>
            <Text style={styles.sub}>
              {hasOrigin
                ? "Search for a place to get directions."
                : "Waiting for location…"}
            </Text>
          </>
        ) : null}

        {phase === "place" && place ? (
          <>
            <Text style={styles.title}>{place.name}</Text>
            <Text style={styles.sub}>{place.address}</Text>
            <Button
              label={hasOrigin ? "Directions" : "Waiting for location…"}
              disabled={!hasOrigin}
              onPress={() => getDirections(mode)}
            />
          </>
        ) : null}

        {phase === "route" && place ? (
          <>
            <Text style={styles.title} numberOfLines={1}>
              {place.name}
            </Text>
            <Chips>
              {(Object.keys(MODES) as TravelMode[]).map((m) => (
                <Chip
                  key={m}
                  label={MODES[m].label}
                  active={m === mode}
                  onPress={() => getDirections(m)}
                />
              ))}
            </Chips>
            {loadingRoute ? <ActivityIndicator style={styles.gap} /> : null}
            {trip && !loadingRoute ? (
              <>
                <Text style={styles.big}>
                  {formatDuration(trip.route.durationS)} ·{" "}
                  {formatDistance(trip.route.distanceM)}
                </Text>
                {permission === "granted" ? (
                  <>
                    <Text style={[styles.sub, styles.gap]}>Movement</Text>
                    <Chips>
                      <Chip
                        label="Simulated"
                        active={movement === "simulated"}
                        onPress={() => chooseMovement("simulated")}
                      />
                      <Chip
                        label="Device GPS"
                        active={movement === "device"}
                        onPress={() => chooseMovement("device")}
                      />
                    </Chips>
                  </>
                ) : null}
                <Button label="Start" onPress={startNavigation} />
                {trip.route.legs
                  .flatMap((l) => l.steps)
                  .map((s, i) => (
                    <View key={i} style={styles.step}>
                      <Text style={styles.rowTitle}>{s.instruction}</Text>
                      <Text style={styles.sub}>
                        {formatDistance(s.distanceM)}
                      </Text>
                    </View>
                  ))}
              </>
            ) : null}
          </>
        ) : null}

        {navigating ? (
          <>
            <Text style={styles.big}>
              {progress
                ? `${formatDuration(progress.etaS)} · ${formatDistance(progress.remainingM)}`
                : "Starting…"}
            </Text>
            <Text style={styles.sub}>to {place?.name}</Text>
            <Button label="End" danger onPress={() => endNavigation(false)} />
          </>
        ) : null}

        {notice ? <Text style={styles.notice}>{notice}</Text> : null}
      </BottomSheet>
    </View>
  );
}

function Fab({
  label,
  onPress,
  primary,
}: {
  label: string;
  onPress: () => void;
  primary?: boolean;
}) {
  return (
    <Pressable
      onPress={onPress}
      style={[styles.card, styles.fab, primary && styles.fabPrimary]}
      accessibilityRole="button"
    >
      <Text style={[styles.fabText, primary && styles.onPrimary]}>{label}</Text>
    </Pressable>
  );
}

function Button({
  label,
  onPress,
  danger,
  disabled,
}: {
  label: string;
  onPress: () => void;
  danger?: boolean;
  disabled?: boolean;
}) {
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      style={[styles.button, danger && styles.danger, disabled && styles.disabled]}
      accessibilityRole="button"
    >
      <Text style={styles.onPrimary}>{label}</Text>
    </Pressable>
  );
}

function Chips({ children }: { children: React.ReactNode }) {
  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      style={styles.chips}
      contentContainerStyle={styles.chipsContent}
    >
      {children}
    </ScrollView>
  );
}

function Chip({
  label,
  onPress,
  active,
}: {
  label: string;
  onPress: () => void;
  active?: boolean;
}) {
  return (
    <Pressable
      onPress={onPress}
      style={[styles.chip, active && styles.chipActive]}
      accessibilityRole="button"
    >
      <Text style={active ? styles.onPrimary : styles.chipText}>{label}</Text>
    </Pressable>
  );
}

const BLUE = "#1a73e8";
const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#e5e3df" },
  card: {
    backgroundColor: "#fff",
    borderRadius: 14,
    elevation: 6,
    shadowColor: "#000",
    shadowOpacity: 0.15,
    shadowRadius: 6,
    shadowOffset: { width: 0, height: 2 },
  },
  searchWrap: { position: "absolute", top: TOP + 8, left: 12, right: 12 },
  searchBar: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: 14,
    height: 48,
    gap: 8,
  },
  input: { flex: 1, fontSize: 16, color: "#111" },
  clear: { fontSize: 16, color: "#666" },
  results: { marginTop: 6, overflow: "hidden" },
  row: { paddingHorizontal: 14, paddingVertical: 10 },
  rowTitle: { fontSize: 15, fontWeight: "600", color: "#111" },
  sub: { fontSize: 13, color: "#5f6368" },
  banner: {
    position: "absolute",
    top: TOP + 8,
    left: 12,
    right: 12,
    padding: 14,
    backgroundColor: "#0b5d3b",
  },
  bannerText: { color: "#fff", fontSize: 18, fontWeight: "700" },
  fabs: {
    position: "absolute",
    right: 12,
    top: TOP + 72 + 8,
    gap: 8,
    alignItems: "flex-end",
  },
  fab: {
    paddingHorizontal: 14,
    height: 40,
    justifyContent: "center",
    borderRadius: 20,
  },
  fabPrimary: { backgroundColor: BLUE },
  fabText: { fontWeight: "600", color: "#111" },
  dev: {
    position: "absolute",
    left: 12,
    top: TOP + 72 + 8,
    width: 250,
    padding: 12,
    gap: 8,
  },
  title: { fontSize: 22, fontWeight: "700", color: "#111" },
  big: { fontSize: 20, fontWeight: "700", color: "#111", marginTop: 8 },
  gap: { marginTop: 16 },
  button: {
    marginTop: 14,
    backgroundColor: BLUE,
    borderRadius: 24,
    height: 46,
    alignItems: "center",
    justifyContent: "center",
  },
  danger: { backgroundColor: "#d93025" },
  disabled: { backgroundColor: "#9aa0a6" },
  locationOff: {
    position: "absolute",
    top: TOP + 62,
    left: 12,
    paddingHorizontal: 12,
    paddingVertical: 6,
  },
  onPrimary: { color: "#fff", fontWeight: "700", fontSize: 15 },
  chips: { marginTop: 10, flexGrow: 0 },
  chipsContent: { gap: 8 },
  chip: {
    paddingHorizontal: 14,
    height: 34,
    borderRadius: 17,
    backgroundColor: "#eef0f3",
    justifyContent: "center",
  },
  chipActive: { backgroundColor: BLUE },
  chipText: { color: "#111", fontWeight: "600" },
  step: {
    paddingVertical: 10,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: "#d0d3d8",
  },
  notice: { marginTop: 12, color: "#b3261e" },
});
