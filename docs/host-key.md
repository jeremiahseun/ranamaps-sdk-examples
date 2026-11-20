# Configure a mobile map key

The host app supplies one app-restricted public Rana key for its native maps. Configure it once for Android and iOS, then create map views without a key argument. Android uses the app package name and signing certificate. iOS uses the bundle identifier. Use a public `pk_live_` key with the scopes needed by the app.

## Android

Add the following inside the host application's `<application>` element in `AndroidManifest.xml`:

```xml
<meta-data
    android:name="com.ranamaps.API_KEY"
    android:value="${ranaPublicKey}" />
```

Populate the placeholder in the host app's Gradle build:

```kotlin
android {
    defaultConfig {
        manifestPlaceholders["ranaPublicKey"] =
            providers.environmentVariable("RANA_PUBLIC_KEY").orElse("").get()
    }
}
```

Set `RANA_PUBLIC_KEY` for the build. For Play distribution, restrict the key to the Play App Signing certificate. A debug app usually needs a different certificate restriction. Rebuild the host when updating its manifest value.

## iOS

Add `RanaMapsAPIKey` to the app's Info.plist and set its value to `$(RANA_PUBLIC_KEY)`. Supply that build setting from the app's local or CI configuration. In the host's existing `AppDelegate`, call the SDK during `application(_:didFinishLaunchingWithOptions:)` before mounting a Rana map:

```swift
import RanaMapsSDK

// Inside application(_:didFinishLaunchingWithOptions:)
if let key = Bundle.main.object(forInfoDictionaryKey: "RanaMapsAPIKey") as? String {
    do {
        try RanaMaps.configure(apiKey: key)
    } catch {
        // Route the configuration failure to the host app's error handling.
        NSLog("Rana Maps configuration failed.")
    }
}
```

Handle the thrown `RanaError` in the app's startup flow. If the app uses the SwiftUI lifecycle, register its delegate with `@UIApplicationDelegateAdaptor`. Configuring the same key again is safe. A different key requires a new process.

## Migrate map call sites

| SDK | Change |
| --- | --- |
| Android | Remove `key` from Compose `RanaMap` and use the host-configured `RanaMapView.start` overload for native views. |
| iOS | Remove `key` from SwiftUI `RanaMap` and use the host-configured UIKit map entry point. |
| Flutter | Remove `apiKey` from `RanaMap`. Configure the Android and iOS Runner targets before running the app. |
| React Native | Remove `apiKey` from `RanaMap`. Set up the native app targets, or follow the package's Expo config plugin instructions and regenerate the native app. |

For Android services and offline regions, use `RanaClient(context)` and `RanaOfflineManager(context)`. On iOS, use `try RanaClient()` and `try RanaOfflineManager()`. In Flutter, call `RanaClient.createConfigured()` and `RanaOfflineManager.createConfigured()`. In React Native, call `createClient()` and `createOfflineManager()`. Explicit public keys remain available for independently scoped service clients. A map and an offline manager in the same process use the same renderer credential.

An absent host key reports `missing_api_key`. A malformed setup value reports `invalid_api_key` during Android resolution or the iOS configuration call. A second, different iOS startup key reports `conflicting_api_key`. Renderer conflicts with an explicitly keyed offline manager report `map_credential_conflict`.

These instructions apply to the upcoming mobile SDK release. The previous preview packages still use their original map key arguments.

© Rana Maps © OpenStreetMap
