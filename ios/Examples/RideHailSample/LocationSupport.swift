import CoreLocation
import RanaMapsSDK

/// Owns the foreground permission prompt (the SDK's native provider never asks).
final class LocationPermission: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    /// true = granted, false = denied/restricted. Not called while undetermined.
    var onChange: ((Bool) -> Void)?

    override init() { super.init(); manager.delegate = self }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: report()
        }
    }

    private func report() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: onChange?(true)
        case .denied, .restricted: onChange?(false)
        default: break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { report() }
}

/// Native provider that also tells the app about every fix (and forwards heading).
@MainActor
final class ObservedLocationProvider: RanaLocationProvider, RanaHeadingProvider {
    private let native = NativeLocationProvider()
    private let onFix: @MainActor (LocationFix) -> Void

    init(onFix: @escaping @MainActor (LocationFix) -> Void) { self.onFix = onFix }

    func start(onLocation: @escaping @MainActor (LocationFix) -> Void, onError: @escaping @MainActor (RanaError) -> Void) {
        native.start(onLocation: { [onFix] fix in onLocation(fix); onFix(fix) }, onError: onError)
    }
    func stop() { native.stop() }
    func startHeading(onHeading: @escaping @MainActor (HeadingFix) -> Void) { native.startHeading(onHeading: onHeading) }
    func stopHeading() { native.stopHeading() }
}
