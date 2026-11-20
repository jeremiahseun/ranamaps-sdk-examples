package com.ranamaps.rana_maps_example;

import android.content.Intent;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.rule.ActivityTestRule;
import dev.flutter.plugins.integration_test.FlutterTestRunner;
import dev.flutter.plugins.integration_test.IntegrationTestPlugin;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.embedding.engine.dart.DartExecutor;
import org.junit.Rule;
import org.junit.runner.RunWith;

@RunWith(FlutterTestRunner.class)
public class MainActivityTest {
    private static final String ENGINE_ID = "rana-release-integration";
    private FlutterEngine engine;

    @Rule
    public ActivityTestRule<MainActivity> rule =
        new ActivityTestRule<MainActivity>(MainActivity.class, true, false) {
            @Override
            protected void beforeActivityLaunched() {
                // Flutter excludes dev plugins from a fresh release registrant.
                // Register the results channel before starting the Dart isolate.
                InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
                    engine = new FlutterEngine(
                        InstrumentationRegistry.getInstrumentation().getTargetContext());
                    if (!engine.getPlugins().has(IntegrationTestPlugin.class)) {
                        engine.getPlugins().add(new IntegrationTestPlugin());
                    }
                    FlutterEngineCache.getInstance().put(ENGINE_ID, engine);
                    engine.getDartExecutor().executeDartEntrypoint(
                        DartExecutor.DartEntrypoint.createDefault());
                });
            }

            @Override
            protected Intent getActivityIntent() {
                return new Intent(
                    InstrumentationRegistry.getInstrumentation().getTargetContext(),
                    MainActivity.class).putExtra("cached_engine_id", ENGINE_ID);
            }

        };
}
