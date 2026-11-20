import Foundation
import RanaMapsSDK
import SwiftUI

let defaultPickup = LatLng(lat: 6.6018, lng: 3.3515) // Ikeja, used only when location is denied
let lagosCentre = LatLng(lat: 6.5244, lng: 3.3792)

enum RidePhase { case idle, options, trip, arrived }
enum Movement: String { case simulated = "Simulated", device = "Device GPS" }

struct PlaceRow: Identifiable {
    let id: String
    let name: String
    let secondary: String
    let point: LatLng
}

struct RideOption: Identifiable {
    var id: Mode { mode }
    let mode: Mode
    let route: Route?
    let error: String?

    var title: String { mode == .car ? "Car" : "Okada" }
    var icon: String { mode == .car ? "car.fill" : "bicycle" }
    var durationText: String { route.map { Fmt.duration(Double($0.durationS)) } ?? "n/a" }
    var distanceText: String { route.map { Fmt.distance(Double($0.distanceM)) } ?? "" }
    /// Illustrative estimate only. No booking or payment exists in this sample.
    var priceText: String {
        guard let route else { return "-" }
        let km = Double(route.distanceM) / 1000, min = Double(route.durationS) / 60
        let raw = mode == .car ? 600 + 110 * km + 18 * min : 300 + 70 * km + 9 * min
        let rounded = (raw / 50).rounded() * 50
        return "~\u{20A6}" + (Fmt.grouping.string(from: NSNumber(value: rounded)) ?? "\(Int(rounded))")
    }
    var speed: Double { mode == .car ? 11 : 9 }
}

enum Fmt {
    static let grouping: NumberFormatter = { let f = NumberFormatter(); f.numberStyle = .decimal; return f }()
    static func distance(_ m: Double) -> String { m < 1000 ? "\(Int(m.rounded())) m" : String(format: "%.1f km", m / 1000) }
    static func duration(_ s: Double) -> String {
        let minutes = Int((s / 60).rounded(.up))
        return minutes < 60 ? "\(max(1, minutes)) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
}

@MainActor
final class RideModel: ObservableObject {
    // Idle / search
    @Published var query = ""
    @Published private(set) var results: [PlaceRow] = []
    @Published private(set) var searching = false
    @Published private(set) var searchError: String?

    // Flow
    @Published private(set) var phase: RidePhase = .idle
    @Published private(set) var pickup: LatLng?          // nil until the first fix (or until location is denied)
    @Published private(set) var pickupName = "Waiting for location…"
    @Published private(set) var pickupIsPinned = false   // long-press override
    @Published private(set) var userLocation: LatLng?
    @Published var movement: Movement = .simulated
    @Published private(set) var destinationName = ""
    @Published private(set) var destination: LatLng?
    @Published private(set) var options: [RideOption] = []
    @Published var selectedMode: Mode = .car
    @Published private(set) var loadingRoutes = false
    @Published private(set) var routeError: String?

    // Map state mirrored into the SwiftUI MapSettings (the SDK re-applies them on every SwiftUI update).
    @Published private(set) var mapPadding = MapPadding()
    @Published private(set) var tracking: LocationTracking = .none

    // Trip
    @Published private(set) var routeStatus = LocationRouteStatus(state: .none)
    @Published private(set) var reroutingStatus = ReroutingStatus(state: .disabled)
    @Published private(set) var lastFix: LocationFix?
    @Published private(set) var fixCount = 0
    @Published private(set) var remainingMetres: Double?
    @Published private(set) var remainingIsExact = false
    @Published private(set) var etaSeconds: Double?
    @Published private(set) var nextManeuver: (text: String, metres: Double)?
    @Published private(set) var hostRouteIsWrong = false
    @Published private(set) var hostRouteLabel = "Correct route"
    @Published private(set) var loadingWrongRoute = false
    @Published private(set) var autoReroute = false
    @Published private(set) var interval: TimeInterval = 5
    @Published private(set) var silentUntil: Date?
    @Published private(set) var reroutes = 0
    @Published var banner: String?

