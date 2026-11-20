package com.ranamaps.sdk.ridehail

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ranamaps.sdk.client.LatLng
import com.ranamaps.sdk.client.Location
import com.ranamaps.sdk.map.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Ride-hailing sample: one full-bleed map and a draggable sheet. The pickup is the device's real location. Trip movement is
 * either [FakeLocationSocket] ("Simulated") or the device's own location ("Device GPS"); nothing here books a real ride.
 */
class RideHailActivity : ComponentActivity() {
    private val vm: TripViewModel by viewModels()
    private val permissions = arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
    private val requestLocation = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { vm.onPermission(it.values.any { granted -> granted }) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (permissions.any { ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED }) vm.onPermission(true)
        else if (vm.locationGranted == null) requestLocation.launch(permissions)
        enableEdgeToEdge()
        setContent {
            MaterialTheme(colorScheme = lightColorScheme(primary = Color(0xFF2F3F8F), secondary = Color(0xFFECA824), surface = Color.White, surfaceVariant = Color(0xFFF1F3F9))) {
                RideScreen(vm)
            }
        }
    }
}

internal enum class Detent { Collapsed, Half, Expanded }

@Composable
private fun RideScreen(vm: TripViewModel) {
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    var controller by remember { mutableStateOf<RanaMapController?>(null) }
    var tracking by remember { mutableStateOf(LocationTracking.None) }
    val installed = remember { arrayOfNulls<List<LatLng>>(1) }
    val inTrip = vm.phase == Phase.Trip
    val followTarget = if (inTrip) LocationTracking.FollowHeading else LocationTracking.Follow

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val maxH = maxHeight.value
        val detentHeights = mapOf(Detent.Collapsed to 148f, Detent.Half to maxH * 0.46f, Detent.Expanded to maxH * 0.88f)
        val navBar = with(density) { WindowInsets.navigationBars.getBottom(density).toDp().value }
        val ime = with(density) { WindowInsets.ime.getBottom(density).toDp().value }
        val sheet = remember { Animatable(detentHeights.getValue(Detent.Half) + navBar) }
        var detent by remember { mutableStateOf(Detent.Half) }
        val sheetDp = sheet.value
        // Height of the sheet as it covers the map; the keyboard lifts the sheet, so it counts too.
        val visibleBottom = (sheetDp + (ime - navBar).coerceAtLeast(0f)).toDouble()
        val topPad = with(density) { WindowInsets.statusBars.getTop(density).toDp().value } + 56.0

        fun snap(to: Detent) { detent = to; scope.launch { sheet.animateTo(detentHeights.getValue(to) + navBar, spring(stiffness = 400f)) } }
        LaunchedEffect(vm.phase) { snap(Detent.Half) }

        val activity = if (vm.selectedMode == com.ranamaps.sdk.client.Mode.Walk) LocationActivity.Walking else LocationActivity.Vehicle
        val settings = remember(visibleBottom, topPad, inTrip, activity) {
            MapSettings(
                padding = MapPadding(top = topPad, bottom = visibleBottom),
                location = LocationOptions(
                    tracking = if (inTrip) LocationTracking.FollowHeading else LocationTracking.None,
                    appearance = if (inTrip) TravellerAppearance.Puck else TravellerAppearance.Dot, motion = LocationMotion.Smooth,
                    activity = if (inTrip) activity else LocationActivity.Generic, firstFixZoom = 16.5,
                ),
                events = MapEvents(
                    onLongPress = { vm.dropPickup(it) },
                    onTrackingChanged = { tracking = it },
                    onLocationRouteChanged = { vm.onRouteStatus(it) },
                    onReroutingChanged = { vm.onReroutingStatus(it) },
                    onRerouted = { installed[0] = it.path; vm.onRerouted(it.path) },
                    onError = { if (it.code == "permission_denied" || it.code == "location_unavailable") vm.onLocationOff() else vm.reportError("${it.code}: ${it.message}") },
                ),
            )
        }
        // Keep center/zoom constant: they are the initial camera, and changing them later moves the camera.
        RanaMap(
            modifier = Modifier.fillMaxSize(), center = DefaultPickup, zoom = 12.0,
            controls = ControlsOptions(), settings = settings,
        ) { controller = it }

        controller?.let { map ->
            MapEffects(vm, map, installed, detent)
            // The sheet is the one source of truth for the visible map area, in every state.
            LaunchedEffect(map) { snapshotFlow { sheet.value + (ime - navBar).coerceAtLeast(0f) }.collect { map.setPadding(MapPadding(top = topPad, bottom = it.toDouble())) } }
        }

        Column(Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Surface(shape = RoundedCornerShape(50), color = Color(0xFF1B1F3B).copy(alpha = 0.92f), contentColor = Color.White, shadowElevation = 4.dp) {
                Text(if (vm.movement == Movement.Simulated) "SIMULATED movement · demo only · no real ride" else "DEVICE GPS movement · demo only · no real ride", Modifier.padding(horizontal = 14.dp, vertical = 8.dp), fontSize = 12.sp)
            }
            if (vm.locationOff) Surface(shape = RoundedCornerShape(50), color = Color(0xFFFFF4D6), contentColor = Color(0xFF6B4B00), shadowElevation = 4.dp) {
                Text("Location off — using Lagos", Modifier.padding(horizontal = 14.dp, vertical = 6.dp), fontSize = 12.sp)
            }
        }

        if (vm.phase != Phase.Options && (inTrip || vm.deviceFix != null) && tracking != followTarget) {
            FilledTonalButton(
                onClick = { controller?.setTracking(followTarget) },
                modifier = Modifier.align(Alignment.BottomEnd).padding(end = 16.dp, bottom = (sheetDp + 12).dp),
            ) { Text("Re-centre") }
        }

        Surface(
            Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(sheetDp.dp).offset(y = -with(density) { (ime - navBar).coerceAtLeast(0f).dp }),
            shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp), shadowElevation = 12.dp, color = MaterialTheme.colorScheme.surface,
        ) {
            Column(Modifier.navigationBarsPadding()) {
                Box(
                    Modifier.fillMaxWidth().height(28.dp).pointerInput(maxH, navBar) {
                        var total = 0f
                        detectVerticalDragGestures(
                            onDragStart = { total = 0f },
                            onDragEnd = {
                                val h = sheet.value - navBar
                                val target = detentHeights.minBy { kotlin.math.abs(it.value - (h - total / density.density * 0.3f)) }.key
                                snap(target)
                            },
                        ) { change, drag ->
                            change.consume(); total += drag
                            val h = (sheet.value - drag / density.density).coerceIn(detentHeights.getValue(Detent.Collapsed) + navBar, detentHeights.getValue(Detent.Expanded) + navBar)
                            scope.launch { sheet.snapTo(h) }
                        }
                    },
                    contentAlignment = Alignment.Center,
                ) { Box(Modifier.width(40.dp).height(5.dp).background(Color(0xFFC9CDDA), RoundedCornerShape(3.dp))) }
                SheetContent(vm, onDetent = ::snap)
            }
        }
    }
}

