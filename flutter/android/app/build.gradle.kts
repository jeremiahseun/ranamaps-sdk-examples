plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.ranamaps.rana_maps_example"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion
    testBuildType = providers.gradleProperty("ranaTestBuildType").getOrElse("debug")

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ranamaps.rana_maps_example"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        manifestPlaceholders["ranaApiKey"] = providers.environmentVariable("RANA_PUBLIC_KEY").orElse("").get()
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            if (providers.gradleProperty("ranaTestBuildType").orNull == "release") {
                proguardFiles("proguard-rules.pro")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    if (providers.gradleProperty("ranaTestBuildType").orNull == "release") {
        // Flutter omits native dev-dependency plugins from ordinary release apps.
        add("releaseImplementation", project(":integration_test"))
        add("releaseImplementation", "androidx.test:runner:1.7.0")
    }
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test:rules:1.2.0")
}
