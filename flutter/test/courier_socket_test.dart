import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rana_maps/rana_maps.dart';
import 'package:rana_maps_example/courier_socket.dart';
import 'package:rana_maps_example/geo.dart';

void main() {
  final route = Path([
    const LatLng(latitude: 6.5, longitude: 3.3),
    const LatLng(latitude: 6.5, longitude: 3.31),
    const LatLng(latitude: 6.51, longitude: 3.31),
  ]);

  test('walks the route at ~9 m/s with bounded noise and drops frames', () {
    fakeAsync((async) {
      final socket = FakeCourierSocket(
        route: route,
        interval: const Duration(seconds: 5),
      );
      final fixes = <LocationFix>[];
      socket.stream.listen((f) => fixes.add(parseFrame(f)!));
      async.elapse(const Duration(seconds: 1));
      socket.drop(1);
      async.elapse(const Duration(seconds: 20));
      expect(socket.dropped, 1);
      expect(fixes.length, 4); // t=0, (t=5 dropped), 10, 15, 20
      for (var i = 1; i < fixes.length; i++) {
        final d = distanceM(fixes[i - 1].point, fixes[i].point);
        expect(d, closeTo(i == 1 ? 90 : 45, 12));
        expect(fixes[i].speedMetresPerSecond, closeTo(9, 1));
        expect(fixes[i].heading, inInclusiveRange(0, 360));
      }
      socket.dispose();
    });
  });
}
