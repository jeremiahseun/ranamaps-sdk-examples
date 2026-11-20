package com.ranamaps.sdk.sample

import android.graphics.Bitmap
import android.graphics.Rect
import android.view.View
import android.view.ViewGroup
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import java.io.File

/** Runs the actual SDK sample and renderer. Fixture interactions do not require a live directions grant. */
class JourneyInteractionTest {
    @get:Rule val app = createAndroidComposeRule<SampleActivity>()

    private fun click(text: String) {
        val node = app.onNodeWithText(text)
        try { node.assertIsDisplayed() } catch (_: AssertionError) { node.performScrollTo() }
        node.performClick()
    }
    private fun screenshot(name: String) {
        app.waitForIdle()
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val file = File(instrumentation.targetContext.getExternalFilesDir("verification"), "$name.png")
        file.parentFile!!.mkdirs()
        file.outputStream().use { instrumentation.uiAutomation.takeScreenshot().compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
    private fun credit(): View? {
        fun find(view: View): View? {
            if (view.contentDescription?.startsWith("Rana. ") == true) return view
            if (view is ViewGroup) for (index in 0 until view.childCount) find(view.getChildAt(index))?.let { return it }
            return null
        }
        return find(app.activity.window.decorView)
    }
    private fun waitForMap() {
        app.waitUntil(timeoutMillis = 30000) {
            var ready = false
            InstrumentationRegistry.getInstrumentation().runOnMainSync { ready = credit() != null }
            ready
        }
    }
    private fun assertCreditAboveSheet() {
        waitForMap()
        val top = app.onNodeWithTag("journey-sheet").fetchSemanticsNode().boundsInRoot.top
        app.runOnIdle {
            val root = app.activity.findViewById<View>(android.R.id.content)
            val position = IntArray(2); root.getLocationOnScreen(position)
            val rect = Rect(); assertTrue("credit is visible", credit()!!.getGlobalVisibleRect(rect))
            assertTrue("credit must be above the bottom sheet: $rect, sheet=$top, root=${position[1]}", rect.bottom <= top + position[1] + 1)
        }
    }
    @Test fun tracePreviewBuffersSimulatedFixesAndStopsOnReset() {
        waitForMap()
        click("Corner demo"); click("Map tools")
        app.onNodeWithTag("trace-preview").performScrollTo().performClick()
        click("Trip"); click("Recenter"); click("Map tools")
        app.waitUntil(8000) { app.onAllNodesWithText("Simulated trace:", substring = true).fetchSemanticsNodes().any { node ->
            node.config.getOrElse(SemanticsProperties.Text) { emptyList() }.any { it.text.contains("buffered") && !it.text.contains(": 0 buffered") }
        } }
        app.onNodeWithText("Simulated trace:", substring = true).assertTextContains("0 learned", substring = true)
        click("Trip"); click("Reset demo"); click("Map tools")
        app.onNodeWithText("Trace preview: off").performScrollTo().assertIsDisplayed()
        app.onNodeWithTag("trace-preview").assertIsOff()
        screenshot("android-simulated-trace-preview")
    }
    @Test fun connectedMotionCourseWalkingAndCancellation() {
        waitForMap()
        var controller: com.ranamaps.sdk.map.RanaMapController? = null
        app.runOnIdle {
            fun find(view: View): com.ranamaps.sdk.map.RanaMapController? {
                if (view is com.ranamaps.sdk.map.RanaMapView) return view.controller
                if (view is ViewGroup) for (i in 0 until view.childCount) find(view.getChildAt(i))?.let { return it }
                return null
            }
            controller = find(app.activity.window.decorView)
            controller!!.setLocationProvider(null)
            controller!!.hideUserLocation()
            controller!!.applySettings(com.ranamaps.sdk.map.MapSettings(location = com.ranamaps.sdk.map.LocationOptions(
                tracking = com.ranamaps.sdk.map.LocationTracking.FollowHeading, mode = com.ranamaps.sdk.map.LocationMode.Puck,
                motion = com.ranamaps.sdk.map.LocationMotion.Smooth, activity = com.ranamaps.sdk.map.LocationActivity.Vehicle)))
            val now = System.currentTimeMillis()
            controller!!.updateLocation(com.ranamaps.sdk.map.LocationFix(com.ranamaps.sdk.client.LatLng(6.5, 3.4), heading = 359.0, timestampMs = now - 1000))
            controller!!.updateLocation(com.ranamaps.sdk.map.LocationFix(com.ranamaps.sdk.client.LatLng(6.501, 3.4), heading = 1.0, timestampMs = now))
        }
        var latitude = 0.0
        app.waitUntil(3000) {
            InstrumentationRegistry.getInstrumentation().runOnMainSync { latitude = controller!!.center.lat }
            latitude > 6.50001
        }
        assertTrue("the native follow camera must render an intermediate position", latitude < 6.501)
        app.runOnIdle {
            controller!!.setLocationRoute(listOf(com.ranamaps.sdk.client.LatLng(6.5, 3.4), com.ranamaps.sdk.client.LatLng(6.501, 3.4), com.ranamaps.sdk.client.LatLng(6.501, 3.401)))
            val now = System.currentTimeMillis()
            controller!!.updateLocation(com.ranamaps.sdk.map.LocationFix(com.ranamaps.sdk.client.LatLng(6.5005, 3.4), heading = 0.0, timestampMs = now - 1000))
            controller!!.updateLocation(com.ranamaps.sdk.map.LocationFix(com.ranamaps.sdk.client.LatLng(6.501, 3.4005), heading = 90.0, timestampMs = now))
        }
        var longitude = 0.0
        app.waitUntil(3000) {
            InstrumentationRegistry.getInstrumentation().runOnMainSync { latitude = controller!!.center.lat; longitude = controller!!.center.lng }
            latitude > 6.5006
        }
        assertTrue("route-aware native camera must stay on a route segment", kotlin.math.abs(longitude - 3.4) < .000001 || kotlin.math.abs(latitude - 6.501) < .000001)
        app.runOnIdle {
            assertEquals(com.ranamaps.sdk.map.LocationRouteState.Matched, controller!!.locationRouteStatus.state)
            controller!!.setLocationRoute(null)
            controller!!.hideUserLocation()
            controller!!.applySettings(com.ranamaps.sdk.map.MapSettings(location = com.ranamaps.sdk.map.LocationOptions(
                tracking = com.ranamaps.sdk.map.LocationTracking.FollowHeading, mode = com.ranamaps.sdk.map.LocationMode.Puck,
                motion = com.ranamaps.sdk.map.LocationMotion.Smooth, activity = com.ranamaps.sdk.map.LocationActivity.Walking)))
            controller!!.updateLocation(com.ranamaps.sdk.map.LocationFix(com.ranamaps.sdk.client.LatLng(6.5, 3.4), heading = 90.0))
            controller!!.updateDeviceHeading(com.ranamaps.sdk.map.HeadingFix(45.0, 5.0))
            assertEquals(45.0, controller!!.cameraState.bearing, .01)
            controller!!.hideUserLocation()
        }
    }
    @Test fun optionalAutomaticReroutingUsesLiveDirections() {
        org.junit.Assume.assumeTrue(InstrumentationRegistry.getArguments().getString("liveServices") == "true")
        waitForMap(); click("Corner demo"); click("Start simulation"); click("Map tools")
        app.onNodeWithTag("automatic-rerouting").performScrollTo().performClick()
        click("Simulate GPS detour")
        app.waitUntil(35000) { app.onAllNodesWithText("Automatic reroute loaded. Movement remains simulated.").fetchSemanticsNodes().isNotEmpty() }
        app.onNodeWithText("Live route · simulated movement · no booking").assertExists()
        app.onNodeWithText("Route match: Matched").assertExists()
        click("Trip"); click("Pause")
        screenshot("android-automatic-reroute")
    }
    @Test fun routeMatchingDetourRecoveryAndToggle() {
        waitForMap(); click("Corner demo")
        app.onNodeWithText("Route match: Matched").assertExists()
        click("Map tools"); click("Simulate GPS detour")
        app.onNodeWithText("Route match: Off route").assertExists()
        click("Rejoin route"); app.onNodeWithText("Route match: Matched").assertExists()
        app.onNodeWithTag("route-aware").performScrollTo().performClick()
        app.onNodeWithText("Route match: None").assertExists()
        app.onNodeWithTag("route-aware").performClick()
        app.onNodeWithText("Route match: Matched").assertExists()
        screenshot("android-route-aware")
    }
    @Test fun journeyPlaybackScrubArrivalReplayAndReset() {
        waitForMap()
        app.runOnIdle {
            fun containsTexture(view: View): Boolean = view is android.view.TextureView ||
                (view is ViewGroup && (0 until view.childCount).any { containsTexture(view.getChildAt(it)) })
            assertTrue("native map must compose with host overlays", containsTexture(app.activity.window.decorView))
        }
        app.onNodeWithText("Explore Lagos").assertIsDisplayed()
        app.onNodeWithText("Where are you going?").assertIsDisplayed()
        click("Ikeja")
        app.onNodeWithText("Ikeja").assertExists()
        app.onNodeWithText("Illustrative route · simulated movement · no booking").assertExists()
        app.onNodeWithText("Start simulation").performScrollTo()
        app.mainClock.autoAdvance = false
        click("Start simulation")
        app.mainClock.advanceTimeBy(1200)
        app.onNodeWithText("Pause").assertExists()
        click("Pause"); app.mainClock.advanceTimeByFrame(); app.mainClock.autoAdvance = true
        app.onNodeWithText("Simulation paused").assertExists()
        click("Recenter")
        app.onNode(SemanticsMatcher.keyIsDefined(SemanticsProperties.ProgressBarRangeInfo))
            .performSemanticsAction(SemanticsActions.SetProgress) { it(1f) }
        app.onNodeWithText("You have arrived").assertExists()
        click("Start simulation")
        app.onNodeWithText("Trip in progress").assertExists()
        click("Pause")
        click("Reset demo")
        app.onNodeWithText("Where are you going?").assertExists()
        click("Marina"); click("Walk"); click("Rotate sample phone")
        app.onNodeWithText("Walking compass · sample phone 45°").assertExists()
        app.onNodeWithText("Marina").assertExists()
        screenshot("android-journey")
    }
    @Test fun draggedSheetAndCompactAttribution() {
        assertCreditAboveSheet()
        app.onNodeWithTag("sheet-handle").performTouchInput { swipeUp() }
        assertCreditAboveSheet()
        app.runOnIdle { credit()!!.performClick(); assertTrue(credit()!!.isSelected) }
        screenshot("android-attribution-expanded")
        app.waitUntil(timeoutMillis = 7000) {
            var collapsed = false
            InstrumentationRegistry.getInstrumentation().runOnMainSync { collapsed = credit()?.isSelected == false }
            collapsed
        }
        click("Map tools")
        app.onNodeWithTag("smooth-movement").performScrollTo().performClick()
        app.onNodeWithText("Vehicle course · direct movement").assertExists()
        app.onNodeWithTag("smooth-movement").performClick()
        click("Move Rana credit to right")
        assertCreditAboveSheet()
        click("Restore left credit and fit")
        assertCreditAboveSheet()
        app.runOnIdle {
            fun find(view: View): View? {
                if (view.contentDescription?.toString() in listOf("Show my location", "Following your location", "Following your heading")) return view
                if (view is ViewGroup) for (index in 0 until view.childCount) find(view.getChildAt(index))?.let { return it }
                return null
            }
            val locate = find(app.activity.window.decorView) as ViewGroup
            val glyph = locate.getChildAt(0)
            val density = locate.resources.displayMetrics.density
            assertEquals("match the iOS 24-point glyph", 24f, glyph.width / density, 0.6f)
            assertTrue("retain a full touch target (${locate.width / density}dp)", locate.width + 1 >= 44f * density)
        }
        click("Night")
        app.onNodeWithText("Day").assertExists()
        click("3D")
        app.onNodeWithText("2D").assertExists()
        screenshot("android-map-tools")
    }
    @Test fun liveDirectionsAndOfflinePack() {
        org.junit.Assume.assumeTrue("Enable explicitly for real service usage",
            InstrumentationRegistry.getArguments().getString("liveServices") == "true")
        waitForMap()
        click("Ikeja"); click("Load live directions")
        app.waitUntil(timeoutMillis = 30000) {
            app.onAllNodesWithText("Live route · simulated movement · no booking").fetchSemanticsNodes().isNotEmpty()
        }
        screenshot("android-live-route")
        click("Map tools"); click("Download small map area")
        app.waitUntil(timeoutMillis = 30000) {
            app.onAllNodesWithText("Offline download:", substring = true).fetchSemanticsNodes().isNotEmpty() ||
                app.onAllNodesWithText("Offline pack ready.").fetchSemanticsNodes().isNotEmpty()
        }
        click("Pause download")
        app.onNodeWithText("Offline download paused.").assertExists()
        click("Delete downloaded area")
        app.waitUntil(10000) { app.onAllNodesWithText("Offline pack deleted.").fetchSemanticsNodes().isNotEmpty() }
        screenshot("android-offline-pack-deleted")
    }

}
