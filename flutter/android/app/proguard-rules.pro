# Cross-APK test classes are loaded reflectively by instrumentation.
# Applied only when ranaTestBuildType=release; Rana SDK code uses its shipped consumer rules.
-keep class dev.flutter.plugins.integration_test.** { *; }
-keep class androidx.test.** { *; }
-keep class org.junit.** { *; }

# The separate test APK creates a cached engine before starting Dart.
-keep class io.flutter.embedding.engine.FlutterEngine { public *; }
-keep class io.flutter.embedding.engine.FlutterEngineCache { public *; }
-keep class io.flutter.embedding.engine.dart.DartExecutor { public *; }
-keep class io.flutter.embedding.engine.dart.DartExecutor$DartEntrypoint { public *; }
-keep interface io.flutter.embedding.engine.plugins.PluginRegistry { public *; }
