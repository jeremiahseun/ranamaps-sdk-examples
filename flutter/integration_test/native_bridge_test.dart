import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rana_maps/rana_maps.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => RanaMaps.setTelemetry(false));
  testWidgets(
    'real Pigeon native service transport, identity and stale handles',
    (tester) async {
      expect(await RanaMaps.version(), '0.4.0-beta.0');
      var count = 0;
      final client = await RanaClient.create(
        'pk_live_fixture',
        transport: (request, token) async {
          count++;
          expect(request.headers['X-Rana-Key'], 'pk_live_fixture');
          expect(
            request.headers.keys.any(
              (key) =>
                  key == 'X-Rana-Ios-Bundle' || key == 'X-Rana-Android-Package',
            ),
            isTrue,
          );
          expect(request.url, contains('/v1/geocode?q=Lagos'));
          return const HttpAnswer(
            status: 200,
            headers: {'rana-request-id': 'native-fixture'},
            body:
                '{"results":[{"label":"Lagos","point":{"lat":6.5,"lng":3.4},"kind":"city","place_id":"fixture"}]}',
          );
        },
      );
      final result = await client.geocode(const SearchOptions(query: 'Lagos'));
      expect(result.single.point.latitude, 6.5);
      expect(result.single.point.longitude, 3.4);
      expect(count, 1);
      await client.dispose();
      await expectLater(
        client.geocode(const SearchOptions(query: 'Lagos')),
        throwsA(isA<RanaError>().having((e) => e.code, 'code', 'stale_handle')),
      );
    },
  );
  testWidgets('native service errors retain structured response metadata', (
    tester,
  ) async {
    final client = await RanaClient.create(
      'pk_live_fixture',
      transport: (request, token) async => const HttpAnswer(
        status: 429,
        headers: {'rana-request-id': 'error-fixture', 'retry-after': '8'},
        body: '{"error":"rate_limited","message":"Fixture limit reached"}',
      ),
    );
    try {
      await expectLater(
        client.geocode(const SearchOptions(query: 'Lagos')),
        throwsA(
          isA<RanaError>()
              .having((e) => e.code, 'code', 'rate_limited')
              .having((e) => e.message, 'message', 'Fixture limit reached')
              .having((e) => e.status, 'status', 429)
              .having((e) => e.requestId, 'requestId', 'error-fixture')
              .having((e) => e.retryAfter, 'retryAfter', 8),
        ),
      );
    } finally {
      await client.dispose();
    }
  });
  testWidgets(
    'native request cancellation aborts the host callback and ignores its late answer',
    (tester) async {
      final started = Completer<void>(), cancelled = Completer<void>();
      final answer = Completer<HttpAnswer>();
      final client = await RanaClient.create(
        'pk_live_fixture',
        transport: (request, token) async {
          token.listen(() {
            if (!cancelled.isCompleted) cancelled.complete();
          });
          started.complete();
          return answer.future;
        },
      );
      final token = RanaCancellationToken();
      final completed = expectLater(
        client
            .geocode(const SearchOptions(query: 'Lagos'), token: token)
            .timeout(const Duration(seconds: 10)),
        throwsA(isA<RanaError>().having((e) => e.code, 'code', 'cancelled')),
      );
      try {
        await started.future.timeout(const Duration(seconds: 10));
        token.cancel();
        await cancelled.future.timeout(const Duration(seconds: 10));
        answer.complete(
          const HttpAnswer(status: 200, headers: {}, body: '{"results":[]}'),
        );
        await completed;
      } finally {
        if (!answer.isCompleted) {
          answer.complete(
            const HttpAnswer(status: 200, headers: {}, body: '{"results":[]}'),
          );
        }
        await client.dispose();
      }
    },
  );
  testWidgets(
    'inactive offline metadata restores across manager disposal and deletes without a map',
    (tester) async {
      final id = 'keyfree_${DateTime.now().microsecondsSinceEpoch}';
      RanaOfflineManager? manager;
      try {
        manager = await RanaOfflineManager.create('pk_live_fixture');
        final region = await manager.createRegion(
          OfflineRegionOptions(
            id: id,
            bounds: const CameraBounds(
              southWest: LatLng(latitude: 6.50, longitude: 3.40),
              northEast: LatLng(latitude: 6.51, longitude: 3.41),
            ),
            minZoom: 0,
            maxZoom: 0,
            maxBytes: 1024 * 1024,
          ),
        );
        expect(region.info.id, id);
        expect(region.info.bounds.southWest.latitude, 6.50);
        await region.pause();
        expect((await region.progress())?.active ?? false, isFalse);
        expect(
          (await manager.regions()).where((r) => r.info.id == id),
          hasLength(1),
        );
        await manager.dispose();
        manager = null;
        await expectLater(
          region.progress(),
          throwsA(
            isA<RanaError>().having((e) => e.code, 'code', 'stale_handle'),
          ),
        );
        manager = await RanaOfflineManager.create('pk_live_fixture');
        final restored = (await manager.regions()).singleWhere(
          (r) => r.info.id == id,
        );
        expect(restored.info.maxBytes, 1024 * 1024);
        await restored.remove();
        await expectLater(
          restored.progress(),
          throwsA(
            isA<RanaError>().having((e) => e.code, 'code', 'stale_handle'),
          ),
        );
        expect(
          (await manager.regions()).where((r) => r.info.id == id),
          isEmpty,
        );
      } finally {
        await manager?.dispose();
        // Clean only this fixture, including when an earlier assertion failed.
        final cleanup = await RanaOfflineManager.create('pk_live_fixture');
        try {
          for (final region in (await cleanup.regions()).where(
            (r) => r.info.id == id,
          )) {
            await region.remove();
          }
        } finally {
          await cleanup.dispose();
        }
      }
    },
  );
  testWidgets(
    'simulated trace callbacks preserve data and revocation stops collection',
    (tester) async {
      var httpRequests = 0, uploads = 0;
      final client = await RanaClient.create(
        'pk_live_fixture',
        transport: (request, token) async {
          httpRequests++;
          throw StateError('Trace fixture must use its custom uploader');
        },
      );
      JourneyTraceRecorder? recorder;
      try {
        await expectLater(
          client.createTraceRecorder(
            const JourneyTraceOptions(
              consent: false,
              source: JourneyTraceSource.simulated,
            ),
          ),
          throwsA(
            isA<RanaError>().having((e) => e.code, 'code', 'invalid_argument'),
          ),
        );
        recorder = await client.createTraceRecorder(
          const JourneyTraceOptions(
            consent: true,
            source: JourneyTraceSource.simulated,
            mode: Mode.okada,
          ),
          uploader: (batch, token) async {
            uploads++;
            expect(batch.consent, isTrue);
            expect(batch.source, JourneyTraceSource.simulated);
            expect(batch.mode, Mode.okada);
            expect(batch.points, hasLength(6));
            expect(batch.points.first.latitude, 6.5);
            expect(batch.points.first.accuracyM, 5);
            expect(batch.journeyId, isNotEmpty);
            expect(batch.batchId, isNotEmpty);
            return const JourneyTraceReceipt(accepted: 0, simulated: true);
          },
        );
        final start = DateTime.now().millisecondsSinceEpoch.toDouble() - 4000;
        for (var i = 0; i < 6; i++) {
          await recorder.record(
            LocationFix(
              point: LatLng(latitude: 6.5 + i * .0001, longitude: 3.4),
              timestampMs: start + i * 600,
              accuracyMetres: 5,
              speedMetresPerSecond: 10,
              heading: 90,
            ),
          );
        }
        expect((await recorder.status()).buffered, 6);
        await recorder.flush();
        final flushed = await recorder.status();
        expect(flushed.buffered, 0);
        expect(flushed.uploaded, 0);
        expect(flushed.error, isNull);
        expect(uploads, 1);
        await recorder.stop();
        await recorder.record(
          LocationFix(
            point: const LatLng(latitude: 6.6, longitude: 3.5),
            timestampMs: DateTime.now().millisecondsSinceEpoch.toDouble(),
            accuracyMetres: 5,
          ),
        );
        await recorder.flush();
        final stopped = await recorder.status();
        expect(stopped.stopped, isTrue);
        expect(stopped.buffered, 0);
        expect(uploads, 1);
        expect(httpRequests, 0);
      } finally {
        await recorder?.dispose();
        await client.dispose();
      }
    },
  );
}
