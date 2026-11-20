package com.ranamaps.sdk.ridehail

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.ranamaps.sdk.client.*
import com.ranamaps.sdk.RanaError
import com.ranamaps.sdk.map.HeadingFix
import com.ranamaps.sdk.map.LocationFix
import com.ranamaps.sdk.map.LocationRouteState
import com.ranamaps.sdk.map.LocationRouteStatus
import com.ranamaps.sdk.map.NativeLocationProvider
import com.ranamaps.sdk.map.RanaHeadingProvider
import com.ranamaps.sdk.map.RanaLocationProvider
import com.ranamaps.sdk.map.ReroutingState
import com.ranamaps.sdk.map.ReroutingStatus
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.launch
import org.json.JSONObject
import kotlin.math.cos
import kotlin.math.roundToInt

enum class Phase { Idle, Options, Trip }
/** Where trip movement comes from: the fake websocket walking the route, or the device (or emulator) location. */
enum class Movement { Simulated, DeviceGps }

/** Fallback pickup, and the initial map centre, when location is off. */
val DefaultPickup = LatLng(6.6018, 3.3515) // Ikeja, Lagos

/** Delegates to the native provider and tells the app about every fix, so the app knows where the user is. */
class TrackingProvider(private val delegate: NativeLocationProvider, private val onFix: (LocationFix) -> Unit) : RanaLocationProvider, RanaHeadingProvider {
    override fun start(onLocation: (LocationFix) -> Unit, onError: (RanaError) -> Unit) = delegate.start({ onFix(it); onLocation(it) }, onError)
    override fun stop() = delegate.stop()
    override fun startHeading(onHeading: (HeadingFix) -> Unit) = delegate.startHeading(onHeading)
    override fun stopHeading() = delegate.stopHeading()
}
val RideModes = listOf(Mode.Car, Mode.Okada)

data class Destination(val name: String, val detail: String, val point: LatLng)
data class RideOption(val mode: Mode, val route: Route, val points: List<LatLng>, val priceNaira: Int) {
    val etaMinutes: Int get() = (route.durationS / 60.0).roundToInt().coerceAtLeast(1)
    val distanceKm: Double get() = route.distanceM / 1000.0
}
data class TripInfo(
    val remainingM: Int = 0, val etaS: Int = 0, val instruction: String? = null, val instructionInM: Int? = null,
    val arrived: Boolean = false,
)

/** All ride state. The screen reads it, applies it to the map, and feeds [fixes] to `controller.updateLocation`. */
class TripViewModel(app: Application) : AndroidViewModel(app) {
    private val client: RanaClient? = runCatching { RanaClient(app) }.getOrNull()
    val hasClient get() = client != null
    fun newClient(): RanaClient? = client

    var phase by mutableStateOf(Phase.Idle); private set
    /** Null until the first real fix (or until location is known to be off). Follows the device while idle unless the user dropped a pin. */
    var pickup by mutableStateOf<LatLng?>(null); private set
    var pickupIsPin by mutableStateOf(false); private set
    var locationGranted by mutableStateOf<Boolean?>(null); private set
    var locationOff by mutableStateOf(false); private set
    var deviceFix by mutableStateOf<LatLng?>(null); private set
    var movement by mutableStateOf(Movement.Simulated); private set
    val provider = TrackingProvider(NativeLocationProvider(app), ::onDeviceFix)
    var query by mutableStateOf(""); private set
    var suggestions by mutableStateOf<List<PlaceSuggestion>>(emptyList()); private set
    var searching by mutableStateOf(false); private set
    var attribution by mutableStateOf<String?>(null); private set
    var destination by mutableStateOf<Destination?>(null); private set
    var options by mutableStateOf<List<RideOption>>(emptyList()); private set
    var selectedMode by mutableStateOf(Mode.Car); private set
    var loadingOptions by mutableStateOf(false); private set
    var error by mutableStateOf<String?>(null); private set

