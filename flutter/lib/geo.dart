import 'dart:math' as math;
import 'package:rana_maps/rana_maps.dart';

const _earth = 6371008.8;
double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;

double distanceM(LatLng a, LatLng b) {
  final dLat = _rad(b.latitude - a.latitude);
  final dLng = _rad(b.longitude - a.longitude);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.latitude)) *
          math.cos(_rad(b.latitude)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * _earth * math.asin(math.sqrt(h.toDouble()));
}

/// Initial bearing from [a] to [b], clockwise from true north, 0..360.
double bearingDeg(LatLng a, LatLng b) {
  final dLng = _rad(b.longitude - a.longitude);
  final y = math.sin(dLng) * math.cos(_rad(b.latitude));
  final x =
      math.cos(_rad(a.latitude)) * math.sin(_rad(b.latitude)) -
      math.sin(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.cos(dLng);
  return (_deg(math.atan2(y, x)) + 360) % 360;
}

LatLng offsetM(LatLng p, double northM, double eastM) => LatLng(
  latitude: p.latitude + _deg(northM / _earth),
  longitude: p.longitude + _deg(eastM / (_earth * math.cos(_rad(p.latitude)))),
);

/// A polyline with cumulative distances, so it can be walked and measured.
class Path {
  Path(this.points) {
    var sum = 0.0;
    cum = [0.0];
    for (var i = 1; i < points.length; i++) {
      sum += distanceM(points[i - 1], points[i]);
      cum.add(sum);
    }
  }

  final List<LatLng> points;
  late final List<double> cum;
  double get length => cum.last;

  /// Position at [d] metres from the start (clamped).
  LatLng at(double d) {
    if (points.length < 2) return points.first;
    final x = d.clamp(0.0, length);
    var i = 1;
    while (i < cum.length - 1 && cum[i] < x) {
      i++;
    }
    final seg = cum[i] - cum[i - 1];
    final t = seg <= 0 ? 0.0 : (x - cum[i - 1]) / seg;
    final a = points[i - 1], b = points[i];
    return LatLng(
      latitude: a.latitude + (b.latitude - a.latitude) * t,
      longitude: a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  /// Travel direction at [d], from a short look-ahead.
  double courseAt(double d) {
    final a = at(math.max(0, d - 4)), b = at(math.min(length, d + 4));
    return bearingDeg(a, b);
  }

  /// Distance along the path of the vertex nearest to [p].
  double progressOf(LatLng p) {
    var best = double.infinity, at = 0.0;
    for (var i = 0; i < points.length; i++) {
      final d = distanceM(points[i], p);
      if (d < best) {
        best = d;
        at = cum[i];
      }
    }
    return at;
  }

  /// Same shape with a vertex at least every [maxGap] metres.
  Path densified([double maxGap = 25]) {
    final out = <LatLng>[points.first];
    for (var i = 1; i < points.length; i++) {
      final n = (distanceM(points[i - 1], points[i]) / maxGap).ceil();
      for (var k = 1; k <= n; k++) {
        final t = k / n;
        out.add(
          LatLng(
            latitude:
                points[i - 1].latitude +
                (points[i].latitude - points[i - 1].latitude) * t,
            longitude:
                points[i - 1].longitude +
                (points[i].longitude - points[i - 1].longitude) * t,
          ),
        );
      }
    }
    return Path(out);
  }
}
