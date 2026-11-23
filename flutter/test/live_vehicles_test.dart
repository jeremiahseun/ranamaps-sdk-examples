import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rana_maps/rana_maps.dart';
import 'package:rana_maps_example/geo.dart';
import 'package:rana_maps_example/live_vehicles/live_vehicles_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reconciles arrivals, independent movement, departures and reentry', () {
    fakeAsync((clock) {
      final runtime = _RecordingRuntime();
      final controller = LiveVehiclesController();
      controller.start(RanaMapController(runtime, 'map'));
      clock.flushMicrotasks();

      expect(runtime.activeKinds, {
        'car': 2,
        'okada': 1,
        'walker': 1,
        'keke': 1,
      });
      expect(runtime.added.keys, [
        'Car 01',
        'Car 02',
        'Bike 01',
        'Walker 01',
        'Maruwa 01',
      ]);
      final firstCar = runtime.added['Car 01']!;
      final secondCar = runtime.added['Car 02']!;
      final firstBike = runtime.added['Bike 01']!;

      clock.elapse(const Duration(seconds: 1));
      final carFix = runtime.fixes[firstCar]!;
      final otherCarFix = runtime.fixes[secondCar]!;
      final bikeFix = runtime.fixes[firstBike]!;
      for (final (handle, fix) in [
        (firstCar, carFix),
        (secondCar, otherCarFix),
        (firstBike, bikeFix),
      ]) {
        expect(
          distanceM(fix['point'] as LatLng, runtime.startPoints[handle]!),
          greaterThan(0),
        );
      }
      expect(carFix['heading'], isNot(otherCarFix['heading']));
      expect(carFix['durationMs'], 250);

      clock.elapse(const Duration(seconds: 10));
      expect(runtime.activeKinds, {
        'car': 3,
        'okada': 2,
        'bicycle': 1,
        'walker': 4,
        'keke': 5,
      });
      expect(runtime.added['Car 01'], firstCar);

      clock.elapse(const Duration(seconds: 8));
      expect(runtime.removed, [firstBike]);
      expect(runtime.activeKinds['okada'], 1);

      clock.elapse(const Duration(seconds: 23));
      expect(runtime.removed, hasLength(15));
      expect(runtime.activeKinds, {
        'car': 2,
        'okada': 1,
        'walker': 1,
        'keke': 1,
      });
      expect(runtime.added['Car 01'], isNot(firstCar));

      controller.dispose();
      final callsAtDisposal = runtime.calls;
      clock.elapse(const Duration(seconds: 42));
      expect(runtime.calls, callsAtDisposal);
    });
  });
}

class _RecordingRuntime extends RanaRuntime {
  final added = <String, String>{};
  final startPoints = <String, LatLng>{};
  final fixes = <String, Map<String, Object?>>{};
  final removed = <String>[];
  final _active = <String, String>{};
  int calls = 0;

  Map<String, int> get activeKinds {
    final counts = <String, int>{};
    for (final kind in _active.values) {
      counts.update(kind, (count) => count + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  @override
  Future<Object?> call(
    String target,
    String method, [
    Object arguments = const {},
    RanaCancellationToken? token,
  ]) async {
    calls++;
    switch (method) {
      case 'addVehicle':
        final args = arguments as Map<String, Object?>;
        final options = args['options'] as VehicleOptions;
        final handle = 'vehicle-$calls';
        added[options.accessibilityLabel!] = handle;
        startPoints[handle] = args['point'] as LatLng;
        final appearance = args['appearance'] as VehicleAppearanceWire;
        expect(appearance.base, VehicleBase.none);
        _active[handle] = appearance.vehicle!.name;
        return handle;
      case 'update':
        expect(_active, contains(target));
        fixes[target] = arguments as Map<String, Object?>;
        return null;
      case 'remove':
        removed.add(target);
        _active.remove(target);
        return null;
      default:
        fail('Unexpected call $method on $target');
    }
  }
}
