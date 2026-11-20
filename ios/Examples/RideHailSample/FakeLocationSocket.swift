import Foundation
import RanaMapsSDK

// MARK: - Geometry helpers

enum Geo {
    static let metresPerDegree = Double.pi * 6_371_000 / 180

    static func distance(_ a: LatLng, _ b: LatLng) -> Double {
        let dx = (b.lng - a.lng) * metresPerDegree * cos((a.lat + b.lat) * .pi / 360)
        let dy = (b.lat - a.lat) * metresPerDegree
        return hypot(dx, dy)
    }

    /// Course in degrees clockwise from north.
    static func bearing(_ a: LatLng, _ b: LatLng) -> Double {
        let dx = (b.lng - a.lng) * cos((a.lat + b.lat) * .pi / 360)
        let dy = b.lat - a.lat
        return (atan2(dx, dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    static func offset(_ p: LatLng, eastMetres: Double, northMetres: Double) -> LatLng {
        LatLng(lat: p.lat + northMetres / metresPerDegree,
               lng: p.lng + eastMetres / (metresPerDegree * max(0.01, cos(p.lat * .pi / 180))))
    }

    static func length(_ path: [LatLng]) -> Double {
        zip(path, path.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    /// Largest distance from any point of `a` to the polyline `b` (vertex based, good enough for a sanity check).
    static func maxDeviation(of a: [LatLng], from b: [LatLng]) -> Double {
        guard b.count > 1 else { return .infinity }
        return a.map { p in
            zip(b, b.dropFirst()).map { distanceToSegment(p, $0.0, $0.1) }.min() ?? .infinity
        }.max() ?? 0
    }

    static func distanceToSegment(_ p: LatLng, _ a: LatLng, _ b: LatLng) -> Double {
        let k = cos(a.lat * .pi / 180)
        let ax = a.lng * k, ay = a.lat, bx = b.lng * k, by = b.lat, px = p.lng * k, py = p.lat
        let dx = bx - ax, dy = by - ay, len2 = dx * dx + dy * dy
        let t = len2 == 0 ? 0 : max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / len2))
        return distance(p, LatLng(lat: a.lat + (b.lat - a.lat) * t, lng: a.lng + (b.lng - a.lng) * t))
    }
}

/// Walks a polyline by distance travelled.
struct TrackWalker {
    private let points: [LatLng]
    private let cumulative: [Double]
    let totalMetres: Double

    init(_ points: [LatLng]) {
        self.points = points
        var sums = [0.0]
        for (a, b) in zip(points, points.dropFirst()) { sums.append(sums.last! + Geo.distance(a, b)) }
        cumulative = sums
        totalMetres = sums.last ?? 0
    }

    func sample(at metres: Double) -> (point: LatLng, course: Double) {
        guard points.count > 1 else { return (points.first ?? LatLng(lat: 0, lng: 0), 0) }
        let d = max(0, min(totalMetres, metres))
        var i = 1
        while i < cumulative.count - 1, cumulative[i] < d { i += 1 }
        let a = points[i - 1], b = points[i]
        let seg = cumulative[i] - cumulative[i - 1]
        let t = seg > 0 ? (d - cumulative[i - 1]) / seg : 0
        let p = LatLng(lat: a.lat + (b.lat - a.lat) * t, lng: a.lng + (b.lng - a.lng) * t)
        // Use a short look-ahead so the course is smooth and never zero-length.
        let ahead = point(at: min(totalMetres, d + 6)), behind = point(at: max(0, d - 6))
        let course = Geo.distance(behind, ahead) > 0.5 ? Geo.bearing(behind, ahead) : Geo.bearing(a, b)
        return (p, course)
    }

    private func point(at d: Double) -> LatLng {
        var i = 1
        while i < cumulative.count - 1, cumulative[i] < d { i += 1 }
        let a = points[i - 1], b = points[i], seg = cumulative[i] - cumulative[i - 1]
        let t = seg > 0 ? max(0, min(1, (d - cumulative[i - 1]) / seg)) : 0
        return LatLng(lat: a.lat + (b.lat - a.lat) * t, lng: a.lng + (b.lng - a.lng) * t)
    }
}

// MARK: - Fake websocket

/// Mimics a websocket delivering driver locations as JSON text frames:
/// `{"lat","lng","speed","heading","accuracy","ts"}`. Movement is SIMULATED by walking a route
/// geometry at a realistic speed with +-3 m of GPS noise. The vehicle keeps moving during
/// silences; only the messages are withheld.
@MainActor
final class FakeLocationSocket {
    var onMessage: ((String) -> Void)?
    var onFinished: (() -> Void)?
    /// Seconds between messages. Read on every tick, so it can change mid-trip.
    var interval: TimeInterval = 5
    private(set) var isConnected = false
    private(set) var silentUntil: Date?
    private var task: Task<Void, Never>?
    private var started = Date()

    /// Suppress messages for `seconds` (the vehicle keeps moving).
    func dropMessages(forSeconds seconds: TimeInterval) {
        silentUntil = Date().addingTimeInterval(seconds)
    }

    func connect(track: [LatLng], speed: Double) {
        disconnect()
        guard track.count > 1 else { return }
        let walker = TrackWalker(track)
        isConnected = true
        started = Date()
        task = Task { [weak self] in
            var finished = false
            while !Task.isCancelled, !finished {
                guard let self else { return }
                let travelled = speed * Date().timeIntervalSince(self.started)
                finished = travelled >= walker.totalMetres
                if !(self.silentUntil.map { Date() < $0 } ?? false) {
                    self.onMessage?(Self.frame(walker.sample(at: travelled), speed: finished ? 0 : speed))
                }
                if finished { break }
                try? await Task.sleep(nanoseconds: UInt64(max(0.2, self.interval) * 1_000_000_000))
            }
            guard let self, !Task.isCancelled else { return }
            self.isConnected = false
            self.onFinished?()
        }
    }

    func disconnect() {
        task?.cancel(); task = nil
        isConnected = false; silentUntil = nil
    }

    private static func frame(_ sample: (point: LatLng, course: Double), speed: Double) -> String {
        let noisy = Geo.offset(sample.point, eastMetres: .random(in: -3...3), northMetres: .random(in: -3...3))
        let body: [String: Any] = [
            "lat": noisy.lat, "lng": noisy.lng,
            "speed": max(0, speed + .random(in: -0.6...0.6)),
            "heading": sample.course, "accuracy": 5.0,
            "ts": Int(Date().timeIntervalSince1970 * 1000),
        ]
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Wire format of one socket message.
struct SocketFrame: Decodable {
    let lat: Double, lng: Double, speed: Double, heading: Double, accuracy: Double, ts: Double

    /// Timestamp is the time of receipt, as the app would stamp a live fix.
    func locationFix() -> LocationFix {
        LocationFix(point: LatLng(lat: lat, lng: lng), accuracyMetres: accuracy, heading: heading,
                    timestamp: Date(), speedMetresPerSecond: speed, courseAccuracyDegrees: 10)
    }
}
