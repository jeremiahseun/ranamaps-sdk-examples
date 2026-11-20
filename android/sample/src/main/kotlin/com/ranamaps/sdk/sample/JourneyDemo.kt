package com.ranamaps.sdk.sample

import com.ranamaps.sdk.RanaError
import com.ranamaps.sdk.client.LatLng
import com.ranamaps.sdk.client.Mode
import com.ranamaps.sdk.map.LocationFix
import com.ranamaps.sdk.map.RanaLocationProvider
import kotlin.math.*

enum class DemoPhase { Explore, Preview, Running, Paused, Arrived }
data class DemoDestination(val name: String, val point: LatLng)
val demoPickup = LatLng(6.5095, 3.3711)
val demoDestinations = listOf(DemoDestination("Ikeja", LatLng(6.6018, 3.3515)), DemoDestination("Marina", LatLng(6.4500, 3.3900)), DemoDestination("Corner demo", LatLng(6.5125, 3.3726)))

/** Fixture journey state. No booking, routing or device GPS is fabricated by this model. */
data class JourneyDemo(
    val phase: DemoPhase = DemoPhase.Explore,
    val destination: DemoDestination? = null,
    val mode: Mode = Mode.Car,
    val path: List<LatLng> = emptyList(),
    val progress: Float = 0f,
    val liveRoute: Boolean = false,
    val revision: Long = 0,
) {
    fun select(destination: DemoDestination): JourneyDemo {
        val end = destination.point
        val middle = LatLng((demoPickup.lat + end.lat) / 2, (demoPickup.lng + end.lng) / 2 + 0.003)
        return copy(revision = revision + 1, phase = DemoPhase.Preview, destination = destination, path = if (destination.name == "Corner demo") listOf(demoPickup, LatLng(6.511, 3.3711), LatLng(6.511, 3.3726), end) else listOf(demoPickup, middle, end), progress = 0f, liveRoute = false)
    }
    fun advance(value: Float): JourneyDemo {
        val fraction = value.coerceIn(0f, 1f)
        return copy(progress = fraction, phase = if (fraction >= 1f) DemoPhase.Arrived else if (phase == DemoPhase.Arrived) DemoPhase.Paused else phase)
    }
    fun headingAt(): Double {
        val a = pointAt((progress - .001f).coerceAtLeast(0f)); val b = pointAt((progress + .001f).coerceAtMost(1f))
        return (Math.toDegrees(atan2((b.lng - a.lng) * cos((a.lat + b.lat) * PI / 360), b.lat - a.lat)) + 360) % 360
    }
    fun pointAt(value: Float = progress): LatLng {
        if (path.isEmpty()) return demoPickup
        val lengths = path.zipWithNext { a, b -> hypot((b.lat - a.lat), (b.lng - a.lng) * cos((a.lat + b.lat) * PI / 360)) }
        var remaining = lengths.sum() * value.coerceIn(0f, 1f)
        lengths.forEachIndexed { index, length ->
            if (remaining <= length && length > 0) {
                val t = remaining / length; val a = path[index]; val b = path[index + 1]
                return LatLng(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t)
            }
            remaining -= length
        }
        return path.last()
    }
}
class DemoLocationProvider : RanaLocationProvider {
    private var callback: ((LocationFix) -> Unit)? = null
    override fun start(onLocation: (LocationFix) -> Unit, onError: (RanaError) -> Unit) { callback = onLocation }
    override fun stop() { callback = null }
    private var timestamp = 0L
    fun emit(point: LatLng, course: Double = 0.0) {
        timestamp = maxOf(System.currentTimeMillis(), timestamp + 1)
        callback?.invoke(LocationFix(point, accuracyMetres = 8.0, heading = course, timestampMs = timestamp))
    }
}
