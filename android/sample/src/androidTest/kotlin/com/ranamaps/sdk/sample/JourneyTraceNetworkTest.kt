package com.ranamaps.sdk.sample

import androidx.test.platform.app.InstrumentationRegistry
import com.ranamaps.sdk.RanaError
import com.ranamaps.sdk.client.*
import com.ranamaps.sdk.map.*
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.net.URI

/** Real HTTP + PostGIS verification. Fixtures may only go to an explicitly supplied local tunnel. */
class JourneyTraceNetworkTest {
    @Test fun deployedEndpointValidatesSimulationWithoutLearning() = runBlocking {
        val key=InstrumentationRegistry.getArguments().getString("traceLiveKey")
        assumeTrue("Provide a native-restricted live key explicitly", key != null)
        val client=RanaClient(key!!,ClientIdentity.of(InstrumentationRegistry.getInstrumentation().targetContext))
        withContext(Dispatchers.Main) {
            val recorder=JourneyTraceRecorder(client,JourneyTraceOptions(true,JourneyTraceSource.Simulated,Mode.Car))
            val end=System.currentTimeMillis()
            repeat(17) { i -> recorder.record(LocationFix(LatLng(6.50045,3.9+i*.00005),accuracyMetres=5.0,timestampMs=end-8000+i*500)) }
            assertEquals(17,recorder.status.buffered);recorder.flush();assertEquals(0,recorder.status.buffered);assertEquals(0,recorder.status.uploaded);assertNull(recorder.status.error);recorder.stop()
        }
    }
    @Test fun isolatedMeasuredSimulationAndDeniedIdentityFlow() = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        val base = args.getString("traceVerifyUrl")
        val key = args.getString("traceVerifyKey")
        assumeTrue("Provide the isolated verification URL and key explicitly", base != null && key != null)
        require(URI(base!!).host in setOf("10.0.2.2", "127.0.0.1", "localhost"))
        val identity = ClientIdentity.of(InstrumentationRegistry.getInstrumentation().targetContext)
        val client = RanaClient(key!!, identity, baseUrl = base)
        withContext(Dispatchers.Main) {
            fun feed(recorder: JourneyTraceRecorder) {
                val end = System.currentTimeMillis()
                repeat(17) { index -> recorder.record(LocationFix(LatLng(6.50045, 3.9 + index * .00005), accuracyMetres = 5.0, timestampMs = end - 8000 + index * 500, speedMetresPerSecond = 5.0)) }
            }
            val measured = JourneyTraceRecorder(client, JourneyTraceOptions(true, JourneyTraceSource.Measured, Mode.Car))
            feed(measured); assertEquals(17, measured.status.buffered)
            measured.flush(); assertEquals(17, measured.status.uploaded); assertEquals(0, measured.status.buffered)
            measured.flush(); measured.stop(); assertTrue(measured.status.stopped)
            val simulated = JourneyTraceRecorder(client, JourneyTraceOptions(true, JourneyTraceSource.Simulated, Mode.Car))
            feed(simulated); simulated.flush(); assertEquals(0, simulated.status.uploaded); assertEquals(0, simulated.status.buffered); simulated.stop()
            val deniedClient = RanaClient(key, ClientIdentity("com.ranamaps.sdk.disallowed", identity.certSha256), baseUrl = base)
            val denied = JourneyTraceRecorder(deniedClient, JourneyTraceOptions(true, JourneyTraceSource.Measured))
            feed(denied)
            try { denied.flush(); fail("An unlisted native identity must fail") } catch (error: RanaError) { assertEquals(403, error.status) }
            assertEquals(17, denied.status.buffered); denied.stop(); assertEquals(0, denied.status.buffered)
        }
    }
}
