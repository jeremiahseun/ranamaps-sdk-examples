package com.ranamaps.sdk.sample

import android.os.SystemClock
import androidx.test.core.app.ActivityScenario
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class InitialStyleRecoveryTest {
    @Test fun failedInitialStyleCanBeReplacedWithoutRecreatingTheView() {
        assumeFalse("A native-restricted public key is needed for real style loading", BuildConfig.RANA_KEY.contains("replace"))
        ActivityScenario.launch(StyleRecoveryTestActivity::class.java).use { scenario ->
            var errors = 0; var ready = 0
            fun state() { scenario.onActivity { errors = it.errors; ready = it.ready } }
            fun waitFor(condition: () -> Boolean) {
                val end = SystemClock.elapsedRealtime() + 30000
                while (!condition() && SystemClock.elapsedRealtime() < end) { SystemClock.sleep(100); state() }
                assertTrue("Timed out: errors=$errors ready=$ready", condition())
            }
            waitFor { errors > 0 }; assertEquals(0, ready)
            scenario.onActivity { it.useDayStyle() }
            waitFor { ready == 1 }; assertEquals(1, ready)
        }
    }
}
