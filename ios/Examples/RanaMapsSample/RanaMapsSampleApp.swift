import CoreLocation
import RanaMapsSDK
import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        do { try RanaMaps.configure(apiKey: ProcessInfo.processInfo.environment["RANA_KEY"] ?? Bundle.main.object(forInfoDictionaryKey: "RanaMapsAPIKey") as? String ?? "pk_live_replace_me") }
        catch { print("Rana Maps configuration failed: \((error as? RanaError)?.code ?? "unknown")") }
        return true
    }
}

@main
struct RanaMapsSampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { WindowGroup { JourneyScreen() } }
}
private enum DemoPhase { case explore, preview, running, paused, arrived }
private let pickup = LatLng(lat: 6.5095, lng: 3.3711)
private let destinations: [(String, LatLng)] = [("Ikeja", LatLng(lat: 6.6018, lng: 3.3515)), ("Marina", LatLng(lat: 6.45, lng: 3.39)), ("Corner demo", LatLng(lat: 6.5125, lng: 3.3726))]

@MainActor
private final class ReplayLocationProvider: RanaLocationProvider {
    private var callback: (@MainActor (LocationFix) -> Void)?
    func start(onLocation: @escaping @MainActor (LocationFix) -> Void, onError: @escaping @MainActor (RanaError) -> Void) { callback = onLocation }
    func stop() { callback = nil }
    private var timestamp = Date.distantPast
    func send(_ point: LatLng, course: Double = 0) {
        timestamp = max(Date(), timestamp.addingTimeInterval(0.000001))
        callback?(LocationFix(point: point, accuracyMetres: 8, heading: course, timestamp: timestamp))
    }
}

@MainActor
private final class JourneyModel: ObservableObject {
    @Published var phase: DemoPhase = .explore
    @Published var name = ""
    @Published var mode: Mode = .car
    @Published var progress = 0.0
    @Published var night = false
    @Published var tilted = false
    @Published var tools = false
    @Published var smooth = true
    @Published var routeAware = true
    @Published var tracePreview = false
    @Published var traceStatus = "Trace preview: off"
    private var traceRecorder: JourneyTraceRecorder?
    @Published var automaticRerouting = false
    @Published var reroutingState = "Disabled"
    @Published var reroutingRequests = 0
    private var publicKey = "pk_live_replace_me"
    @Published var detour = false
    @Published var routeState = "None"
    @Published var phoneHeading = 0.0
    @Published var showLayers = false
    @Published var creditRight = false
    @Published var liveRoute = false
    @Published var busy = false
    @Published var message = "Tap a destination or drop a pin. Journeys use sample data."
    private(set) var path: [LatLng] = []
    private var map: RanaMapController?
    private var line: RanaRouteLine?
    private var destinationPin: RanaMarker?
    private let provider = ReplayLocationProvider()
    private var routeGeneration = 0
    private var timer: Task<Void, Never>?
    private var shapes: [RanaShape] = []
    private var sampleImage: RanaMarker?
    private var points: RanaPointsOverlay?
    private var dataSource: RanaGeoJsonSource?
    private var dataLayer: RanaStyleLayer?
    private var manager: RanaOfflineManager?
    private var pack: RanaOfflineRegion?

