import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rana_maps/rana_maps.dart';

import 'simulated_locations.dart';

/// Ambient delivery-map overlays driven independently of the courier's GPS.
class LiveVehiclesController {
  // Short steps keep native point-to-point animation close to the road at bends.
  static const _interval = Duration(milliseconds: 250);
  final _locations = SimulatedLocations();
  final _vehicles = <String, RanaVehicle>{};
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _applying = false;
  bool _disposed = false;
  void start(RanaMapController map) {
    if (_disposed || _timer != null) return;
    _timer = Timer.periodic(_interval, (_) => unawaited(_applyFrame(map)));
    unawaited(_applyFrame(map));
  }

  Future<void> _applyFrame(RanaMapController map) async {
    // Skip ticks while a snapshot is in flight so add/update/remove stay ordered.
    if (_disposed || _applying) return;
    _applying = true;
    try {
      final fixes = _locations.at(_elapsed);
      final activeIds = fixes.map((fix) => fix.id).toSet();

      for (final id in _vehicles.keys.toList()) {
        if (activeIds.contains(id)) continue;
        await _vehicles[id]!.remove();
        if (_disposed) return;
        _vehicles.remove(id);
      }

      for (final fix in fixes) {
        final vehicle = _vehicles[fix.id];
        if (vehicle == null) {
          final added = await map.addVehicle(
            fix.point,
            appearance: VehicleAppearance.kit(
              fix.kind,
              base: VehicleBase.none,
              color: switch (fix.kind) {
                VehicleKind.car => '#244898',
                VehicleKind.keke => '#A44816',
                VehicleKind.walker => '#793A83',
                _ => '#15794E',
              },
            ),
            options: VehicleOptions(
              heading: fix.heading,
              size: 26,
              accessibilityLabel: fix.id,
            ),
          );
          if (_disposed) return;
          _vehicles[fix.id] = added;
        } else {
          await vehicle.update(
            fix.point,
            heading: fix.heading,
            durationMs: _interval.inMilliseconds,
          );
          if (_disposed) return;
        }
      }

      _elapsed += _interval;
    } catch (error) {
      _timer?.cancel();
      if (!_disposed) {
        debugPrint(
          'Simulated map traffic stopped: ${RanaError.from(error).message}',
        );
      }
    } finally {
      _applying = false;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    // RanaMap owns the native overlays and releases them when it unmounts.
    _vehicles.clear();
  }
}
