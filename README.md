# Rana Maps SDK examples

These samples use Rana Maps SDK `0.4.0-beta.0`. Get a public key restricted to your website origin,
Android package and signing certificate, or iOS bundle ID. See [developer guides](https://developers.ranamaps.com/sdks/).

| Platform | Run the sample |
| --- | --- |
| Web | In `web/`, run `npm ci` and `python3 -m http.server 8080`. Open `/journey/` or `/explore/` and enter a key restricted to `http://localhost:8080`. |
| Android | In `android/`, use JDK 17 and Android SDK 37. Run `./gradlew :sample:assembleDebug -PranaKey="$RANA_PUBLIC_KEY"` or build `:ridehail:assembleDebug` for the ride-hail demo. |
| iOS | In `ios/`, run `xcodegen generate` and open `RanaMapsExamples.xcodeproj`. Put `RANA_KEY = <your key>` in `Examples/Config/Keys.local.xcconfig`. Choose either sample scheme and run. SwiftPM downloads Rana’s native binaries. |
| Flutter | In `flutter/`, run `flutter pub get` and follow the [Flutter sample setup](flutter/README.md). |
| React Native | In `react-native/`, follow the [Expo sample setup](react-native/README.md). |

See the [host key setup](docs/host-key.md) and [bare React Native installation](docs/react-native.md).
