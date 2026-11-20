import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:rana_maps/rana_maps.dart';
import 'courier_socket.dart';
import 'geo.dart';

/// Fallback start when location permission is denied.
const lagos = LatLng(latitude: 6.5095, longitude: 3.3711);

/// Preset drop-offs as (name, metres north, metres east) of the start.
const _presets = [
  ('Nearby stop 1', 650.0, -700.0),
  ('Nearby stop 2', -1500.0, -900.0),
  ('Nearby stop 3', -2400.0, -700.0),
];
const maxStops = 6;

class Stop {
  Stop(this.name, this.point);
  final String name;
  final LatLng point;
  bool delivered = false;
  RanaMarker? marker;
}

class DeliveryController extends ChangeNotifier {
  RanaMapController? map;
  RanaClient? client;
  RanaPlaces? places;

  final stops = <Stop>[];

  /// Latest real device fix (null until the first one, or when denied).
  LatLng? userPoint;

  /// Route start: the latest device fix, or [lagos] when permission is denied.
  LatLng? origin;
  bool locationDenied = false;

  /// "Simulated" feeds the fake websocket; otherwise device GPS drives the puck.
  bool simulated = true;

  Path? path; // host route line (what the user sees)
  RanaPolyline? line;
  RanaMarker? depotMarker;
  LatLng? _depotAt;
  int distanceM0 = 0, durationS0 = 0;
  bool planning = false, live = false, usingFallback = false;
  bool running = false, wrongRoute = false;
  String? message;
  Duration interval = const Duration(seconds: 5);
  LocationRouteState routeState = LocationRouteState.none;
  ReroutingState reroutingState = ReroutingState.disabled;
  double remainingM = 0;
  double speed = 9;
  int received = 0, dropped = 0;

  FakeCourierSocket? _socket;
  StreamSubscription<String>? _socketSub;
  final _subs = <StreamSubscription<Object?>>[];
  StreamSubscription<LocationFix>? _gps;
  bool _nativeOn = false;
  int _plan = 0;
  bool _disposed = false;

  Stop? get next {
    for (final s in stops) {
      if (!s.delivered) return s;
    }
    return null;
  }

  int get remainingStops => stops.where((s) => !s.delivered).length;

  Duration? get eta {
    if (path == null) return null;
    if (!running && durationS0 > 0) return Duration(seconds: durationS0);
    return Duration(seconds: (remainingM / speed.clamp(4, 30)).round());
  }

  String get statusLabel {
    if (message != null) return message!;
    if (origin == null) return 'Waiting for location…';
    if (planning) return 'Planning route...';
    if (!running) {
      if (path == null) return 'Add a drop-off to plan a route';
      return usingFallback
          ? 'Estimated route (directions unavailable)'
          : 'Route ready';
    }
    if (wrongRoute) return 'SDK route deliberately wrong';
    return switch (reroutingState) {
      ReroutingState.rerouting || ReroutingState.waiting => 'Rerouting...',
      ReroutingState.rerouted => 'Rerouted',
      ReroutingState.failed || ReroutingState.blocked => 'Reroute failed',
      _ => switch (routeState) {
        LocationRouteState.matched => 'On route',
        LocationRouteState.offRoute => 'Off route',
        LocationRouteState.uncertain => 'Locating on route...',
        LocationRouteState.none => 'Waiting for first update',
      },
    };
  }

