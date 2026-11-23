# Flutter samples

Run with a public app-restricted key:

```sh
export RANA_PUBLIC_KEY=your_public_key
flutter run -d <android-device>
```

For iOS, set `RANA_PUBLIC_KEY` as an Xcode build setting (for example in an untracked xcconfig) and run the Runner target. AppDelegate configures the SDK before the map initializes. The public key is embedded in the app and should be restricted to its application identity.

To verify host-key wiring independently of the live API, build with the synthetic value `pk_live_fixture` and run
`flutter test integration_test/host_key_test.dart -d <device>`. The fixture intercepts the service request and checks
the configured key and the native package or bundle identifier.

The sample installs `rana_maps` from pub.dev and resolves the native SDK from Rana's Maven repository on Android
and through Swift Package Manager on iOS. Use Flutter 3.44 or later, Android API 26 or later and iOS 17 or later.
Run `flutter pub get` before building.

## Delivery sample

Use the search field to add a drop-off, then start a delivery. The draggable delivery sheet controls the courier's movement source, route scenarios, and stop completion. Live directions and automatic rerouting require a suitable key.

`flutter test integration_test/native_bridge_test.dart -d <device>` runs real channel/native service checks using a host transport without a live key. `journey_test.dart` requires a configured host key and exercises live map readiness.

### Simulated map traffic

Three cars, three bikes, four pedestrians, and five Maruwas (keke tricycles) appear, move, and leave at staggered times near the default Lagos delivery area. Each marker follows a bundled street centerline. The in-memory simulation repeats every 42 seconds.

The map starts `LiveVehiclesController` when it is ready. The controller updates its own `RanaVehicle` overlays using fixes from `SimulatedLocations`. Delivery stops, routing, and courier location continue through `DeliveryController`. Road geometry comes from [© OpenStreetMap contributors](https://www.openstreetmap.org/copyright).

## Key-free Android release checks

From this directory, with an emulator selected with `ANDROID_SERIAL`:

```sh
flutter pub get
ORG_GRADLE_PROJECT_ranaTestBuildType=release flutter build apk --release --target integration_test/native_bridge_test.dart --target-platform android-arm64
./android/gradlew -p android :app:connectedReleaseAndroidTest -PranaTestBuildType=release -Ptarget=integration_test/native_bridge_test.dart -Ptarget-platform=android-arm64
```

The Flutter build bootstraps generated Gradle wrapper files in a freshly unpacked sample. The opt-in property includes the integration-test plugin and its instrumentation rules only for this test variant. The app uses AOT, R8 and resource shrinking. The five checks use injected transports/custom uploads and an inactive offline region; they need no live key and do not establish rendered-map or performance acceptance. Disable emulator networking when reproducing offline boundary evidence.