    // Trip
    var info by mutableStateOf(TripInfo()); private set
    var routeStatus by mutableStateOf("none"); private set
    var rerouting by mutableStateOf("Off"); private set
    var autoReroute by mutableStateOf(false); private set
    var intervalMs by mutableStateOf(5_000L); private set
    var wrongRoute by mutableStateOf(false); private set
    var lastFrame by mutableStateOf(""); private set
    var frames by mutableStateOf(0); private set
    var droppedNote by mutableStateOf<String?>(null); private set
    /** The route handed to `setLocationRoute`. It differs from [tripRoute] while "Wrong route" is on or after a reroute. */
    var sdkRoute by mutableStateOf<List<LatLng>?>(null); private set
    var tripRoute by mutableStateOf<List<LatLng>>(emptyList()); private set

    /** Fixes parsed from socket frames, in order. The screen applies them on the main thread. */
    val fixes = MutableSharedFlow<LocationFix>(extraBufferCapacity = 64)

    val selected: RideOption? get() = options.firstOrNull { it.mode == selectedMode }
    val tripOption: RideOption? get() = if (phase == Phase.Trip) selected else null

    private var searchJob: Job? = null
    private var optionsJob: Job? = null
    private var socketJob: Job? = null
    private var socket: FakeLocationSocket? = null
    private var tracker: RouteTracker? = null

    // ---- Location ----
    fun onPermission(granted: Boolean) { locationGranted = granted; if (!granted) onLocationOff() }

    /** Permission denied or location services off: fall back to Lagos until a fix arrives. */
    fun onLocationOff() {
        locationOff = true
        if (pickup == null) pickup = DefaultPickup
        if (movement == Movement.DeviceGps && phase != Phase.Trip) movement = Movement.Simulated
    }

    private fun onDeviceFix(fix: LocationFix) {
        deviceFix = fix.point; locationOff = false
        if (phase == Phase.Idle && !pickupIsPin) pickup = fix.point
        if (phase == Phase.Trip && movement == Movement.DeviceGps) {
            frames++
            val tracker = tracker ?: return
            if (info.arrived) return
            val next = tracker.update(fix.point, fix.speedMetresPerSecond ?: 0.0)
            info = if (next.remainingM < 25) next.copy(arrived = true, remainingM = 0, etaS = 0, instruction = "You have arrived", instructionInM = null) else next
        }
    }

    fun chooseMovement(value: Movement) { if (phase != Phase.Trip && (value == Movement.Simulated || locationGranted == true)) movement = value }

    // ---- Idle: search ----
    fun onQuery(text: String) {
        query = text; error = null
        searchJob?.cancel()
        if (text.trim().length < 2) { suggestions = emptyList(); searching = false; return }
        searchJob = viewModelScope.launch {
            delay(350)
            val api = client ?: run { error = "Set -PranaKey=pk_live_… to search and route."; return@launch }
            searching = true
            try {
                val result = api.places.autocompleteResults(text.trim(), near = pickup ?: deviceFix, limit = 6)
                suggestions = result.results; attribution = result.attribution
            } catch (c: CancellationException) { throw c } catch (e: Exception) { error = e.message ?: "Search failed" }
            finally { searching = false }
        }
    }

    fun dropPickup(point: LatLng) {
        if (phase == Phase.Trip) return
        pickup = point; pickupIsPin = true
        destination?.let { loadOptions(it) }
    }

    fun resetPickup() {
        if (phase == Phase.Trip) return
        pickupIsPin = false; pickup = deviceFix ?: if (locationOff) DefaultPickup else null
        destination?.let { loadOptions(it) }
    }

    fun choose(suggestion: PlaceSuggestion) {
        if (pickup == null) return // route requests wait for the first location
        query = suggestion.name; suggestions = emptyList()
        loadOptions(Destination(suggestion.name, suggestion.secondary, suggestion.point))
    }

