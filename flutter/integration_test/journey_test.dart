// Keep the Flutter 3.44 import; newer SDKs re-export material_ui here.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rana_maps_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<bool> pumpUntil(
    WidgetTester t,
    bool Function() ok,
    int seconds,
  ) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    while (!ok() && DateTime.now().isBefore(deadline)) {
      await t.pump(const Duration(milliseconds: 250));
    }
    return ok();
  }

  testWidgets('delivery run: plan, start, scenarios, deliver, end', (t) async {
    app.main();
    await t.pump();
    // No AppBar: the map is full bleed.
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Start delivery'), findsOneWidget);
    expect(find.byKey(const Key('movement')), findsOneWidget);

    // Grant location first on a fresh install (the native prompt blocks the
    // origin); denied falls back to Lagos. Route planning (live directions, or the offline estimate) enables start.
    final startButton = find.byKey(const Key('primary-action'));
    expect(
      await pumpUntil(
        t,
        () => t.widget<FilledButton>(startButton).onPressed != null,
        60,
      ),
      isTrue,
    );

    await t.tap(startButton);
    await t.pump(const Duration(seconds: 2));
    expect(find.text('End run'), findsOneWidget);
    expect(find.text('Wrong route'), findsOneWidget);

    await t.tap(find.text('Drop next update'));
    await t.tap(find.text('Wrong route'));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Restore route'), findsOneWidget);
    await t.tap(find.text('Restore route'));
    await t.pump(const Duration(seconds: 1));

    await t.tap(find.byKey(const Key('mark-delivered')));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Delivered'), findsOneWidget);

    await t.tap(find.text('End run'));
    await t.pump(const Duration(seconds: 2));
    expect(find.text('Start delivery'), findsOneWidget);
    expect(find.text('Delivered'), findsNothing);
  });
}