  void _publish() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
    } catch (e) {
      message = e is RanaError ? e.message : e.toString();
      _publish();
    }
  }

  // --- map lifecycle ---------------------------------------------------------

  Future<void> ready(RanaMapController controller) => _guard(() async {
    map = controller;
    _subs.addAll([
      controller.locationRouteChanges.listen((s) {
        routeState = s.state;
        _publish();
      }),
      controller.reroutingChanges.listen((s) {
        reroutingState = s.state;
        _publish();
      }),
      controller.rerouted.listen(_onRerouted),
    ]);
    try {
      client = await RanaClient.createConfigured();
      places = RanaPlaces(client!);
    } catch (e) {
      message = 'No API key configured: $e';
    }
    unawaited(_guard(_startLocation)); // permission prompt must not block ready
  });

  // --- device location -----------------------------------------------------

  Future<bool> _requestPermission() async {
    try {
      var p = await geo.Geolocator.checkPermission();
      if (p == geo.LocationPermission.denied) {
        p = await geo.Geolocator.requestPermission();
      }
      return p == geo.LocationPermission.whileInUse ||
          p == geo.LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  Future<void> _startLocation() async {
    if (!await _requestPermission()) {
      locationDenied = true;
      simulated = true;
      await _setOrigin(lagos);
      return;
    }
    // Listen before connecting: a still device (or simulator) may report only
    // one fix. geolocator is only used for the permission prompt.
    _gps = map!.locations.listen(_onFix, onError: (_) {});
    await _guard(_connectNative);
  }

  Future<void> _connectNative() async {
    await map!.useNativeLocationProvider();
    _nativeOn = true;
  }

  Future<void> _disconnectNative() async {
    if (!_nativeOn) return;
    _nativeOn = false;
    await map!.setLocationProvider(null);
  }

  void _onFix(LocationFix fix) {
    // While the simulated socket drives the map its fixes are fake: ignore them.
    if (running && simulated) return;
    final point = fix.point;
    userPoint = point;
    if (running) {
      _onDeviceFix(point);
      return;
    }
    if (origin == null) {
      unawaited(_setOrigin(point));
    } else if (!locationDenied && !planning) {
      origin = point; // next plan starts from where the courier is now
    }
  }

  /// First origin: drop the start marker and the preset stops around it.
  Future<void> _setOrigin(LatLng point) => _guard(() async {
    origin = point;
    if (stops.isEmpty) {
      for (final (name, north, east) in _presets) {
        stops.add(Stop(name, offsetM(point, north, east)));
      }
    }
    for (final s in stops) {
      if (s.marker == null) await _addMarker(s);
    }
    _publish();
    await replan();
  });

  Future<void> _placeDepot(LatLng at) async {
    if (_depotAt == at) return;
    _depotAt = at;
    await depotMarker?.remove();
    depotMarker = await map!.addMarker(
      at,
      content: const MarkerContent.pin(glyph: PinGlyph.home),
      style: const MarkerStyle(accessibilityLabel: 'Start'),
    );
  }

  Future<void> _addMarker(Stop s) async {
    final i = stops.indexOf(s) + 1;
    s.marker = await map!.addMarker(
      s.point,
      content: MarkerContent.pin(label: '$i'),
    );
  }

  Future<void> _renumber() async {
    for (var i = 0; i < stops.length; i++) {
      final s = stops[i];
      final marker = s.marker ??= await map!.addMarker(s.point);
      // One handle per stop: renumbering swaps the label instead of replacing the marker.
      await marker.setContent(MarkerContent.pin(label: '${i + 1}'));
      await marker.setStyle(
        s.delivered
            ? const MarkerStyle(state: MarkerState.disabled, color: '#2E7D32')
            : const MarkerStyle(),
      );
    }
  }

  // --- stops & route planning ---------------------------------------------

  Future<void> addStop(String name, LatLng point) async {
    if (running || stops.length >= maxStops) return;
    final s = Stop(name, point);
    stops.add(s);
    message = null;
    await _guard(() => _addMarker(s));
    _publish();
    await replan();
  }

  Future<void> removeStop(Stop s) async {
    if (running) return;
    stops.remove(s);
    await s.marker?.remove();
    await _guard(_renumber);
    _publish();
    await replan();
  }

  Future<void> replan() => _guard(() async {
    final token = ++_plan;
    final from = origin;
    if (from == null) return;
    final pending = stops.where((s) => !s.delivered).toList();
    if (pending.isEmpty) {
      await _setLine(null);
      path = null;
      _publish();
      return;
    }
    planning = true;
    message = null;
    _publish();
    final waypoints = [
      for (final s in pending.take(pending.length - 1)) s.point,
    ];
    List<LatLng> points;
    try {
      final result = await client!.directions(
        DirectionsOptions(
          origin: RouteLocation(
            latitude: from.latitude,
            longitude: from.longitude,
          ),
          destination: RouteLocation(
            latitude: pending.last.point.latitude,
            longitude: pending.last.point.longitude,
          ),
          waypoints: waypoints.isEmpty ? null : waypoints,
          mode: Mode.car,
        ),
      );
      if (token != _plan) return;
      final r = result.routes.first;
      points = decodePolyline(r.geometry);
      distanceM0 = r.distanceM;
      durationS0 = r.durationS;
      usingFallback = false;
    } catch (_) {
      if (token != _plan) return;
      points = [from, for (final s in pending) s.point];
      final p = Path(points).densified();
      points = p.points;
      distanceM0 = p.length.round();
      durationS0 = (p.length / 8).round();
      usingFallback = true;
    }
    path = Path(points);
    remainingM = path!.length;
    await _setLine(points);
    await _placeDepot(from);
    planning = false;
    _publish();
    await map?.fitPoints([from, ...points]);
  });

  Future<void> _setLine(List<LatLng>? points) async {
    final old = line;
    line = null;
    await old?.remove();
    if (points != null) {
      line = await map!.addPolyline(
        points,
        options: const PolylineOptions(preset: PolylinePreset.car, stops: true),
      );
    }
  }

  // --- run ----------------------------------------------------------------

  Future<void> start() => _guard(() async {
    final p = path;
    final m = map;
    if (running || p == null || m == null) return;
    running = true;
    wrongRoute = false;
    received = dropped = 0;
    routeState = LocationRouteState.none;
    message = null;
    _publish();
    // One source at a time: the fake socket replaces the native provider.
    if (simulated) await _disconnectNative();
    // Navigation puck (arrow) shows the courier's direction during the run.
    await m.applySettings(
      const MapSettings(
        location: LocationOptions(
          appearance: TravellerAppearance.puck,
          motion: LocationMotion.smooth,
          activity: LocationActivity.vehicle, // Mode.car route
        ),
      ),
    );
    await m.setTracking(LocationTracking.followHeading);
    await _setSdkRoute(p.points);
    if (simulated) {
      _socket = FakeCourierSocket(route: p, interval: interval);
      _socketSub = _socket!.stream.listen(_onFrame, onDone: _onSocketDone);
    }
  });

  Future<void> _setSdkRoute(List<LatLng> points) async {
    await map!.setLocationRoute(points);
    await _enableRerouting(); // a manual route change disables rerouting
  }

  Future<void> _enableRerouting() async {
    final pending = stops.where((s) => !s.delivered).toList();
    if (pending.isEmpty || client == null) return;
    await map!.setAutomaticRerouting(
      ReroutingOptions(
        destination: RouteLocation(
          latitude: pending.last.point.latitude,
          longitude: pending.last.point.longitude,
        ),
        mode: Mode.car,
        remainingWaypoints: [
          for (final s in pending.take(pending.length - 1)) s.point,
        ],
      ),
      client: client,
    );
  }

  void _onFrame(String frame) {
    final fix = parseFrame(frame);
    if (fix == null || map == null) return;
    received++;
    dropped = _socket?.dropped ?? dropped;
    speed = fix.speedMetresPerSecond ?? speed;
    _progress(fix.point);
    unawaited(_guard(() => map!.updateLocation(fix)));
    _publish();
  }

  void _onDeviceFix(LatLng point) {
    received++;
    _progress(point);
    _publish();
  }

  void _progress(LatLng at) {
    final p = path;
    if (p == null) return;
    final progress = p.progressOf(at);
    remainingM = p.length - progress;
    unawaited(line?.setProgress(progress / p.length));
  }

  void _onSocketDone() {
    if (running) {
      message = 'Courier reached the end of the route';
      _publish();
    }
  }

  void _onRerouted(ReroutingResult result) {
    // Host owns the line: redraw it from the accepted path. Never call
    // setLocationRoute here; the SDK already installed this geometry.
    if (wrongRoute) wrongRoute = false;
    unawaited(
      _guard(() async {
        await _setLine(result.path);
        _publish();
      }),
    );
  }

  void dropUpdates(int n) => _socket?.drop(n);

  void setInterval(Duration value) {
    interval = value;
    _socket?.interval = value;
    _publish();
  }

  Future<void> useWrongRoute() => _guard(() async {
    final p = path;
    if (!running || p == null) return;
    wrongRoute = true;
    final shifted = [for (final q in p.points) offsetM(q, 420, 420)];
    await _setSdkRoute(shifted);
    _publish();
  });

  Future<void> restoreRoute() => _guard(() async {
    final p = path;
    if (!running || p == null) return;
    wrongRoute = false;
    await _setSdkRoute(p.points);
    _publish();
  });

  Future<void> markDelivered() async {
    final s = next;
    if (!running || s == null) return;
    s.delivered = true;
    await _guard(() async {
      await s.marker?.setStyle(
        const MarkerStyle(state: MarkerState.disabled, color: '#2E7D32'),
      );
    });
    if (remainingStops == 0) {
      await endRun(completed: true);
      return;
    }
    await _guard(_enableRerouting);
    _publish();
  }

  Future<void> recenter() => _guard(
    () => map!.setTracking(
      running ? LocationTracking.followHeading : LocationTracking.follow,
    ),
  );

  void setSimulated(bool value) {
    if (running || (!value && locationDenied)) return;
    simulated = value;
    _publish();
  }

  Future<void> endRun({bool completed = false}) async {
    await _stopStream();
    await _guard(() async {
      final m = map!;
      await m.setAutomaticRerouting(null);
      await m.setTracking(LocationTracking.none);
      await m.setLocationRoute(null);
      await m.applySettings(
        const MapSettings(location: LocationOptions(appearance: TravellerAppearance.dot)),
      );
      if (locationDenied) {
        await m.hideUserLocation();
      } else if (!_nativeOn) {
        await _connectNative();
      }
    });
    running = false;
    wrongRoute = false;
    routeState = LocationRouteState.none;
    reroutingState = ReroutingState.disabled;
    for (final s in stops) {
      s.delivered = false;
    }
    await _guard(_renumber);
    _publish();
    await replan();
    if (completed) {
      message = 'All deliveries completed';
      _publish();
    }
  }

  Future<void> _stopStream() async {
    await _socketSub?.cancel();
    _socketSub = null;
    _socket?.dispose();
    _socket = null;
  }

  void setError(RanaError e) {
    message = e.message;
    _publish();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(_gps?.cancel());
    unawaited(_stopStream());
    super.dispose();
  }
}
