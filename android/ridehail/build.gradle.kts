plugins {
    id("com.android.application")
    kotlin("android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.ranamaps.sdk.ridehail"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.ranamaps.sdk.ridehail"
        minSdk = 26
        targetSdk = 37
        versionCode = 1
        versionName = "0.4.0-beta.0"
        manifestPlaceholders["ranaKey"] = project.findProperty("ranaKey") ?: "pk_live_replace_me"
        // A public key limited to this package and its signing certificate: -PranaKey=pk_live_…
        buildConfigField("String", "RANA_KEY", "\"${project.findProperty("ranaKey") ?: "pk_live_replace_me"}\"")
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin { jvmToolchain(17) }

dependencies {
    implementation("com.ranamaps:maps-android:0.4.0-beta.0")
    val composeBom = platform("androidx.compose:compose-bom:2025.12.00")
    implementation(composeBom)
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
}
