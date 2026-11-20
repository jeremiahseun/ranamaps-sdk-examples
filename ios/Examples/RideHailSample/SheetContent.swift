import RanaMapsSDK
import SwiftUI

struct SheetContent: View {
    @ObservedObject var model: RideModel
    @Binding var detent: SheetDetent

    var body: some View {
        switch model.phase {
        case .idle: IdleContent(model: model, detent: $detent)
        case .options: OptionsContent(model: model)
        case .trip, .arrived: TripContent(model: model)
        }
    }
}

private struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(.black)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(sunGold.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ChipButton: ButtonStyle {
    var tint: Color = .primary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.medium)).foregroundStyle(tint)
            .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 8)
            .background(Color(uiColor: .secondarySystemBackground).opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: Idle

private struct IdleContent: View {
    @ObservedObject var model: RideModel
    @Binding var detent: SheetDetent
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Where to?", text: $model.query)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .disabled(model.pickup == nil)
                    .accessibilityIdentifier("destination-field")
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                }
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
            .onChange(of: focused) { _, isFocused in
                if isFocused { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { detent = .half } }
            }
            .onChange(of: model.query) { _, _ in model.queryChanged() }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pickupRow
                    if model.searching { ProgressView().padding(.vertical, 16).frame(maxWidth: .infinity) }
                    if let error = model.searchError {
                        Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal, 20).padding(.vertical, 8)
                    }
                    if !model.searching, model.searchError == nil, model.results.isEmpty, model.query.trimmingCharacters(in: .whitespaces).count >= 2 {
                        Text("No places found").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 8)
                    }
                    ForEach(model.results) { place in
                        Button { focused = false; model.choose(place) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill").font(.title3).foregroundStyle(sunGold)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                                    if !place.secondary.isEmpty { Text(place.secondary).font(.footnote).foregroundStyle(.secondary) }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20).padding(.vertical, 10).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var pickupRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.inset.filled").foregroundStyle(.green).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pickup: \(model.pickupName)").font(.subheadline.weight(.medium))
                Text(model.pickup == nil ? "Needs a location fix before you can search" : "Long-press the map to move the pickup").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.pickupIsPinned { Button("Reset") { model.resetPickup() }.font(.footnote.weight(.semibold)) }
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
    }
}

// MARK: Options