    // ---- Options ----
    private fun loadOptions(dest: Destination) {
        val api = client ?: run { error = "Set -PranaKey=pk_live_… to search and route."; return }
        val from = pickup ?: run { error = "Waiting for location…"; return }
        destination = dest; phase = Phase.Options; loadingOptions = true; options = emptyList(); error = null
        optionsJob?.cancel()
        optionsJob = viewModelScope.launch {
            try {
                val loaded = coroutineScope {
                    RideModes.map { mode -> async { mode to runCatching { api.directions(Location.Point(from), Location.Point(dest.point), mode).routes.firstOrNull() } } }
                        .map { it.await() }
                }
                options = loaded.mapNotNull { (mode, result) ->
                    result.getOrNull()?.let { r -> RideOption(mode, r, r.points(), price(mode, r)) }
                }
                if (options.none { it.mode == selectedMode }) options.firstOrNull()?.let { selectedMode = it.mode }
                if (options.isEmpty()) error = loaded.firstNotNullOfOrNull { it.second.exceptionOrNull() }?.message ?: "No route found."
            } catch (c: CancellationException) { throw c } finally { loadingOptions = false }
        }
    }

    fun select(mode: Mode) { selectedMode = mode }

    fun backToIdle() {
        optionsJob?.cancel(); destination = null; options = emptyList(); phase = Phase.Idle; error = null
    }

    private fun price(mode: Mode, route: Route): Int {
        val km = route.distanceM / 1000.0; val min = route.durationS / 60.0
        val raw = if (mode == Mode.Car) 600 + 140 * km + 18 * min else 300 + 90 * km + 10 * min
        return ((raw / 50).roundToInt() * 50)
    }

    // ---- Trip ----
    fun confirm() {
        val option = selected ?: return
        phase = Phase.Trip
        tripRoute = option.points; sdkRoute = option.points; wrongRoute = false
        tracker = RouteTracker(option.points, option.route.legs.flatMap { it.steps }, option.route.durationS)
        info = tracker!!.update(option.points.first(), 0.0)
        routeStatus = "none"; frames = 0; lastFrame = ""; droppedNote = null
        rerouting = if (autoReroute) "Monitoring" else "Off"
        if (movement == Movement.DeviceGps) { socketJob?.cancel(); socket = null; return }
        val speed = if (option.mode == Mode.Okada) 9.0 else 11.0
        val fake = FakeLocationSocket(option.points, speed, intervalMs)
        socket = fake
        socketJob?.cancel()
        socketJob = viewModelScope.launch {
            val collector = launch { fake.messages.collect(::onFrame) }
            delay(400) // let the screen install the route before the first frame
            fake.connect(this) { info = info.copy(arrived = true, remainingM = 0, etaS = 0, instruction = "You have arrived", instructionInM = null) }.join()
            collector.cancel()
        }
    }

    private fun onFrame(text: String) {
        val o = JSONObject(text)
        val point = LatLng(o.getDouble("lat"), o.getDouble("lng"))
        fixes.tryEmit(LocationFix(point, o.optDouble("accuracy"), o.optDouble("heading"), o.getLong("ts"), o.optDouble("speed"), 10.0))
        frames++; lastFrame = text
        tracker?.let { info = it.update(point, o.optDouble("speed")).let { next -> if (info.arrived) info else next } }
    }

    fun dropUpdates(count: Int) {
        socket?.dropNext(count)
        droppedNote = "Socket silent for ~${(count + 1) * intervalMs / 1000} s"
        viewModelScope.launch { delay((count + 1) * intervalMs); droppedNote = null }
    }

    fun setInterval(ms: Long) { intervalMs = ms; socket?.intervalMs = ms }

    fun startWrongRoute() {
        val base = tripRoute; if (base.size < 2) return
        // The same road shape moved ~250 m east: a plausible-looking but wrong path, immediately off the driver's real track.
        val shift = 250.0 / (111_320.0 * cos(Math.toRadians(base.first().lat)))
        sdkRoute = base.map { LatLng(it.lat, it.lng + shift) }; wrongRoute = true
    }
    fun restoreRoute() { sdkRoute = tripRoute; wrongRoute = false }
    fun toggleAutoReroute(on: Boolean) { autoReroute = on; rerouting = if (on) "Monitoring" else "Off" }