    let socket = FakeLocationSocket()
    private let permission = LocationPermission()
    private var locationDenied = false
    private var map: RanaMapController?
    private var client: RanaClient?
    private var searchTask: Task<Void, Never>?
    private var routeTask: Task<Void, Never>?
    private var wrongTask: Task<Void, Never>?

    private var pickupMarker: RanaMarker?
    private var destMarker: RanaMarker?
    private var lines: [RanaRouteLine] = []      // option / real route lines
    private var hostLine: RanaRouteLine?          // dashed line = route currently handed to the SDK when it differs

    private var tripMode: Mode = .car
    private var tripRoute: Route?                 // the route the simulated driver really follows
    private var driverTrack: [LatLng] = []
    private var activeRoute: Route?               // what the host passed to setLocationRoute
    private var activePath: [LatLng] = []
    private var activeLength = 0.0
    private var activeStepStarts: [(start: Double, text: String)] = []

    var selectedOption: RideOption? { options.first { $0.mode == selectedMode } }

    // MARK: Map attach

    func attach(_ controller: RanaMapController) {
        map = controller
        permission.onChange = { [weak self] granted in
            Task { @MainActor in self?.permissionChanged(granted) }
        }
        permission.request()
        socket.onMessage = { [weak self] text in self?.receive(text) }
        socket.onFinished = { [weak self] in self?.arrived() }
        controller.setPadding(mapPadding)
    }

    // MARK: Location

    private func permissionChanged(_ granted: Bool) {
        if granted {
            locationDenied = false
            if banner?.hasPrefix("Location off") == true { banner = nil }
            connectDeviceProvider()
        } else {
            locationDenied = true
            banner = "Location off — using Lagos"
            if pickup == nil { setPickup(defaultPickup, name: "Ikeja, Lagos (default pickup)", pinned: false); map?.move(to: defaultPickup, zoom: 14) }
        }
    }

    private func connectDeviceProvider() {
        guard !locationDenied else { return }
        map?.setLocationProvider(ObservedLocationProvider { [weak self] fix in self?.deviceFix(fix) })
    }

    private func deviceFix(_ fix: LocationFix) {
        userLocation = fix.point
        if !pickupIsPinned, phase == .idle || pickup == nil { setPickup(fix.point, name: "Current location", pinned: false) }
        guard phase == .trip, movement == .device else { return }
        lastFix = fix; fixCount += 1
        refreshStatus()
        if let remaining = remainingMetres, remaining < 25 { arrived() }
    }

    /// Recenter: follow, or follow-heading during a trip.
    func recenter() { setTracking(phase == .trip ? .followHeading : .follow) }

    func setSheetInset(top: Double, bottom: Double) {
        let padding = MapPadding(top: top, bottom: bottom)
        guard padding != mapPadding else { return }
        mapPadding = padding
        map?.setPadding(padding)
    }

    func setTracking(_ value: LocationTracking) {
        tracking = value
        map?.setTracking(value)
    }

    func trackingChangedByMap(_ value: LocationTracking) { if tracking != value { tracking = value } }

    private func rana() throws -> RanaClient {
        if let client { return client }
        let created = try RanaClient()
        client = created
        return created
    }

    private func describe(_ error: Error) -> String { (error as? RanaError)?.description ?? error.localizedDescription }

    // MARK: Search

