import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:rana_maps/rana_maps.dart';
import 'geo.dart';

/// Stand-in for a backend websocket: every interval it emits one JSON text
/// frame with the courier's noisy GPS fix while walking [route] at [speedMps].
class FakeCourierSocket {
  FakeCourierSocket({
    required this.route,
    this.speedMps = 9,
    this.noiseM = 3,
    this.interval = const Duration(seconds: 5),
    int seed = 7,
  }) : _random = math.Random(seed) {
    _controller = StreamController<String>(onListen: _tick, onCancel: dispose);
  }

  final Path route;
  final double speedMps, noiseM;
  Duration interval;
  final math.Random _random;
  late final StreamController<String> _controller;
  Timer? _timer;
  double _travelled = 0;
  int _drop = 0;
  int dropped = 0;

  Stream<String> get stream => _controller.stream;

  /// Simulate packet loss: the courier keeps moving, frames never arrive.
  void drop(int count) => _drop += count;

  void _tick() {
    if (_controller.isClosed) return;
    final d = _travelled.clamp(0.0, route.length);
    if (_drop > 0) {
      _drop--;
      dropped++;
    } else {
      _controller.add(_frame(d));
    }
    if (d >= route.length) {
      unawaited(_controller.close());
      return;
    }
    _travelled += speedMps * interval.inMilliseconds / 1000;
    _timer = Timer(interval, _tick);
  }

  String _frame(double d) {
    double n() => (_random.nextDouble() * 2 - 1) * noiseM;
    final p = offsetM(route.at(d), n(), n());
    return jsonEncode({
      'type': 'courier.position',
      'lat': p.latitude,
      'lng': p.longitude,
      'speed': speedMps + (_random.nextDouble() - .5) * .6,
      'course': route.courseAt(d),
      'accuracy': 5,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (!_controller.isClosed) unawaited(_controller.close());
  }
}

/// Parse one websocket frame into an SDK location fix.
LocationFix? parseFrame(String frame) {
  final m = jsonDecode(frame);
  if (m is! Map || m['type'] != 'courier.position') return null;
  return LocationFix(
    point: LatLng(
      latitude: (m['lat'] as num).toDouble(),
      longitude: (m['lng'] as num).toDouble(),
    ),
    accuracyMetres: (m['accuracy'] as num?)?.toDouble(),
    heading: (m['course'] as num?)?.toDouble(),
    speedMetresPerSecond: (m['speed'] as num?)?.toDouble(),
    courseAccuracyDegrees: 10,
    timestampMs: (m['ts'] as num).toDouble(),
  );
}