    /** Called by the screen when the SDK installed a replacement route on its own. */
    fun onRerouted(path: List<LatLng>) { sdkRoute = path; wrongRoute = false }
    fun onRouteStatus(status: LocationRouteStatus) {
        routeStatus = when (status.state) {
            LocationRouteState.Matched -> "matched"
            LocationRouteState.OffRoute -> "off-route" + (status.distanceFromRouteMetres?.let { " (${it.roundToInt()} m)" } ?: "")
            LocationRouteState.Uncertain -> "uncertain"
            LocationRouteState.None -> "none"
        }
    }
    fun onReroutingStatus(status: ReroutingStatus) {
        rerouting = if (status.state == ReroutingState.Disabled) "Off" else "${status.state.name} · ${status.requestsMade} request(s)" +
            (status.error?.let { " · ${it.code}" } ?: "")
    }
    fun reportError(message: String) { error = message }

    fun endTrip() {
        socketJob?.cancel(); socket = null; tracker = null
        sdkRoute = null; tripRoute = emptyList(); wrongRoute = false; info = TripInfo()
        routeStatus = "none"; rerouting = if (autoReroute) "Monitoring" else "Off"; droppedNote = null
        destination = null; options = emptyList(); query = ""; suggestions = emptyList(); phase = Phase.Idle
        if (!pickupIsPin) pickup = deviceFix ?: pickup
    }

    override fun onCleared() { socketJob?.cancel() }
}

/** The app's own view of progress along the chosen route, for remaining distance, ETA and the next maneuver. */
private class RouteTracker(private val points: List<LatLng>, steps: List<Step>, private val durationS: Int) {
    private val cumulative = DoubleArray(points.size).also { c -> for (i in 1 until points.size) c[i] = c[i - 1] + FakeLocationSocket.metres(points[i - 1], points[i]) }
    private val total = cumulative.last()
    private var segment = 0
    private val maneuvers: List<Pair<Double, String>>
    init {
        var from = 0
        maneuvers = steps.map { step ->
            val (index, progress) = project(step.location, from, points.lastIndex - 1)
            from = index
            progress to step.instruction
        }
        segment = 0
    }

    private fun project(p: LatLng, from: Int, to: Int): Pair<Int, Double> {
        var best = Double.MAX_VALUE; var bestIndex = from; var bestProgress = cumulative[from]
        val k = cos(Math.toRadians(p.lat))
        for (i in from..to.coerceAtLeast(from)) {
            val a = points[i]; val b = points[i + 1]
            val ax = (b.lng - a.lng) * k; val ay = b.lat - a.lat
            val len2 = ax * ax + ay * ay
            val t = if (len2 == 0.0) 0.0 else (((p.lng - a.lng) * k * ax + (p.lat - a.lat) * ay) / len2).coerceIn(0.0, 1.0)
            val d = FakeLocationSocket.metres(p, LatLng(a.lat + ay * t, a.lng + (b.lng - a.lng) * t))
            if (d < best) { best = d; bestIndex = i; bestProgress = cumulative[i] + t * (cumulative[i + 1] - cumulative[i]) }
        }
        return bestIndex to bestProgress
    }

    fun update(fix: LatLng, @Suppress("UNUSED_PARAMETER") speed: Double): TripInfo {
        val (index, progress) = project(fix, segment, minOf(points.lastIndex - 1, segment + 400))
        segment = index
        val remaining = (total - progress).coerceAtLeast(0.0)
        val next = maneuvers.firstOrNull { it.first > progress + 15 } ?: maneuvers.lastOrNull()
        return TripInfo(remaining.roundToInt(), (durationS * remaining / total.coerceAtLeast(1.0)).roundToInt(),
            next?.second, next?.let { (it.first - progress).coerceAtLeast(0.0).roundToInt() })
    }
}
