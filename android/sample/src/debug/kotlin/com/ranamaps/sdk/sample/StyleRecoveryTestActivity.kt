package com.ranamaps.sdk.sample

import android.app.Activity
import android.os.Bundle
import com.ranamaps.sdk.client.LatLng
import com.ranamaps.sdk.map.*

/** Debug-only native-view host for initial-style failure/replacement instrumentation. */
class StyleRecoveryTestActivity : Activity() {
    private lateinit var view: RanaMapView
    @Volatile var errors = 0
    @Volatile var ready = 0
    private val settings = MapSettings(events = MapEvents(onError = { errors++ }))
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        view = RanaMapView(this); setContentView(view); view.setSettings(settings)
        view.start(style = RanaStyle.Studio("23456789"), telemetry = false) { ready++ }
    }
    fun useDayStyle() {
        view.update(RanaStyle.Day, LatLng(6.5244, 3.3792), 11.0, ControlsOptions(), false, settings) { ready++ }
    }
    override fun onStart() { super.onStart(); view.onStart() }
    override fun onResume() { super.onResume(); view.onResume() }
    override fun onPause() { view.onPause(); super.onPause() }
    override fun onStop() { view.onStop(); super.onStop() }
    override fun onDestroy() { view.onDestroy(); super.onDestroy() }
}
