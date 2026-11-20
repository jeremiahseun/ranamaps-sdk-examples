# Rana Maps for React Native — 0.4.0-beta.0

Native maps and services for modern React Native on Android API 26+ and iOS 17+. Uses Fabric components and TurboModules, with TypeScript value types. Expo development builds are supported through `app.plugin.js`. Expo Go and legacy architecture are not supported.

Install the [React Native beta archive](https://github.com/jeremiahseun/ranamaps-sdk-examples/releases/tag/0.4.0-beta.0)
and use the matching native packages from Rana Maven and the hosted CocoaPods specification.

```tsx
import {MarkerContent, RanaMap, RanaViewMarker, createClient} from '@ranamaps/maps-react-native';

<RanaMap
  options={{center: {latitude: 6.5244, longitude: 3.3792}, zoom: 12}}
  onReady={async map => {
    await map.addMarker({latitude: 6.52, longitude: 3.38}, MarkerContent.badge('₦2,500'));
  }}>
  <RanaViewMarker point={{latitude: 6.52, longitude: 3.38}}
    style={{width: 140, height: 44}}>
    <YourInteractiveMarker />
  </RanaViewMarker>
</RanaMap>

const client = await createClient();
const result = await client.directions({
  origin: {latitude: 6.52, longitude: 3.38},
  destination: {placeId: 'your-place-id'}, mode: 'okada',
});
await client.dispose();
```

`RanaMap` accepts a controller ref, `onMapCreated`, `onReady`, `onEvent` and `onError`. Use controller methods after readiness. Unchanged serialized component options do not reconfigure the map on rerenders. Keep view-marker React keys stable and give markers a measurable layout. Marker children remain live native React views. View markers do not cluster, participate in renderer collision or use native dragging. Use image/kit markers or GeoJSON for large collections.

Controllers expose camera/constraints/gestures/controls/padding, styles, tracking/location/heading, route matching, optional rerouting, trace attachment, overlays, GeoJSON sources/layers/expressions and feature queries. Methods return Promises and typed resource handles. `onEvent` returns an unsubscribe function. Remove overlays and dispose clients/managers/recorders when their owner is finished.

`createClient` works without a mounted map. It provides key info, directions, matrix, snapping, geocoding, `places.autocomplete/details/nearby`, raw trace upload and trace recorder creation. Native code supplies the host app identity. `RanaError` preserves code, message, status, request ID and Retry-After seconds. Async operations accept `AbortSignal` where applicable. Custom HTTP transports, rerouting providers and trace uploaders receive cancellation signals. Custom location providers have independent location/heading subscriptions and stop on replacement/lifecycle changes.

Units: named WGS84 latitude/longitude, logical pixels, metres, degrees clockwise from true north, millisecond durations/timestamps. GeoJSON keeps longitude/latitude order.

Permissions are host-owned. Rerouting and traces are off by default. Set a location route before enabling rerouting with a client or custom provider. Rerouting uses ordinary directions usage; the host updates route-line/UI from accepted replacement events. Trace recording requires explicit consent and a measured/simulated source. Simulated batches create zero learning evidence. `stop()` revokes collection and discards unsent fixes; diagnostics do not grant consent.

`createOfflineManager` is independent of the map. Create/list/restore region handles, observe progress, pause/resume/refresh/remove. Failed deletion retains a usable handle for retry. Offline regions cache maps, not routing/search services or background scheduling.

## Expo

Add `[@ranamaps/maps-react-native, options]` to the `plugins` array in app config (use a normal JSON string for the package name):

```json
["@ranamaps/maps-react-native", {
  "locationWhenInUsePermission": "Show your position on the map.",
  "locationPermission": true
}]
```

The plugin sets platform floors, adds the native Maven repository and CocoaPods spec, and optionally declares foreground location permissions. It does not prompt for permission or enable background location. Build a development client after prebuild. Set `RANA_PUBLIC_KEY` to a public app-restricted key when running `expo prebuild`. The plugin writes it to Android application metadata and iOS Info.plist, and inserts initialization in a Swift Expo AppDelegate. Re-run prebuild after changing the key. The key is packaged in the native app and is not a secret. Existing native values are preserved if the environment variable is absent. The plugin supports the standard Swift Expo AppDelegate launch method; other host layouts must configure iOS manually. Set `configureAppDelegate: false` in plugin options when the host already configures the SDK or uses an unsupported AppDelegate; then configure it manually before creating a map or service.

## Bare native setup

Add `<meta-data android:name="com.ranamaps.API_KEY" android:value="pk_live_..." />` inside the Android application element. In the iOS Swift AppDelegate, import `RanaMapsSDK` and call `try RanaMaps.configure(apiKey: "pk_live_...")` during launch before creating a map or service. Handle configuration errors at startup. Use a public key restricted to the host app; native app bundles do not conceal it. `createClient()` and `createOfflineManager()` use the host key; both also accept an explicit key when needed.

Android's host repositories must include `maven { url 'https://assets.ranamaps.com/maven' }`. For local verification set `RANA_MAVEN_REPOSITORY` to the prepared Maven directory.

Add `pod 'RanaMapsSDK', :podspec => 'https://assets.ranamaps.com/sdk/ios/0.4.0-beta.0/RanaMapsSDK.podspec'` inside the iOS application target, then run pod install. Local consumers can use `:path` with the prepared `RanaMapsSDK` directory; the Expo example accepts `RANA_IOS_BINARY_DIR`. SDK resources/privacy manifests/notices are included in the native archive. Do not link duplicate native copies through another dependency manager.

See the [Expo sample](../react-native/README.md) for an app using the beta.
