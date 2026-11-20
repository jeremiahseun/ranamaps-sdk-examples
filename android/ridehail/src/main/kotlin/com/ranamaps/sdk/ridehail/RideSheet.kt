package com.ranamaps.sdk.ridehail

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ranamaps.sdk.client.Mode
import java.text.NumberFormat
import java.util.Locale

@Composable
internal fun SheetContent(vm: TripViewModel, onDetent: (Detent) -> Unit) {
    Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        when (vm.phase) {
            Phase.Idle -> Idle(vm)
            Phase.Options -> Options(vm)
            Phase.Trip -> Trip(vm)
        }
        vm.error?.let { Text(it, color = MaterialTheme.colorScheme.error, fontSize = 13.sp) }
    }
}

@Composable
private fun Idle(vm: TripViewModel) {
    Text("Where to?", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
    OutlinedTextField(
        value = vm.query, onValueChange = vm::onQuery, modifier = Modifier.fillMaxWidth(), singleLine = true,
        placeholder = { Text("Search destination in Lagos") }, shape = RoundedCornerShape(14.dp),
        trailingIcon = { if (vm.searching) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) },
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(onSearch = { vm.onQuery(vm.query) }),
    )
    PickupRow(vm)
    vm.suggestions.forEach { s ->
        Row(Modifier.fillMaxWidth().clickable(enabled = vm.pickup != null) { vm.choose(s) }.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(36.dp), contentAlignment = Alignment.Center) { Text("●", color = MaterialTheme.colorScheme.primary, fontSize = 12.sp) }
            Column { Text(s.name, fontWeight = FontWeight.Medium); if (s.secondary.isNotBlank()) Text(s.secondary, fontSize = 13.sp, color = Color(0xFF5A6075)) }
        }
        HorizontalDivider(color = Color(0xFFEDEFF5))
    }
    if (vm.suggestions.isNotEmpty()) vm.attribution?.let { Text(it, fontSize = 11.sp, color = Color(0xFF8A90A5)) }
    if (!vm.hasClient) Text("No Rana key: build with -PranaKey=pk_live_… to search and route.", fontSize = 13.sp)
}

@Composable
private fun PickupRow(vm: TripViewModel) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text("Pickup", fontSize = 12.sp, color = Color(0xFF5A6075))
            val p = vm.pickup
            Text(when {
                p == null -> "Waiting for location…"
                vm.pickupIsPin -> "Dropped pin · %.4f, %.4f".format(p.lat, p.lng)
                vm.deviceFix == null -> "Lagos (Ikeja) · long-press the map to change"
                else -> "Your location · long-press the map to change"
            }, fontSize = 14.sp)
        }
        if (vm.pickupIsPin) TextButton(onClick = vm::resetPickup) { Text("Reset") }
    }
}

@Composable
private fun Options(vm: TripViewModel) {
    val dest = vm.destination
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(dest?.name ?: "", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, maxLines = 1)
            if (!dest?.detail.isNullOrBlank()) Text(dest!!.detail, fontSize = 13.sp, color = Color(0xFF5A6075), maxLines = 1)
        }
        TextButton(onClick = vm::backToIdle) { Text("Change") }
    }
    PickupRow(vm)
    if (vm.loadingOptions) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) { CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp); Text("Finding routes…") }
    vm.options.forEach { o ->
        val on = o.mode == vm.selectedMode
        OutlinedCard(
            onClick = { vm.select(o.mode) }, shape = RoundedCornerShape(16.dp),
            border = BorderStroke(if (on) 2.dp else 1.dp, if (on) MaterialTheme.colorScheme.primary else Color(0xFFD9DCE8)),
            colors = CardDefaults.outlinedCardColors(containerColor = if (on) Color(0xFFF1F3FB) else Color.White),
        ) {
            Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(if (o.mode == Mode.Car) "Car" else "Okada", fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
                    Text("${o.etaMinutes} min · %.1f km".format(o.distanceKm), fontSize = 13.sp, color = Color(0xFF5A6075))
                }
                Text(naira(o.priceNaira), fontWeight = FontWeight.Bold, fontSize = 18.sp)
            }
        }
    }
    Text("Prices are illustrative estimates.", fontSize = 11.sp, color = Color(0xFF8A90A5))
    Text("Movement during the trip", fontSize = 12.sp, color = Color(0xFF5A6075))
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        FilterChip(selected = vm.movement == Movement.Simulated, onClick = { vm.chooseMovement(Movement.Simulated) }, label = { Text("Simulated") })
        FilterChip(selected = vm.movement == Movement.DeviceGps, onClick = { vm.chooseMovement(Movement.DeviceGps) }, enabled = vm.locationGranted == true, label = { Text("Device GPS") })
    }
    Button(onClick = vm::confirm, enabled = vm.selected != null, modifier = Modifier.fillMaxWidth().height(52.dp), shape = RoundedCornerShape(14.dp)) {
        Text(vm.selected?.let { "Confirm ${if (it.mode == Mode.Car) "Car" else "Okada"} · ${naira(it.priceNaira)}" } ?: "Confirm")
    }
}

