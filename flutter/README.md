# Flutter journey sample

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

Tap the map to select a destination. Exercise playback/pause/scrub/reset, day/night, direct/smooth motion, route-aware movement and detours, a draggable sheet and interactive widget marker. Live directions, automatic rerouting, simulated trace validation and offline downloads require a suitable key. Traces are simulated and opt-in; they never become measured learning evidence.

`flutter test integration_test/native_bridge_test.dart -d <device>` runs real channel/native service checks using a host transport without a live key. `journey_test.dart` requires a configured host key and exercises live map readiness.

## Key-free Android release checks

From this directory, with an emulator selected with `ANDROID_SERIAL`:

```sh
flutter pub get
ORG_GRADLE_PROJECT_ranaTestBuildType=release flutter build apk --release --target integration_test/native_bridge_test.dart --target-platform android-arm64
./android/gradlew -p android :app:connectedReleaseAndroidTest -PranaTestBuildType=release -Ptarget=integration_test/native_bridge_test.dart -Ptarget-platform=android-arm64
```

The Flutter build bootstraps generated Gradle wrapper files in a freshly unpacked sample. The opt-in property includes the integration-test plugin and its instrumentation rules only for this test variant. The app uses AOT, R8 and resource shrinking. The five checks use injected transports/custom uploads and an inactive offline region; they need no live key and do not establish rendered-map or performance acceptance. Disable emulator networking when reproducing offline boundary evidence.