    func queryChanged() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { results = []; searching = false; searchError = nil; return }
        searching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled else { return }
            do {
                let found = try await self.rana().places.autocomplete(text, near: self.pickup ?? defaultPickup, limit: 8)
                guard !Task.isCancelled else { return }
                self.results = found.map { PlaceRow(id: $0.placeId, name: $0.name, secondary: $0.secondary, point: $0.point) }
                self.searchError = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.results = []
                self.searchError = self.describe(error)
            }
            self.searching = false
        }
    }

    func choose(_ place: PlaceRow) {
        guard pickup != nil else { return }
        searchTask?.cancel()
        query = ""; results = []; searching = false
        destination = place.point; destinationName = place.name
        phase = .options
        syncPickupMarker()
        loadRoutes()
    }

    func setPickup(_ point: LatLng, name: String, pinned: Bool) {
        guard phase == .idle || phase == .options else { return }
        pickup = point; pickupName = name; pickupIsPinned = pinned
        syncPickupMarker()
        if phase == .options { loadRoutes() }
    }

    /// The live location dot already marks an unpinned pickup while idle; an "A" pin there would hide it.
    private func syncPickupMarker() {
        guard let pickup, pickupIsPinned || phase != .idle else { pickupMarker?.remove(); pickupMarker = nil; return }
        if let pickupMarker { pickupMarker.setPosition(pickup) }
        else { pickupMarker = map?.addMarker(at: pickup, content: .pin(label: "A")) }
    }

    /// Back to the live device location (or the default point when location is off).
    func resetPickup() {
        if let userLocation, !locationDenied { setPickup(userLocation, name: "Current location", pinned: false) }
        else { setPickup(defaultPickup, name: "Ikeja, Lagos (default pickup)", pinned: false) }
    }

    func longPress(_ point: LatLng) {
        setPickup(point, name: String(format: "Pin at %.4f, %.4f", point.lat, point.lng), pinned: true)
    }

    // MARK: Ride options

    func loadRoutes() {
        guard let destination, let origin = pickup else { return }
        routeTask?.cancel()
        loadingRoutes = true; routeError = nil; options = []
        routeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let client = try self.rana()
                async let car = Self.fetch(client, .car, origin, destination)
                async let okada = Self.fetch(client, .okada, origin, destination)
                let both = await [car, okada]
                guard !Task.isCancelled else { return }
                self.options = both
                if self.selectedOption?.route == nil, let ok = both.first(where: { $0.route != nil }) { self.selectedMode = ok.mode }
                if both.allSatisfy({ $0.route == nil }) { self.routeError = both.compactMap(\.error).first ?? "No route found." }
                self.drawOptions(fit: true)
            } catch {
                guard !Task.isCancelled else { return }
                self.routeError = self.describe(error)
            }
            self.loadingRoutes = false
        }
    }

    private nonisolated static func fetch(_ client: RanaClient, _ mode: Mode, _ from: LatLng, _ to: LatLng) async -> RideOption {
        do {
            let result = try await client.directions(origin: .point(from), destination: .point(to), mode: mode)
            guard let route = result.routes.first else { return RideOption(mode: mode, route: nil, error: "No \(mode.rawValue) route.") }
            return RideOption(mode: mode, route: route, error: nil)
        } catch {
            return RideOption(mode: mode, route: nil, error: (error as? RanaError)?.description ?? error.localizedDescription)
        }
    }

    func select(_ mode: Mode) {
        guard options.first(where: { $0.mode == mode })?.route != nil else { return }
        selectedMode = mode
        drawOptions(fit: false)
    }

    private func clearLines() { lines.forEach { $0.remove() }; lines = []; hostLine?.remove(); hostLine = nil }

    func drawOptions(fit: Bool) {
        guard let map else { return }
        clearLines()
        destMarker?.remove(); destMarker = nil
        guard phase == .options else { return }
        for option in options where option.mode != selectedMode {
            if let route = option.route { lines.append(map.addPolyline(route.points, options: PolylineOptions(preset: .alternative))) }
        }
        if let route = selectedOption?.route { lines.append(map.addPolyline(route.points, options: PolylineOptions(mode: selectedMode, arrows: false))) }
        if let destination { destMarker = map.addMarker(at: destination, content: .pin(label: "B")) }
        if fit, let route = selectedOption?.route { map.fit(route.points, padding: 48) }
        else if fit, let destination, let pickup { map.fit([pickup, destination], padding: 48) }
    }

    func backToSearch() {
        routeTask?.cancel()
        clearLines(); destMarker?.remove(); destMarker = nil
        options = []; destination = nil; destinationName = ""; loadingRoutes = false; routeError = nil
        phase = .idle; syncPickupMarker()
        if let pickup { map?.move(to: pickup, zoom: 15) }
    }

    // MARK: Trip

    func confirmRide() {
        guard let option = selectedOption, let route = option.route, let map else { return }
        routeTask?.cancel()
        tripMode = option.mode; tripRoute = route; driverTrack = route.points
        phase = .trip
        hostRouteIsWrong = false; hostRouteLabel = "Correct route"
        reroutes = 0; fixCount = 0; lastFix = nil; silentUntil = nil
        clearLines()
        lines.append(map.addPolyline(route.points, options: PolylineOptions(mode: tripMode, arrows: false)))
        installRoute(route, path: route.points)
        setTracking(.followHeading)
        if movement == .simulated {
            map.setLocationProvider(nil)   // one source at a time
            socket.interval = interval
            socket.connect(track: driverTrack, speed: option.speed)
        }
        refreshStatus()
    }

    /// `setLocationRoute` also clears automatic rerouting, so it is always re-armed right after.
    private func installRoute(_ route: Route?, path: [LatLng]) {
        activeRoute = route; activePath = path
        activeLength = Geo.length(path)
        var start = 0.0
        activeStepStarts = (route?.legs.flatMap(\.steps) ?? []).map { step in
            defer { start += Double(step.distanceM) }
            return (start, step.instruction)
        }
        map?.setLocationRoute(path)
        installRerouting()
    }

    private func installRerouting() {
        guard let map else { return }
        if autoReroute, let destination {
            do {
                map.setAutomaticRerouting(ReroutingOptions(destination: .point(destination), mode: tripMode),
                                          provider: DirectionsReroutingProvider(client: try rana()))
            } catch { banner = describe(error) }
        } else {
            map.setAutomaticRerouting(nil)
        }
        reroutingStatus = map.reroutingStatus
    }

    func setAutoReroute(_ on: Bool) {
        autoReroute = on
        if phase == .trip { installRerouting() }
    }

    func setInterval(_ seconds: TimeInterval) {
        interval = seconds
        socket.interval = seconds
    }

    func dropUpdates(seconds: TimeInterval) {
        socket.dropMessages(forSeconds: seconds)
        silentUntil = socket.silentUntil
    }

    private func receive(_ text: String) {
        guard phase == .trip, let data = text.data(using: .utf8), let frame = try? JSONDecoder().decode(SocketFrame.self, from: data) else { return }
        let fix = frame.locationFix()
        lastFix = fix; fixCount += 1
        map?.updateLocation(fix)
        refreshStatus()
    }

    func refreshStatus() {
        guard let map else { return }
        routeStatus = map.locationRouteStatus
        reroutingStatus = map.reroutingStatus
        guard phase == .trip || phase == .arrived else { return }
        let progress = routeStatus.state == .matched ? routeStatus.progressMetres : nil
        if let progress {
            remainingMetres = max(0, activeLength - progress); remainingIsExact = true
        } else if let fix = lastFix, let destination {
            remainingMetres = Geo.distance(fix.point, destination); remainingIsExact = false
        }
        let avg: Double = {
            if let r = activeRoute, r.durationS > 0 { return Double(r.distanceM) / Double(r.durationS) }
            return tripMode == .car ? 11 : 9
        }()
        etaSeconds = remainingMetres.map { $0 / max(1, avg) }
        if let progress, let next = activeStepStarts.first(where: { $0.start > progress + 1 }) {
            nextManeuver = (next.text, next.start - progress)
        } else {
            nextManeuver = nil
        }
    }

    func routeChangedByMap() { refreshStatus() }

    func reroutingChangedByMap(_ status: ReroutingStatus) {
        reroutingStatus = status
        if let error = status.error { banner = "Rerouting: \(error.description)" }
    }

    func rerouted(_ result: ReroutingResult) {
        reroutes += 1
        activeRoute = result.route; activePath = result.path; activeLength = Geo.length(result.path)
        var start = 0.0
        activeStepStarts = (result.route?.legs.flatMap(\.steps) ?? []).map { step in defer { start += Double(step.distanceM) }; return (start, step.instruction) }
        hostRouteIsWrong = true; hostRouteLabel = "Rerouted by SDK (dashed)"
        drawHostLine(result.path)
        refreshStatus()
    }

    private func drawHostLine(_ path: [LatLng]) {
        hostLine?.remove()
        hostLine = map?.addPolyline(path, options: PolylineOptions(preset: .alternative, dash: .dashed, opacity: 0.9))
    }

    // MARK: Scenarios

    /// Host deliberately hands the SDK a different route while the socket keeps emitting the real track.
    func applyWrongRoute() {
        guard phase == .trip, !loadingWrongRoute, let destination else { return }
        loadingWrongRoute = true
        wrongTask?.cancel()
        let track = driverTrack, mode = tripMode
        let other: Mode = mode == .car ? .okada : .car
        let otherRoute = options.first { $0.mode == other }?.route
        let from = lastFix?.point ?? track.first ?? pickup ?? defaultPickup
        wrongTask = Task { [weak self] in
            guard let self else { return }
            var wrong: Route?
            var label = ""
            if let otherRoute, Geo.maxDeviation(of: otherRoute.points, from: track) > 40 {
                wrong = otherRoute; label = "WRONG: \(other == .car ? "Car" : "Okada") route"
            } else {
                // Same geometry for both modes: route to a different nearby destination instead.
                let decoy = Geo.offset(destination, eastMetres: 1800, northMetres: -1400)
                do {
                    let result = try await self.rana().directions(origin: .point(from), destination: .point(decoy), mode: mode)
                    wrong = result.routes.first; label = "WRONG: route to another destination"
                } catch { self.banner = "Wrong route request failed: \(self.describe(error))" }
            }
            guard !Task.isCancelled else { return }
            if let wrong {
                self.installRoute(wrong, path: wrong.points)
                self.drawHostLine(wrong.points)
                self.hostRouteIsWrong = true; self.hostRouteLabel = label
                self.refreshStatus()
            }
            self.loadingWrongRoute = false
        }
    }

    func restoreRoute() {
        guard phase == .trip, let route = tripRoute else { return }
        wrongTask?.cancel(); loadingWrongRoute = false
        hostLine?.remove(); hostLine = nil
        installRoute(route, path: route.points)
        hostRouteIsWrong = false; hostRouteLabel = "Correct route"
        refreshStatus()
    }

    // MARK: End

    private func arrived() {
        guard phase == .trip else { return }
        phase = .arrived
        refreshStatus()
        remainingMetres = 0; etaSeconds = 0; nextManeuver = nil
    }

    func endTrip() {
        socket.disconnect()
        wrongTask?.cancel()
        map?.setAutomaticRerouting(nil)
        map?.setLocationRoute(nil)
        setTracking(.none)
        map?.hideUserLocation()
        connectDeviceProvider()
        clearLines(); destMarker?.remove(); destMarker = nil
        phase = .idle; syncPickupMarker()
        destination = nil; destinationName = ""; options = []
        tripRoute = nil; activeRoute = nil; driverTrack = []; activePath = []
        lastFix = nil; remainingMetres = nil; etaSeconds = nil; nextManeuver = nil; silentUntil = nil
        hostRouteIsWrong = false; loadingWrongRoute = false
        routeStatus = LocationRouteStatus(state: .none)
        reroutingStatus = map?.reroutingStatus ?? ReroutingStatus(state: .disabled)
        if let pickup { map?.move(to: pickup, zoom: 15) }
    }

    func detach() { socket.disconnect(); map = nil }
}