private struct OptionsContent: View {
    @ObservedObject var model: RideModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Choose a ride").font(.title3.bold())
                        Text("to \(model.destinationName)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("Change") { model.backToSearch() }.font(.subheadline.weight(.semibold))
                }
                Text("Pickup: \(model.pickupName)").font(.caption).foregroundStyle(.secondary)
                if model.loadingRoutes {
                    HStack(spacing: 10) { ProgressView(); Text("Finding routes...").font(.subheadline).foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else if let error = model.routeError {
                    VStack(spacing: 10) {
                        Text(error).font(.footnote).foregroundStyle(.red)
                        Button("Try again") { model.loadRoutes() }.buttonStyle(ChipButton())
                    }
                } else {
                    ForEach(model.options) { option in card(option) }
                    HStack {
                        Text("Movement").font(.subheadline)
                        Spacer()
                        Picker("Movement", selection: $model.movement) {
                            Text("Simulated").tag(Movement.simulated); Text("Device GPS").tag(Movement.device)
                        }.pickerStyle(.segmented).frame(width: 190)
                    }
                    Button("Confirm \(model.selectedOption?.title ?? "ride")") { model.confirmRide() }
                        .buttonStyle(PrimaryButton())
                        .disabled(model.selectedOption?.route == nil)
                        .accessibilityIdentifier("confirm-ride")
                    Text("Estimates are illustrative. No booking or payment is made.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
    }

    private func card(_ option: RideOption) -> some View {
        let selected = option.mode == model.selectedMode
        return Button { model.select(option.mode) } label: {
            HStack(spacing: 14) {
                Image(systemName: option.icon).font(.title2).frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title).font(.headline)
                    Text(option.route == nil ? (option.error ?? "Unavailable") : "\(option.durationText) · \(option.distanceText)")
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Text(option.priceText).font(.headline)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(selected ? sunGold.opacity(0.14) : Color(uiColor: .secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? sunGold : .clear, lineWidth: 2))
            .opacity(option.route == nil ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ride-option-\(option.mode.rawValue)")
    }
}

// MARK: Trip

private struct TripContent: View {
    @ObservedObject var model: RideModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                maneuver
                statusGrid
                if model.phase == .trip { scenarios }
                Text(model.movement == .simulated
                     ? "Location source: simulated socket walking the real route geometry with +-3 m noise. No real GPS is used."
                     : "Location source: device GPS (or the simulator's played location).")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                if model.phase == .arrived {
                    Text("You have arrived").font(.title2.bold())
                    Text(model.destinationName).font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text(model.etaSeconds.map { Fmt.duration($0) } ?? "--").font(.title2.bold())
                    Text("\(model.remainingMetres.map { (model.remainingIsExact ? "" : "~") + Fmt.distance($0) } ?? "--") to \(model.destinationName)")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Button(model.phase == .arrived ? "Done" : "End trip") { model.endTrip() }
                .font(.subheadline.weight(.semibold)).buttonStyle(.borderedProminent).tint(model.phase == .arrived ? sunGold : .red)
                .foregroundStyle(model.phase == .arrived ? .black : .white)
                .accessibilityIdentifier("end-trip")
        }
    }

    @ViewBuilder private var maneuver: some View {
        if let next = model.nextManeuver {
            HStack(spacing: 12) {
                Image(systemName: "arrow.turn.up.right").font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(next.text).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text("in \(Fmt.distance(next.metres))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var statusGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Route status", routeText, tint: routeTint)
            row("Route passed to SDK", model.hostRouteLabel, tint: model.hostRouteIsWrong ? .orange : .primary)
            row("Rerouting", reroutingText)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                row(model.movement == .simulated ? "Last socket update" : "Last GPS fix", updateText(now: context.date), tint: silent(now: context.date) ? .orange : .primary)
            }
        }
        .padding(12).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ title: String, _ value: String, tint: Color = .primary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.footnote.weight(.semibold)).foregroundStyle(tint).multilineTextAlignment(.trailing)
        }
    }

    private var routeText: String {
        let s = model.routeStatus
        let dist = s.distanceFromRouteMetres.map { " · \(Int($0.rounded())) m off" } ?? ""
        switch s.state {
        case .none: return "None"
        case .matched: return "Matched" + dist
        case .uncertain: return "Uncertain" + dist
        case .offRoute: return "Off route" + dist
        @unknown default: return "Unknown"
        }
    }
    private var routeTint: Color {
        switch model.routeStatus.state { case .matched: .green; case .offRoute: .red; case .uncertain: .orange; case .none: .secondary; @unknown default: .secondary }
    }
    private var reroutingText: String {
        guard model.autoReroute else { return "Off" }
        let s = model.reroutingStatus
        let name: String
        switch s.state {
        case .disabled: name = "Disabled"; case .monitoring: name = "Monitoring"; case .waiting: name = "Waiting"
        case .rerouting: name = "Requesting..."; case .rerouted: name = "Rerouted"; case .failed: name = "Failed"
        case .exhausted: name = "Exhausted"; case .blocked: name = "Blocked"; case .nearDestination: name = "Near destination"
        @unknown default: name = "Unknown"
        }
        return "\(name) · \(s.requestsMade) req"
    }
    private func silent(now: Date) -> Bool { model.silentUntil.map { now < $0 } ?? false }
    private func updateText(now: Date) -> String {
        if silent(now: now), let until = model.silentUntil { return "Withheld, \(Int(until.timeIntervalSince(now).rounded(.up))) s left" }
        guard let fix = model.lastFix else { return "Waiting..." }
        return "\(Int(now.timeIntervalSince(fix.timestamp))) s ago · #\(model.fixCount)"
    }

    private var scenarios: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scenarios").font(.headline)
            if model.movement == .simulated {
                HStack(spacing: 8) {
                    Button("Drop next update") { model.dropUpdates(seconds: 10) }.buttonStyle(ChipButton())
                    Button("Drop 3 updates") { model.dropUpdates(seconds: 20) }.buttonStyle(ChipButton())
                }
                Text("Silences the socket for ~10 s / ~20 s. The simulated vehicle keeps moving.").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button(model.loadingWrongRoute ? "Loading..." : "Wrong route") { model.applyWrongRoute() }
                    .buttonStyle(ChipButton(tint: .orange)).disabled(model.loadingWrongRoute || model.hostRouteIsWrong)
                Button("Restore route") { model.restoreRoute() }
                    .buttonStyle(ChipButton()).disabled(!model.hostRouteIsWrong)
            }
            Text("Hands the SDK a different route while the socket keeps emitting the real track.").font(.caption2).foregroundStyle(.secondary)
            Toggle(isOn: Binding(get: { model.autoReroute }, set: { model.setAutoReroute($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatic rerouting").font(.subheadline)
                    Text("Off by default. Sends real directions requests when off route.").font(.caption2).foregroundStyle(.secondary)
                }
            }.tint(sunGold)
            if model.movement == .simulated { HStack {
                Text("Update interval").font(.subheadline)
                Spacer()
                Picker("Update interval", selection: Binding(get: { model.interval }, set: { model.setInterval($0) })) {
                    Text("1 s").tag(1.0); Text("5 s").tag(5.0)
                }.pickerStyle(.segmented).frame(width: 140)
            } }
        }
    }
}