/** Everything the screen draws on, or tells, the map. */
@Composable
private fun MapEffects(vm: TripViewModel, map: RanaMapController, installed: Array<List<LatLng>?>, detent: Detent) {
    val selected = vm.selected
    val tripRoute = vm.tripRoute
    val sdkRoute = vm.sdkRoute
    val wrong = vm.wrongRoute
    val phase = vm.phase
    // While idle the pickup follows the live location, which the dot already shows; mark it only once it is fixed or pinned.
    val pickup = vm.pickup.takeIf { phase != Phase.Idle || vm.pickupIsPin }

    DisposableEffect(map, phase, vm.options, vm.selectedMode, tripRoute, if (wrong) sdkRoute else null, pickup, vm.destination) {
        val items = mutableListOf<() -> Unit>()
        fun track(remove: () -> Unit) { items.add(remove) }
        pickup?.let { p -> track(map.addMarker(p, MarkerContent.Dot, MarkerStyle(color = "#1B8F4B", accessibilityLabel = "Pickup")).let { x -> { x.remove() } }) }
        vm.destination?.let { d -> track(map.addMarker(d.point, MarkerContent.Pin(PinGlyph.Flag), MarkerStyle(accessibilityLabel = d.name)).let { x -> { x.remove() } }) }
        when (phase) {
            Phase.Options -> {
                vm.options.filter { it.mode != vm.selectedMode }.forEach { o ->
                    track(map.addPolyline(o.points, PolylineOptions(preset = PolylinePreset.Alternative, mode = o.mode, opacity = 0.55f)).let { x -> { x.remove() } })
                }
                selected?.let { o -> track(map.addPolyline(o.points, PolylineOptions(mode = o.mode, arrows = true)).let { x -> { x.remove() } }) }
            }
            Phase.Trip -> {
                track(map.addPolyline(tripRoute, PolylineOptions(mode = vm.selectedMode, arrows = true)).let { x -> { x.remove() } })
                if (wrong && sdkRoute != null) track(map.addPolyline(sdkRoute, PolylineOptions(color = "#D93025", dash = LineDash.Dashed, widthDp = 4f, arrows = false)).let { x -> { x.remove() } })
            }
            Phase.Idle -> Unit
        }
        onDispose { items.forEach { it() } }
    }

    // Frame the pickup and destination inside the visible map above the sheet. The SDK's follow camera takes over in a trip.
    LaunchedEffect(map, phase, selected?.points, detent) {
        if (phase == Phase.Options && selected != null) { delay(350); map.fitPoints(selected.points + listOfNotNull(vm.pickup), 40) }
    }

    LaunchedEffect(map) { vm.fixes.collect { map.updateLocation(it) } }

    // Hand the route being navigated to the SDK; rerouting only after the route, because setLocationRoute clears it.
    LaunchedEffect(map, phase, sdkRoute, vm.autoReroute) {
        if (phase == Phase.Trip && sdkRoute != null) {
            if (installed[0] !== sdkRoute) { map.setLocationRoute(sdkRoute); installed[0] = sdkRoute; map.setAutomaticRerouting(null) }
            val dest = vm.destination
            val client = vm.newClient()
            if (vm.autoReroute && dest != null && client != null) {
                if (map.reroutingStatus.state == ReroutingState.Disabled)
                    map.setAutomaticRerouting(ReroutingOptions(Location.Point(dest.point), vm.selectedMode), DirectionsReroutingProvider(client))
            } else if (map.reroutingStatus.state != ReroutingState.Disabled) map.setAutomaticRerouting(null)
        }
    }

    val wasTrip = remember { booleanArrayOf(false) }
    LaunchedEffect(map, phase) {
        if (phase == Phase.Trip) wasTrip[0] = true
        else {
            installed[0] = null
            map.setAutomaticRerouting(null); map.setLocationRoute(null); map.setTracking(LocationTracking.None)
            if (wasTrip[0]) {
                wasTrip[0] = false
                // Without a native provider the simulated puck would stay at the destination.
                if (vm.locationGranted != true) map.hideUserLocation()
                map.setCamera(CameraOptions(center = vm.pickup ?: DefaultPickup, zoom = 16.5, bearing = 0.0, pitch = 0.0))
            }
        }
    }

    // One location source at a time: the fake socket owns the puck during a simulated trip, the native provider otherwise.
    // Declared after the effect above so a finished trip clears its route and tracking before the provider reconnects.
    val nativeLocation = vm.locationGranted == true && !(phase == Phase.Trip && vm.movement == Movement.Simulated)
    LaunchedEffect(map, nativeLocation) { map.setLocationProvider(if (nativeLocation) vm.provider else null) }
}