@Composable
private fun Trip(vm: TripViewModel) {
    val info = vm.info
    Text(if (info.arrived) "You have arrived" else "On the way to ${vm.destination?.name ?: "destination"}", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
    val simulated = vm.movement == Movement.Simulated
    Text(if (simulated) "Simulated driver · fake websocket · ${vm.selectedMode.name}" else "Device GPS · ${vm.selectedMode.name}", fontSize = 12.sp, color = Color(0xFF5A6075))
    Surface(shape = RoundedCornerShape(14.dp), color = MaterialTheme.colorScheme.primary, contentColor = Color.White) {
        Column(Modifier.fillMaxWidth().padding(14.dp)) {
            Text(info.instruction ?: "Follow the route", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            info.instructionInM?.let { Text("in ${distance(it)}", fontSize = 13.sp) }
        }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Stat("Remaining", distance(info.remainingM), Modifier.weight(1f))
        Stat("ETA", "${(info.etaS / 60.0).let { kotlin.math.ceil(it).toInt() }} min", Modifier.weight(1f))
    }
    Stat("Route status (SDK)", vm.routeStatus, Modifier.fillMaxWidth(), highlight = vm.routeStatus.startsWith("off"))
    Stat("Automatic rerouting", vm.rerouting, Modifier.fillMaxWidth())
    if (simulated) Text("Socket: ${vm.frames} frames${vm.droppedNote?.let { " · $it" } ?: ""}", fontSize = 12.sp, color = Color(0xFF5A6075))
    else Text("Device fixes: ${vm.frames}", fontSize = 12.sp, color = Color(0xFF5A6075))
    if (simulated && vm.lastFrame.isNotEmpty()) Text(vm.lastFrame, fontSize = 10.sp, fontFamily = FontFamily.Monospace, color = Color(0xFF8A90A5))

    HorizontalDivider(color = Color(0xFFEDEFF5))
    Text(if (simulated) "Scenarios (simulation controls)" else "Scenarios", fontWeight = FontWeight.SemiBold)
    if (simulated) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedButton(onClick = { vm.dropUpdates(1) }, Modifier.weight(1f), enabled = !info.arrived) { Text("Drop next update", fontSize = 12.sp) }
        OutlinedButton(onClick = { vm.dropUpdates(3) }, Modifier.weight(1f), enabled = !info.arrived) { Text("Drop 3 updates", fontSize = 12.sp) }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedButton(onClick = vm::startWrongRoute, Modifier.weight(1f), enabled = !vm.wrongRoute && !info.arrived) { Text("Wrong route", fontSize = 12.sp) }
        OutlinedButton(onClick = vm::restoreRoute, Modifier.weight(1f), enabled = vm.wrongRoute) { Text("Restore route", fontSize = 12.sp) }
    }
    if (vm.wrongRoute) Text("The map shows the real route; the red dashed line is the wrong route given to setLocationRoute.", fontSize = 12.sp, color = Color(0xFFD93025))
    if (simulated) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Update interval", Modifier.weight(1f))
        FilterChip(selected = vm.intervalMs == 1_000L, onClick = { vm.setInterval(1_000) }, label = { Text("1 s") })
        FilterChip(selected = vm.intervalMs == 5_000L, onClick = { vm.setInterval(5_000) }, label = { Text("5 s") })
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) { Text("Automatic rerouting"); Text("Off by default. Uses real directions requests.", fontSize = 11.sp, color = Color(0xFF8A90A5)) }
        Switch(checked = vm.autoReroute, onCheckedChange = vm::toggleAutoReroute)
    }
    Button(
        onClick = vm::endTrip, modifier = Modifier.fillMaxWidth().height(52.dp), shape = RoundedCornerShape(14.dp),
        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFD93025)),
    ) { Text("End trip") }
}

@Composable
private fun Stat(label: String, value: String, modifier: Modifier, highlight: Boolean = false) {
    Surface(modifier, shape = RoundedCornerShape(12.dp), color = if (highlight) Color(0xFFFDECEA) else MaterialTheme.colorScheme.surfaceVariant) {
        Column(Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
            Text(label, fontSize = 11.sp, color = Color(0xFF5A6075))
            Text(value, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = if (highlight) Color(0xFFB3261E) else Color.Unspecified)
        }
    }
}

private fun naira(v: Int) = "₦" + NumberFormat.getIntegerInstance(Locale.US).format(v)
private fun distance(m: Int) = if (m >= 1000) "%.1f km".format(m / 1000.0) else "$m m"
