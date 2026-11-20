import RanaMapsSDK
import SwiftUI
import UIKit

let sunGold = Color(red: 0.925, green: 0.659, blue: 0.141)

/// Full-bleed map. Settings are derived from state because the SDK re-applies the settings struct on
/// every SwiftUI update: padding and tracking must therefore always be passed in current.
private struct MapLayer: View {
    let model: RideModel
    let padding: MapPadding
    let tracking: LocationTracking
    let appearance: TravellerAppearance

    var body: some View {
        RanaMap(
            style: .day, center: lagosCentre, zoom: 11,
            controls: ControlsOptions(compass: .topRight, zoom: .hidden, locate: .hidden, scale: .hidden),
            settings: MapSettings(
                padding: padding,
                location: LocationOptions(tracking: tracking, appearance: appearance, motion: .smooth, activity: .vehicle, firstFixZoom: 16.5),
                events: MapEvents(
                    onLongPress: { [weak model] point in model?.longPress(point) },
                    onError: { [weak model] error in Task { @MainActor in model?.banner = error.description } },
                    onTrackingChanged: { [weak model] value in Task { @MainActor in model?.trackingChangedByMap(value) } },
                    onLocationRouteChanged: { [weak model] _ in Task { @MainActor in model?.routeChangedByMap() } },
                    onReroutingChanged: { [weak model] status in Task { @MainActor in model?.reroutingChangedByMap(status) } },
                    onRerouted: { [weak model] result in Task { @MainActor in model?.rerouted(result) } }
                )
            ),
            onReady: { controller in model.attach(controller) }
        )
    }
}

struct RideHailView: View {
    @StateObject private var model = RideModel()
    @State private var detent: SheetDetent = .collapsed
    @State private var keyboard: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            let safeBottom = geo.safeAreaInsets.bottom
            let total = geo.size.height + safeBottom
            ZStack(alignment: .bottom) {
                MapLayer(model: model, padding: model.mapPadding, tracking: model.tracking, appearance: model.phase == .idle || model.phase == .options ? .dot : .puck)
                    .ignoresSafeArea()
                topOverlay
                BottomSheet(detent: $detent, totalHeight: total, safeBottom: keyboard > 0 ? 0 : safeBottom,
                            topReserve: 72, lift: keyboard,
                            onVisibleHeight: { model.setSheetInset(top: safeTop + 56, bottom: Double($0)) }) {
                    SheetContent(model: model, detent: $detent)
                }
            }
            .frame(width: geo.size.width, height: total)
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .ignoresSafeArea(.keyboard)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let height = max(0, UIScreen.main.bounds.height - frame.minY)
            withAnimation(.easeOut(duration: 0.25)) { keyboard = height }
        }
        .onChange(of: model.phase) { _, phase in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { detent = phase == .idle ? .collapsed : .half }
        }
        .onDisappear { model.detach() }
    }

    private var topOverlay: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Label(model.movement == .simulated ? "Simulated movement" : "Device GPS", systemImage: model.movement == .simulated ? "waveform.path" : "location.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .accessibilityIdentifier("simulated-badge")
                if model.tracking == .none, model.userLocation != nil || model.phase == .trip {
                    Button { model.recenter() } label: {
                        Label("Recenter", systemImage: "location.north.line.fill").font(.caption.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(sunGold, in: Capsule()).foregroundStyle(.black)
                    }
                }
                Spacer()
            }
            if let banner = model.banner {
                Text(banner).font(.caption).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(.white)
                    .onTapGesture { model.banner = nil }
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.top, 6)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(true)
    }
}
