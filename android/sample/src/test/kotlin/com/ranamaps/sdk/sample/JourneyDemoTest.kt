package com.ranamaps.sdk.sample

import org.junit.Assert.*
import org.junit.Test

class JourneyDemoTest {
    @Test fun journeySelectionAndReplay() {
        val selected = JourneyDemo().select(demoDestinations.first())
        assertEquals(DemoPhase.Preview, selected.phase)
        assertFalse(selected.liveRoute)
        assertEquals(demoPickup, selected.pointAt(0f))
        assertEquals(selected.destination!!.point, selected.pointAt(1f))
        val arrived = selected.copy(phase = DemoPhase.Running).advance(2f)
        assertEquals(DemoPhase.Arrived, arrived.phase)
        assertEquals(1f, arrived.progress)
        assertEquals(DemoPhase.Paused, arrived.advance(.5f).phase)
        assertEquals(0f, selected.advance(-1f).progress)
        assertEquals(0f, arrived.select(demoDestinations.last()).progress)
    }
    @Test fun stoppedReplayProviderDoesNotDeliverFixes() {
        val provider = DemoLocationProvider()
        var count = 0
        provider.start({ count++ }, { fail(it.toString()) })
        provider.emit(demoPickup)
        provider.stop()
        provider.emit(demoPickup)
        assertEquals(1, count)
    }
}