    func attach(_ map: RanaMapController, key: String) {
        publicKey = key
        self.map = map
        map.setLocationProvider(provider)
        map.onTap { [weak self] point in self?.select("Dropped pin", point) }
        let button = UIButton(type: .system)
        button.setTitle("Pickup", for: .normal); button.backgroundColor = .systemBackground
        button.frame = CGRect(x: 0, y: 0, width: 90, height: 36)
        button.addAction(UIAction { [weak self] _ in self?.message = "Sample pickup. No booking is created." }, for: .touchUpInside)
        map.addMarker(at: pickup, content: .view(button))
        fit(); redrawRoute(); redrawLayers()
    }
    func select(_ name: String, _ point: LatLng) {
        routeGeneration += 1; timer?.cancel(); self.name = name; progress = 0; phase = .preview; liveRoute = false
        path = name == "Corner demo" ? [pickup, LatLng(lat: 6.511, lng: 3.3711), LatLng(lat: 6.511, lng: 3.3726), point] : [pickup, LatLng(lat: (pickup.lat + point.lat) / 2, lng: (pickup.lng + point.lng) / 2 + 0.003), point]
        map?.setTracking(.none); configureTrace(); redrawRoute(); fit()
    }
    func changeMode(_ mode: Mode) { self.mode = mode; if let end = path.last { select(name, end) } }
    func configureRoute() {
        map?.setLocationRoute(routeAware && path.count >= 2 ? path : nil)
        configureRerouting()
        emitLocation()
    }
    func configureTrace() {
        map?.setJourneyTraceRecorder(nil); traceRecorder=nil
        guard tracePreview, path.count >= 2, let map else { traceStatus="Trace preview: off";return }
        do {
            let recorder=JourneyTraceRecorder(client:try RanaClient(key:publicKey),options:JourneyTraceOptions(consent:true,source:.simulated,mode:mode)) { [weak self] status in
                Task { @MainActor in await Task.yield();self?.traceStatus=status.stopped ? "Trace preview: off" : "Simulated trace: \(status.buffered) buffered · \(status.uploaded) learned\(status.error.map { " · \($0.code)" } ?? "")" }
            }
            traceRecorder=recorder;map.setJourneyTraceRecorder(recorder)
        } catch {message=error.localizedDescription}
    }
    func validateTrace() { Task { do {guard (traceRecorder?.status.buffered ?? 0) >= 2 else {message="Start simulation to collect at least two fixes.";return};try await traceRecorder?.flush();message="Trace batch validated. Simulated fixes are never learned."} catch {message=error.localizedDescription} } }
    func configureRerouting() {
        guard let map else { return }
        do {
            if automaticRerouting, routeAware, path.count >= 2, let end = path.last {
                map.setAutomaticRerouting(ReroutingOptions(destination: .point(end), mode: mode), provider: DirectionsReroutingProvider(client: try RanaClient(key: publicKey)))
            } else { map.setAutomaticRerouting(nil) }
        } catch { message = error.localizedDescription }
        refreshReroutingStatus()
    }
    func refreshReroutingStatus() {
        guard let status = map?.reroutingStatus else { return }
        reroutingState = String(describing: status.state); reroutingRequests = status.requestsMade
        if let error = status.error { message = error.description }
    }
    func acceptedReroute(_ result: ReroutingResult) {
        routeGeneration += 1; path = result.path; detour = false; progress = 0; liveRoute = true
        redrawRoute(installMovement: false)
        message = "Automatic reroute loaded. Movement remains simulated."
    }
    func redrawRoute(installMovement: Bool = true) {
        if installMovement { configureRoute() }
        line?.remove(); destinationPin?.remove()
        line = nil; destinationPin = nil
        guard let map, path.count >= 2 else { return }
        line = map.addPolyline(path, options: PolylineOptions(mode: mode, arrows: true, progress: progress))
        destinationPin = map.addMarker(at: path.last!, content: .pin(label: "B"), style: MarkerStyle(draggable: true))
        updateProgress(progress)
    }
    func updateProgress(_ value: Double) {
        progress = min(1, max(0, value)); line?.setProgress(progress)
        emitLocation()
        if progress >= 1 { phase = .arrived; timer?.cancel() } else if phase == .arrived { phase = .paused }
    }
    func togglePlayback() {
        timer?.cancel()
        if phase == .running { phase = .paused; return }
        if progress >= 1 { updateProgress(0) }
        phase = .running; recenter()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 600_000_000) } catch { return }
                guard let self, self.phase == .running else { return }
                self.updateProgress(self.progress + 0.01)
            }
        }
    }
    func pointAt(_ fraction: Double) -> LatLng {
        guard !path.isEmpty else { return pickup }
        let segments = zip(path, path.dropFirst()).map { a, b in hypot(b.lat - a.lat, (b.lng - a.lng) * cos((a.lat + b.lat) * .pi / 360)) }
        var remaining = segments.reduce(0, +) * min(1, max(0, fraction))
        for (index, length) in segments.enumerated() {
            if remaining <= length, length > 0 { let t = remaining / length, a = path[index], b = path[index + 1]; return LatLng(lat: a.lat + (b.lat - a.lat) * t, lng: a.lng + (b.lng - a.lng) * t) }
            remaining -= length
        }
        return path.last!
    }
    func emitLocation() {
        let a = pointAt(max(0, progress - 0.001)), b = pointAt(min(1, progress + 0.001))
        let course = (atan2((b.lng - a.lng) * cos((a.lat + b.lat) * .pi / 360), b.lat - a.lat) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let point = pointAt(progress)
        let radians = course * .pi / 180
        provider.send(detour ? LatLng(lat: point.lat - sin(radians) * 0.0008, lng: point.lng + cos(radians) * 0.0008 / cos(point.lat * .pi / 180)) : point, course: course)
        switch map?.locationRouteStatus.state {
        case .matched: routeState = "Matched"
        case .offRoute: routeState = "Off route"
        case .uncertain: routeState = "Uncertain"
        default: routeState = "None"
        }
        if mode == .walk { map?.updateDeviceHeading(HeadingFix(heading: phoneHeading, accuracyDegrees: 5)) }
    }
    func recenter() { map?.setTracking(.followHeading); emitLocation() }
    func rotatePhone() { phoneHeading = (phoneHeading + 45).truncatingRemainder(dividingBy: 360); map?.updateDeviceHeading(HeadingFix(heading: phoneHeading, accuracyDegrees: 5)) }
    func fit() { map?.fit(path.isEmpty ? [pickup] + destinations.map(\.1) : path) }
    func reset() {
        tracePreview = false; map?.setJourneyTraceRecorder(nil); traceRecorder=nil; automaticRerouting = false; detour = false
        routeGeneration += 1; timer?.cancel(); phase = .explore; path = []; name = ""; progress = 0; liveRoute = false
        map?.setTracking(.none); redrawRoute(); map?.hideUserLocation(); fit()
    }
    func redrawLayers() {
        sampleImage?.remove(); sampleImage = nil
        points?.remove(); shapes.forEach { $0.remove() }; dataLayer?.remove(); try? dataSource?.remove()
        points = nil; shapes = []; dataLayer = nil; dataSource = nil
        guard showLayers, let map else { return }
        if let bicycle = UIImage(systemName: "bicycle.circle.fill")?.withTintColor(.systemBlue, renderingMode: .alwaysOriginal) {
            sampleImage = map.addMarker(at: LatLng(lat: 6.53, lng: 3.40), content: .image(bicycle, anchor: .center))
        }
        points = map.addPoints([LatLng(lat: 6.53, lng: 3.38), LatLng(lat: 6.531, lng: 3.381), LatLng(lat: 6.55, lng: 3.37)])
        shapes.append(map.addCircle(center: pickup, radiusMetres: 350, options: ShapeOptions(label: "350 m")))
        shapes.append(map.addPolygon([[LatLng(lat: 6.54, lng: 3.38), LatLng(lat: 6.55, lng: 3.38), LatLng(lat: 6.55, lng: 3.39), LatLng(lat: 6.54, lng: 3.39)]], options: ShapeOptions(style: .avoid)))
        do {
            dataSource = try map.addGeoJsonSource(id: "demo-deliveries", geoJson: #"{"type":"FeatureCollection","features":[{"type":"Feature","geometry":{"type":"Point","coordinates":[3.39,6.56]},"properties":{"status":"late"}}]}"#)
            dataLayer = try map.addLayer(id: "demo-dots", sourceId: "demo-deliveries", options: DataLayerOptions(kind: .circle, color: .match(property: "status", cases: ["late": .color("#C4373F")], fallback: .color("#ECA824"))))
        } catch { message = (error as? RanaError)?.description ?? error.localizedDescription }
    }
    func loadLive(key: String) async {
        guard let end = path.last, !busy else { return }
        busy = true; defer { busy = false }
        routeGeneration += 1; let request = routeGeneration
        do {
            let client = try RanaClient(key: key)
            let response = try await client.directions(origin: .point(pickup), destination: .point(end), mode: mode)
            guard request == routeGeneration else { return }
            guard let route = response.routes.first else { message = "No route returned. Try another destination."; return }
            timer?.cancel(); path = route.points; progress = 0; phase = .preview; liveRoute = true
            redrawRoute(); fit(); message = "Live directions loaded. Movement remains simulated."
        } catch is CancellationError {} catch { if request == routeGeneration { message = "Directions failed: \((error as? RanaError)?.description ?? error.localizedDescription)" } }
    }
    func download(key: String) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let manager = self.manager ?? RanaOfflineManager(key: key); self.manager = manager
            let id = night ? "demo-night" : "demo-day"
            let saved = try await manager.regions()
            let region: RanaOfflineRegion
            if let existing = saved.first(where: { $0.id == id }) { region = existing }
            else { region = try await manager.createRegion(OfflineRegionOptions(id: id, bounds: CameraBounds(southWest: LatLng(lat: 6.49, lng: 3.35), northEast: LatLng(lat: 6.54, lng: 3.40)), style: night ? .night : .day, minZoom: 8, maxZoom: 13, maxBytes: 20 * 1024 * 1024)) }
            pack?.pause(); pack?.observe(onProgress: nil); pack = region
            region.observe(onProgress: { [weak self] progress in self?.message = progress.complete ? "Offline pack ready." : "Offline download: \(progress.completedResources) resources" }, onError: { [weak self] error in self?.message = error.description })
            region.resume()
        } catch is CancellationError {} catch { message = "Download failed: \((error as? RanaError)?.description ?? error.localizedDescription)" }
    }
    func deleteDownload() async {
        guard !busy, let region = pack else { return }; busy = true; defer { busy = false }
        do { try await region.remove(); pack = nil; message = "Offline pack deleted." }
        catch is CancellationError {}
        catch { message = "Deletion failed. The pack is paused; retry or resume. \(error.localizedDescription)" }
    }
    func pauseDownload() { pack?.observe(onProgress: nil); pack?.pause(); message = "Offline download paused." }
    func detach() { timer?.cancel(); if phase == .running { phase = .paused }; pack?.pause(); pack?.observe(onProgress: nil); provider.stop(); map?.setLocationProvider(nil); map = nil }
    deinit { timer?.cancel() }
}

