import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rana_maps/rana_maps.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'host configuration supplies service credential and app identity',
    (tester) async {
      await RanaMaps.setTelemetry(false);
      var called = false;
      final client = await RanaClient.createConfigured(
        transport: (request, token) async {
          called = true;
          expect(request.headers['X-Rana-Key'], 'pk_live_fixture');
          expect(
            request.headers['X-Rana-Android-Package'] ??
                request.headers['X-Rana-Ios-Bundle'],
            Platform.isAndroid
                ? 'com.ranamaps.rana_maps_example'
                : 'com.ranamaps.ranaMapsExample',
          );
          return const HttpAnswer(
            status: 200,
            headers: {},
            body: '{"results":[]}',
          );
        },
      );
      try {
        await client.geocode(const SearchOptions(query: 'Lagos'));
        expect(called, isTrue);
      } finally {
        await client.dispose();
      }
    },
  );
}
