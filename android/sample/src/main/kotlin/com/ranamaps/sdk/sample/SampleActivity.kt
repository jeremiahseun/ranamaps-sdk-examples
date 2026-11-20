package com.ranamaps.sdk.sample

import android.os.Bundle
import android.widget.TextView
import android.graphics.Color
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged

import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import com.ranamaps.sdk.RanaError
import com.ranamaps.sdk.client.*
import com.ranamaps.sdk.map.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Interaction sample. Base tiles need a key; fixture journeys and replayed location are clearly labelled. */
class SampleActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MaterialTheme { JourneyScreen() } }
    }

    @Composable
    private fun JourneyScreen() {
        val key = runCatching { com.ranamaps.sdk.RanaMaps.apiKey(this@SampleActivity) }.getOrDefault("")
        val density = LocalDensity.current
        val scope = rememberCoroutineScope()
        var map by remember { mutableStateOf<RanaMapController?>(null) }
        var journey by remember { mutableStateOf(JourneyDemo()) }
        var night by remember { mutableStateOf(false) }
        var tilted by remember { mutableStateOf(false) }
        var tools by remember { mutableStateOf(false) }
        var creditRight by remember { mutableStateOf(false) }
        var smooth by remember { mutableStateOf(true) }
        var tracePreview by remember { mutableStateOf(false) }
        var traceRecorder by remember { mutableStateOf<JourneyTraceRecorder?>(null) }
        var traceStatus by remember { mutableStateOf("Trace preview: off") }
        var automaticRerouting by remember { mutableStateOf(false) }
        var reroutingState by remember { mutableStateOf("Disabled") }
        var reroutingRequests by remember { mutableIntStateOf(0) }
        var installedPath by remember { mutableStateOf<List<LatLng>?>(null) }
        var installedRevision by remember { mutableLongStateOf(-1) }
        var configuredAutomatic by remember { mutableStateOf(false) }
        var routeAware by remember { mutableStateOf(true) }
        var detour by remember { mutableStateOf(false) }
        var routeState by remember { mutableStateOf("None") }
        var phoneHeading by remember { mutableStateOf(0.0) }
        var layers by remember { mutableStateOf(false) }
        var message by remember { mutableStateOf(if (key.contains("replace")) "Set -PranaKey to load the base map. Journeys use sample data." else "Tap a destination or drop a pin on the map.") }
        var routeGeneration by remember { mutableIntStateOf(0) }
        var busy by remember { mutableStateOf(false) }
        var line by remember { mutableStateOf<RanaPolyline?>(null) }
        var destinationPin by remember { mutableStateOf<RanaMarker?>(null) }
        var topInset by remember { mutableStateOf(100.0) }
        var pack by remember { mutableStateOf<RanaOfflineRegion?>(null) }
        val provider = remember { DemoLocationProvider() }
        fun emitLocation() {
            val point = journey.pointAt()
            val course = journey.headingAt(); val radians = Math.toRadians(course)
            provider.emit(if (detour) LatLng(point.lat - kotlin.math.sin(radians) * .0008, point.lng + kotlin.math.cos(radians) * .0008 / kotlin.math.cos(Math.toRadians(point.lat))) else point, course)
            if (journey.mode == Mode.Walk) map?.updateDeviceHeading(HeadingFix(phoneHeading, 5.0))
            routeState = when (map?.locationRouteStatus?.state) {
                LocationRouteState.Matched -> "Matched"
                LocationRouteState.OffRoute -> "Off route"
                LocationRouteState.Uncertain -> "Uncertain"
                else -> "None"
            }
        }
        val offline = remember { mutableStateOf<RanaOfflineManager?>(null) }

        DisposableEffect(Unit) {
            onDispose { pack?.pause(); pack?.observe(null, null); provider.stop() }
        }
        LaunchedEffect(map) {
            val ready = map ?: return@LaunchedEffect
            ready.setLocationProvider(provider)
            ready.setOnMapClickListener { point -> routeGeneration++; journey = journey.select(DemoDestination("Dropped pin", point)) }
            val chip = TextView(this@SampleActivity).apply {
                text = "Pickup"; setTextColor(Color.BLACK); setBackgroundColor(Color.WHITE); setPadding(16, 10, 16, 10)
                setOnClickListener { message = "This is the sample pickup. No booking is created." }
            }
            ready.addMarker(demoPickup, MarkerContent.View(chip))
            ready.fitPoints(listOf(demoPickup) + demoDestinations.map { it.point })
        }
        LaunchedEffect(map, journey.revision, tracePreview) {
            val ready = map ?: return@LaunchedEffect
            ready.setJourneyTraceRecorder(null); traceRecorder = null
            if (tracePreview && journey.path.size >= 2) {
                val recorder = JourneyTraceRecorder(RanaClient(this@SampleActivity), JourneyTraceOptions(true, JourneyTraceSource.Simulated, journey.mode)) { status ->
                    scope.launch { kotlinx.coroutines.yield(); traceStatus = if (status.stopped) "Trace preview: off" else "Simulated trace: ${status.buffered} buffered · ${status.uploaded} learned${status.error?.let { " · ${it.code}" } ?: ""}" }
                }
                traceRecorder = recorder; ready.setJourneyTraceRecorder(recorder)
            } else traceStatus = "Trace preview: off"
        }
        LaunchedEffect(map, journey.path, journey.mode, journey.revision, routeAware, automaticRerouting) {
            val ready = map ?: return@LaunchedEffect
            val desired = if (routeAware && journey.path.size >= 2) journey.path else null
            val replaceRoute = desired != installedPath || installedRevision != journey.revision
            if (replaceRoute) { ready.setLocationRoute(desired); installedPath = desired; installedRevision = journey.revision }
            if (replaceRoute || automaticRerouting != configuredAutomatic) {
                if (automaticRerouting && desired != null) ready.setAutomaticRerouting(ReroutingOptions(destination = Location.Point(journey.destination!!.point), mode = journey.mode), DirectionsReroutingProvider(RanaClient(this@SampleActivity)))
                else ready.setAutomaticRerouting(null)
                configuredAutomatic = automaticRerouting
            }
            line?.remove(); destinationPin?.remove()
            line = null; destinationPin = null
            if (journey.path.size >= 2) {
                line = ready.addPolyline(journey.path, PolylineOptions(mode = journey.mode, progress = journey.progress, arrows = true))
                destinationPin = ready.addMarker(journey.path.last(), MarkerContent.Pin(label = "B"), MarkerStyle(draggable = true))
                if (replaceRoute) ready.fitPoints(journey.path)
            }
            emitLocation()
        }
        LaunchedEffect(map, journey.progress, journey.mode, smooth, phoneHeading, detour, routeAware) {
            line?.setProgress(journey.progress)
            emitLocation()
        }
        LaunchedEffect(journey.phase) {
            if (journey.phase == DemoPhase.Running) {
                map?.setTracking(LocationTracking.FollowHeading)
                while (journey.phase == DemoPhase.Running) { delay(600); journey = journey.advance(journey.progress + 0.01f) }
            }
        }
        LaunchedEffect(map, layers) {
            val ready = map ?: return@LaunchedEffect
            if (!layers) return@LaunchedEffect
            val image = android.graphics.Bitmap.createBitmap(32, 32, android.graphics.Bitmap.Config.ARGB_8888)
            android.graphics.Canvas(image).drawCircle(16f, 16f, 12f, android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(47, 63, 143) })
            val imageMarker = ready.addMarker(LatLng(6.53, 3.40), MarkerContent.Image(image, anchor = MarkerAnchor.Center))
            val points = ready.addPoints(listOf(LatLng(6.53, 3.38), LatLng(6.531, 3.381), LatLng(6.55, 3.37)))
            val radius = ready.addCircle(demoPickup, 350.0, label = "350 m")
            val avoid = ready.addPolygon(listOf(listOf(LatLng(6.54, 3.38), LatLng(6.55, 3.38), LatLng(6.55, 3.39), LatLng(6.54, 3.39))), ShapeOptions(style = ShapeStyle.Avoid))
            val source = ready.addGeoJsonSource("demo-deliveries", """{"type":"FeatureCollection","features":[{"type":"Feature","geometry":{"type":"Point","coordinates":[3.39,6.56]},"properties":{"status":"late"}}]}""")
            val data = ready.addLayer("demo-dots", "demo-deliveries", DataLayerOptions(kind = DataLayerKind.Circle, color = StyleExpression.Match("status", mapOf("late" to StyleExpression.Color("#C4373F")), StyleExpression.Color("#ECA824"))))
            try { kotlinx.coroutines.awaitCancellation() } finally { imageMarker.remove(); points.remove(); radius.remove(); avoid.remove(); data.remove(); source.remove() }
        }

        BoxWithConstraints(Modifier.fillMaxSize()) {
            val maxSheet = (maxHeight.value * 0.82f).coerceAtLeast(220f)
            var sheetHeight by remember { mutableStateOf(280f) }
            val height = sheetHeight.coerceIn(180f, maxSheet)
            RanaMap(modifier = Modifier.fillMaxSize(), style = if (night) RanaStyle.Night else RanaStyle.Day,
                center = demoPickup, zoom = 12.0,
                controls = ControlsOptions(zoom = ControlPlacement.at(ControlCorner.TopEnd)),
                settings = MapSettings(camera = CameraOptions(pitch = if (tilted) 35.0 else 0.0),
                    padding = MapPadding(top = topInset, bottom = height.toDouble()), location = LocationOptions(appearance = TravellerAppearance.Puck, motion = if (smooth) LocationMotion.Smooth else LocationMotion.Direct, activity = if (journey.mode == Mode.Walk) LocationActivity.Walking else LocationActivity.Vehicle), attribution = AttributionOptions(corner = if (creditRight) ControlCorner.BottomRight else ControlCorner.BottomLeft),
                    events = MapEvents(onReroutingChanged = {
                        scope.launch { kotlinx.coroutines.yield(); map?.reroutingStatus?.let { status -> reroutingState = status.state.name; reroutingRequests = status.requestsMade; status.error?.let { message = "${it.code}: ${it.message}" } } }
                    }, onRerouted = { result ->
                        routeGeneration++; installedPath = result.path; installedRevision = journey.revision
                        detour = false; journey = journey.copy(path = result.path, progress = 0f, liveRoute = true)
                        message = "Automatic reroute loaded. Movement remains simulated."
                    }, onError = { message = "${it.code}: ${it.message}" + if (it.code == "map_load_error") " Check the key/network, then switch Day/Night to retry." else "" }, onMarkerDrag = { _, point, phase -> if (phase == DragPhase.Ended) { routeGeneration++; journey = journey.select(DemoDestination("Dropped pin", point)) } }),
                )) { map = it }
            Surface(Modifier.align(Alignment.TopCenter).fillMaxWidth().onSizeChangedCompat { topInset = it / density.density.toDouble() }, color = MaterialTheme.colorScheme.surface) {
                Row(Modifier.statusBarsPadding().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) { Text("Explore Lagos", style = MaterialTheme.typography.titleLarge); Text("Demo trip · replayed location", style = MaterialTheme.typography.bodySmall) }
                    TextButton(onClick = { night = !night }) { Text(if (night) "Day" else "Night") }
                    TextButton(onClick = { tilted = !tilted }) { Text(if (tilted) "2D" else "3D") }
                }
            }
            Surface(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(height.dp).testTag("journey-sheet"), shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp), tonalElevation = 2.dp) {
                Column(Modifier.navigationBarsPadding()) {
                    Row(Modifier.fillMaxWidth().height(48.dp).testTag("sheet-handle").pointerInput(maxSheet) {
                        detectVerticalDragGestures(onDragEnd = { if (journey.phase != DemoPhase.Running) map?.fitPoints(journey.path) }) { change, amount ->
                            change.consume(); sheetHeight = (sheetHeight - amount / density.density).coerceIn(180f, maxSheet)
                        }
                    }.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.width(32.dp).height(4.dp).background(MaterialTheme.colorScheme.outline, RoundedCornerShape(2.dp)))
                        TextButton(onClick = { sheetHeight = if (height < 400) maxSheet else 240f }) { Text(if (height < 400) "Expand" else "Collapse") }
                        Spacer(Modifier.weight(1f)); TextButton(onClick = { tools = !tools; sheetHeight = 440f.coerceAtMost(maxSheet) }) { Text(if (tools) "Trip" else "Map tools") }
                    }
                    Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(when (journey.phase) { DemoPhase.Explore -> "Where are you going?"; DemoPhase.Preview -> journey.destination?.name ?: "Route preview"; DemoPhase.Running -> "Trip in progress"; DemoPhase.Paused -> "Simulation paused"; DemoPhase.Arrived -> "You have arrived" }, style = MaterialTheme.typography.headlineSmall)
                        Text(if (journey.liveRoute) "Live route · simulated movement · no booking" else "Illustrative route · simulated movement · no booking", style = MaterialTheme.typography.bodySmall)
                        Text(if (journey.mode == Mode.Walk) "Walking compass · sample phone ${phoneHeading.toInt()}°" else "Vehicle course · ${if (smooth) "smooth" else "direct"} movement", style = MaterialTheme.typography.bodySmall)
                        if (automaticRerouting || tools) Text("Automatic rerouting: $reroutingState · $reroutingRequests requests", style = MaterialTheme.typography.bodySmall)
                        Text("Route match: $routeState", style = MaterialTheme.typography.bodySmall)
                        if (journey.mode == Mode.Walk) TextButton(onClick = { phoneHeading = (phoneHeading + 45) % 360 }) { Text("Rotate sample phone") }
                        if (!tools) {
                            if (journey.phase == DemoPhase.Explore) demoDestinations.forEach { destination -> OutlinedButton(onClick = { routeGeneration++; journey = journey.select(destination); sheetHeight = 340f.coerceAtMost(maxSheet) }, modifier = Modifier.fillMaxWidth()) { Text(destination.name) } }
                            else {
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { listOf(Mode.Car to "Car", Mode.Okada to "Okada", Mode.Walk to "Walk").forEach { (mode, name) -> FilterChip(selected = journey.mode == mode, onClick = { routeGeneration++; journey = journey.select(journey.destination!!).copy(mode = mode) }, label = { Text(name) }) } }
                                Slider(value = journey.progress, onValueChange = { journey = journey.copy(phase = DemoPhase.Paused).advance(it) }, valueRange = 0f..1f)
                                Text("${(journey.progress * 100).toInt()}% of sample journey", style = MaterialTheme.typography.bodySmall)
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Button(onClick = { journey = if (journey.phase == DemoPhase.Running) journey.copy(phase = DemoPhase.Paused) else journey.copy(phase = DemoPhase.Running, progress = if (journey.progress >= 1) 0f else journey.progress) }) { Text(if (journey.phase == DemoPhase.Running) "Pause" else "Start simulation") }
                                    TextButton(onClick = { map?.setTracking(LocationTracking.FollowHeading); emitLocation() }) { Text("Recenter") }
                                }
                                TextButton(enabled = !busy, onClick = {
                                    busy = true
                                    val request = ++routeGeneration
                                    val requested = journey
                                    scope.launch {
                                        try {
                                            val result = RanaClient(this@SampleActivity).directions(Location.Point(demoPickup), Location.Point(requested.destination!!.point), requested.mode)
                                            if (request != routeGeneration) return@launch
                                            val route = result.routes.firstOrNull()
                                            if (route == null) message = "No route returned. Try another destination."
                                            else { journey = journey.copy(path = route.points(), phase = DemoPhase.Preview, progress = 0f, liveRoute = true); message = "Live directions loaded. Movement remains simulated." }
                                        } catch (cancelled: CancellationException) { throw cancelled } catch (error: Exception) { if (request == routeGeneration) message = error.message ?: "Directions failed. Retry when connected." } finally { busy = false }
                                    }
                                }) { Text(if (busy) "Loading…" else "Load live directions") }
                            }
                            TextButton(onClick = { routeGeneration++; tracePreview = false; automaticRerouting = false; detour = false; journey = JourneyDemo(); map?.setTracking(LocationTracking.None); map?.hideUserLocation() }) { Text("Reset demo") }
                        } else {
                            Row(verticalAlignment = Alignment.CenterVertically) { Text("Automatic rerouting", Modifier.weight(1f)); Switch(checked = automaticRerouting, onCheckedChange = { automaticRerouting = it }, enabled = routeAware && journey.path.size >= 2, modifier = Modifier.testTag("automatic-rerouting")) }
                            Text("Opt-in live directions usage. Start simulation, then simulate a GPS detour. Accurate off-route fixes over three seconds can request replacement directions.", style = MaterialTheme.typography.bodySmall)
                            Row(verticalAlignment = Alignment.CenterVertically) { Text("Preview trace contribution", Modifier.weight(1f)); Switch(checked = tracePreview, onCheckedChange = { tracePreview = it }, enabled = journey.path.size >= 2, modifier = Modifier.testTag("trace-preview")) }
                            Text("Replay fixes are simulated. Validation sends coordinates to the API but never adds them to learning data.", style = MaterialTheme.typography.bodySmall)
                            Text(traceStatus, style = MaterialTheme.typography.bodySmall)
                            TextButton(enabled = traceRecorder != null, onClick = { scope.launch { try { if ((traceRecorder?.status?.buffered ?: 0) < 2) { message = "Start simulation to collect at least two fixes."; return@launch }; traceRecorder?.flush(); message = "Trace batch validated. Simulated fixes are never learned." } catch (error: Exception) { message = error.message ?: "Trace validation failed" } } }) { Text("Validate trace batch") }
                            Row(verticalAlignment = Alignment.CenterVertically) { Text("Follow route", Modifier.weight(1f)); Switch(checked = routeAware, onCheckedChange = { routeAware = it }, modifier = Modifier.testTag("route-aware")) }
                            TextButton(enabled = journey.path.size >= 2, onClick = { detour = !detour }) { Text(if (detour) "Rejoin route" else "Simulate GPS detour") }
                            Row(verticalAlignment = Alignment.CenterVertically) { Text("Smooth movement", Modifier.weight(1f)); Switch(checked = smooth, onCheckedChange = { smooth = it }, modifier = Modifier.testTag("smooth-movement")) }
                            Row(verticalAlignment = Alignment.CenterVertically) { Text("Sample layers", Modifier.weight(1f)); Switch(checked = layers, onCheckedChange = { layers = it }) }
                            Text("Clusters, radius, avoid styling and a data-driven point. Avoid styling does not alter routes.", style = MaterialTheme.typography.bodySmall)
                            Button(onClick = { creditRight = true; map?.setAttribution(AttributionOptions(corner = ControlCorner.BottomRight)) }) { Text("Move Rana credit to right") }
                            TextButton(onClick = { creditRight = false; map?.setAttribution(AttributionOptions()); map?.fitPoints(journey.path.ifEmpty { listOf(demoPickup) + demoDestinations.map { it.point } }) }) { Text("Restore left credit and fit") }
                            OutlinedButton(enabled = !busy, onClick = {
                                scope.launch {
                                    busy = true
                                    try {
                                        val manager = offline.value ?: RanaOfflineManager(this@SampleActivity).also { offline.value = it }
                                        val id = if (night) "demo-night" else "demo-day"
                                        val region = manager.regions().firstOrNull { it.id == id } ?: manager.createRegion(OfflineRegionOptions(id, CameraBounds(LatLng(6.49, 3.35), LatLng(6.54, 3.40)), if (night) RanaStyle.Night else RanaStyle.Day, 8.0, 13.0, 20L * 1024 * 1024))
                                        pack?.pause(); pack?.observe(null, null); pack = region; region.observe({ message = if (it.complete) "Offline pack ready." else "Offline download: ${it.completedResources} resources" }, { message = it.message ?: it.code }); region.resume()
                                    } catch (cancelled: CancellationException) { throw cancelled } catch (error: Exception) { message = error.message ?: "Download failed." } finally { busy = false }
                                }
                            }) { Text("Download small map area") }
                            TextButton(enabled = !busy, onClick = { pack?.observe(null, null); pack?.pause(); message = "Offline download paused." }) { Text("Pause download") }
                            TextButton(enabled = !busy && pack != null, onClick = {
                                scope.launch {
                                    val region = pack ?: return@launch; busy = true
                                    try { region.remove(); pack = null; message = "Offline pack deleted." }
                                    catch (cancelled: CancellationException) { throw cancelled }
                                    catch (error: Exception) { message = "Deletion failed. The pack is paused; retry or resume. ${error.message ?: ""}" }
                                    finally { busy = false }
                                }
                            }) { Text("Delete downloaded area") }
                        }
                        Text(message, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
    }
}

private fun Modifier.onSizeChangedCompat(changed: (Int) -> Unit): Modifier = this.then(Modifier.onSizeChanged { changed(it.height) })
