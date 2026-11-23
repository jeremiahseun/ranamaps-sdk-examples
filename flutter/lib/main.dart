// Keep the Flutter 3.44 import; newer SDKs re-export material_ui here.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:rana_maps/rana_maps.dart' as rana;
import 'delivery_controller.dart';
import 'delivery_sheet.dart';
import 'live_vehicles/live_vehicles_controller.dart';
import 'stop_search.dart';

void main() => runApp(const DeliveryApp());

class DeliveryApp extends StatelessWidget {
  const DeliveryApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFF0B6E4F),
      useMaterial3: true,
    ),
    home: const DeliveryScreen(),
  );
}

class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key});
  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  static const snaps = [0.16, 0.42, 0.85];
  static const searchBarHeight = 56.0;

  final controller = DeliveryController();
  final traffic = LiveVehiclesController();
  final extent = ValueNotifier<double>(snaps[1]);
  double _height = 0, _top = 0;
  bool _padBusy = false, _padDirty = false;

  @override
  void dispose() {
    traffic.dispose();
    extent.dispose();
    controller.dispose();
    super.dispose();
  }

  /// Latest-wins: while one padding call is in flight, only the newest
  /// value is applied afterwards.
  Future<void> _applyPadding() async {
    _padDirty = true;
    if (_padBusy || controller.map == null) return;
    _padBusy = true;
    try {
      while (_padDirty) {
        _padDirty = false;
        await controller.map!.setPadding(
          rana.MapPadding(
            top: _top + searchBarHeight + 16,
            bottom: extent.value * _height,
          ),
        );
      }
    } catch (_) {
      // Padding is best effort; the next sheet change retries.
    } finally {
      _padBusy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    _top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(
        builder: (context, box) {
          _height = box.maxHeight;
          return Stack(
            children: [
              Positioned.fill(
                child: rana.RanaMap(
                  onReady: (m) async {
                    traffic.start(m);
                    await controller.ready(m);
                    unawaited(_applyPadding());
                  },
                  onError: controller.setError,
                  options: rana.MapOptions(
                    center: const rana.LatLng(latitude: 6.5, longitude: 3.365),
                    zoom: 12.5,
                    controls: const rana.ControlsOptions(
                      compass: rana.ControlPlacement.hidden,
                      zoom: rana.ControlPlacement.hidden,
                      locate: rana.ControlPlacement.hidden,
                    ),
                    settings: rana.MapSettings(
                      padding: rana.MapPadding(
                        top: _top + searchBarHeight + 16,
                        bottom: snaps[1] * box.maxHeight,
                      ),
                      location: const rana.LocationOptions(
                        appearance: rana.TravellerAppearance.dot,
                        motion: rana.LocationMotion.smooth,
                        activity: rana.LocationActivity.vehicle,
                        tracking: rana.LocationTracking.none,
                        firstFixZoom: 16.5, // SDK eases to the first fix
                      ),
                    ),
                  ),
                ),
              ),
              NotificationListener<DraggableScrollableNotification>(
                onNotification: (n) {
                  extent.value = n.extent;
                  unawaited(_applyPadding());
                  return false;
                },
                child: DraggableScrollableSheet(
                  initialChildSize: snaps[1],
                  minChildSize: snaps[0],
                  maxChildSize: snaps[2],
                  snap: true,
                  snapSizes: snaps,
                  builder: (context, scroll) => ListenableBuilder(
                    listenable: controller,
                    builder: (_, _) => DeliverySheetContent(
                      controller: controller,
                      scroll: scroll,
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder<double>(
                valueListenable: extent,
                builder: (_, e, child) => Positioned(
                  right: 16,
                  bottom: e * box.maxHeight + 16,
                  child: child!,
                ),
                child: FloatingActionButton.small(
                  key: const Key('recenter'),
                  tooltip: 'Recenter',
                  onPressed: () => unawaited(controller.recenter()),
                  child: const Icon(Icons.my_location),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: ListenableBuilder(
                    listenable: controller,
                    builder: (_, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StopSearch(controller: controller),
                        if (controller.locationDenied)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Chip(
                              key: const Key('location-off'),
                              avatar: const Icon(
                                Icons.location_off_outlined,
                                size: 18,
                              ),
                              label: const Text('Location off — using Lagos'),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