private struct DemoFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, latest in latest }) }
}
private extension View {
    func demoFrame(_ name: String) -> some View { background(GeometryReader { proxy in Color.clear.preference(key: DemoFrames.self, value: [name: proxy.frame(in: .named("demo"))]) }) }
}
private struct JourneyScreen: View {
    @StateObject private var model = JourneyModel()
    @State private var sheetHeight: CGFloat = 300
    @GestureState private var sheetTranslation: CGFloat = 0
    @State private var headerHeight: CGFloat = 76
    private var key: String { (try? RanaMaps.apiKey()) ?? "" }

    var body: some View {
        GeometryReader { geometry in
            let bottomInset = geometry.safeAreaInsets.bottom
            let availableHeight = geometry.size.height + bottomInset
            let maxSheet = max(220, availableHeight - headerHeight - 140)
            let visibleHeight = min(maxSheet, max(220, sheetHeight - sheetTranslation))
            let padding = MapPadding(top: geometry.safeAreaInsets.top + headerHeight, bottom: visibleHeight)
            ZStack(alignment: .bottom) {
                RanaMap(style: model.night ? .night : .day, center: pickup, zoom: 12,
                        controls: ControlsOptions(zoom: .topRight),
                        settings: MapSettings(camera: CameraOptions(pitch: model.tilted ? 35 : 0), padding: padding, location: LocationOptions(appearance: .puck, motion: model.smooth ? .smooth : .direct, activity: model.mode == .walk ? .walking : .vehicle),
                            events: MapEvents(onError: { [weak journey = model] in journey?.message = $0.description }, onMarkerDrag: { [weak journey = model] _, point, phase in if phase == .ended { journey?.select("Dropped pin", point) } }, onReroutingChanged: { [weak journey = model] _ in Task { @MainActor in await Task.yield(); journey?.refreshReroutingStatus() } }, onRerouted: { [weak journey = model] result in journey?.acceptedReroute(result) }),
                            attribution: AttributionOptions(corner: model.creditRight ? .bottomRight : .bottomLeft)), onReady: { model.attach($0, key: key) })
                    .ignoresSafeArea()
                VStack { header.demoFrame("header"); Spacer() }
                sheet(maxSheet: maxSheet, bottomInset: bottomInset, visibleHeight: visibleHeight)
                    .frame(height: visibleHeight)
                    .background(Color(uiColor: .systemBackground), in: UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("journey-sheet")
            }
            .frame(width: geometry.size.width, height: availableHeight)
            .ignoresSafeArea(.container, edges: .bottom)
            .coordinateSpace(name: "demo")
            .onPreferenceChange(DemoFrames.self) { frames in
                if let height = frames["header"]?.height, abs(headerHeight - height) > 0.5 { headerHeight = height }
            }
        }
        .preferredColorScheme(model.night ? .dark : .light)
        .onChange(of: model.progress) { _, value in model.updateProgress(value) }
        .task(id: "\(model.mode)-\(model.smooth)") { await Task.yield(); model.emitLocation() }
        .onChange(of: model.tracePreview) { _, _ in model.configureTrace() }
        .onChange(of: model.automaticRerouting) { _, _ in model.configureRerouting() }
        .onChange(of: model.routeAware) { _, _ in model.configureRoute() }
        .onChange(of: model.detour) { _, _ in model.emitLocation() }
        .onChange(of: model.showLayers) { _, _ in model.redrawLayers() }
        .onDisappear { model.detach() }
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading) { Text("Explore Lagos").font(.title2.bold()); Text("Demo trip · replayed location").font(.caption) }
            Spacer()
            Button(model.night ? "Day" : "Night") { model.night.toggle() }
            Button(model.tilted ? "2D" : "3D") { model.tilted.toggle() }
        }.buttonStyle(.bordered).padding().background(Color(uiColor: .systemBackground))
    }
    private func sheet(maxSheet: CGFloat, bottomInset: CGFloat, visibleHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack {
                Capsule().fill(.secondary).frame(width: 32, height: 4)
                Button(visibleHeight < 400 ? "Expand" : "Collapse") { sheetHeight = visibleHeight < 400 ? maxSheet : 260; model.fit() }
                Spacer(); Button(model.tools ? "Trip" : "Map tools") { model.tools.toggle(); sheetHeight = min(maxSheet, 460) }
            }.padding(.horizontal, 20).frame(height: 48).contentShape(Rectangle())
                .accessibilityIdentifier("journey-sheet-handle")
                .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("demo"))
                    .updating($sheetTranslation) { value, translation, _ in translation = value.translation.height }
                    .onEnded { value in
                        sheetHeight = min(maxSheet, max(220, sheetHeight - value.translation.height))
                        if model.phase != .running { model.fit() }
                    })
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).font(.title2.bold())
                    Text(model.liveRoute ? "Live route · simulated movement · no booking" : "Illustrative route · simulated movement · no booking").font(.caption).foregroundStyle(.secondary)
                    Text(model.mode == .walk ? "Walking compass · sample phone \(Int(model.phoneHeading))°" : "Vehicle course · \(model.smooth ? "smooth" : "direct") movement").font(.caption)
                    if model.automaticRerouting || model.tools { Text("Automatic rerouting: \(model.reroutingState) · \(model.reroutingRequests) requests").font(.caption) }
                    Text("Route match: \(model.routeState)").font(.caption)
                    if model.mode == .walk { Button("Rotate sample phone") { model.rotatePhone() } }
                    if model.tools {
                        Toggle("Automatic rerouting", isOn: $model.automaticRerouting).disabled(!model.routeAware || model.path.count < 2)
                        Text("Opt-in live directions usage. Start simulation, then simulate a GPS detour. Accurate off-route fixes over three seconds can request replacement directions.").font(.caption)
                        Toggle("Preview trace contribution", isOn:$model.tracePreview).disabled(model.path.count < 2)
                        Text("Replay fixes are simulated. Validation sends coordinates to the API but never adds them to learning data.").font(.caption)
                        Text(model.traceStatus).font(.caption)
                        Button("Validate trace batch") {model.validateTrace()}.disabled(!model.tracePreview)
                        Toggle("Follow route", isOn: $model.routeAware)
                        Button(model.detour ? "Rejoin route" : "Simulate GPS detour") { model.detour.toggle() }.disabled(model.path.count < 2)
                        Toggle("Smooth movement", isOn: $model.smooth)
                        Toggle("Sample layers", isOn: $model.showLayers)
                        Text("Clusters, radius, avoid styling and a data-driven point. Avoid styling does not alter routes.").font(.caption)
                        Toggle("Rana credit on the right", isOn: $model.creditRight)
                        Button("Fit journey") { model.fit() }
                        Button("Download small map area") { Task { await model.download(key: key) } }.disabled(model.busy)
                        Button("Pause download") { model.pauseDownload() }.disabled(model.busy)
                        Button("Delete downloaded area") { Task { await model.deleteDownload() } }.disabled(model.busy)
                    } else if model.phase == .explore {
                        ForEach(destinations, id: \.0) { name, point in Button(name) { model.select(name, point); sheetHeight = min(maxSheet, 340) }.buttonStyle(.bordered).frame(maxWidth: .infinity) }
                    } else {
                        HStack { ForEach([("Car", Mode.car), ("Okada", .okada), ("Walk", .walk)], id: \.0) { name, mode in Button(name) { model.changeMode(mode) }.buttonStyle(.bordered).tint(model.mode == mode ? .orange : .secondary) } }
                        Slider(value: $model.progress, in: 0...1, onEditingChanged: { editing in if editing && model.phase == .running { model.togglePlayback() } }) { Text("Sample journey progress") }
                        Text("\(Int(model.progress * 100))% of sample journey").font(.caption)
                        HStack {
                            Button(model.phase == .running ? "Pause" : "Start simulation") { model.togglePlayback() }.buttonStyle(.borderedProminent)
                            Button("Recenter") { model.recenter() }
                        }
                        Button(model.busy ? "Loading…" : "Load live directions") { Task { await model.loadLive(key: key) } }.disabled(model.busy)
                    }
                    if !model.tools { Button("Reset demo") { model.reset() } }
                    Text(key.contains("replace") ? "Set RANA_KEY to load the base map. " + model.message : model.message).font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 20).padding(.bottom, 20).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.bottom, bottomInset)
    }
    private var title: String {
        switch model.phase { case .explore: "Where are you going?"; case .preview: model.name; case .running: "Trip in progress"; case .paused: "Simulation paused"; case .arrived: "You have arrived" }
    }
}
