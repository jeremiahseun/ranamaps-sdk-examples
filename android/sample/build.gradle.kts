plugins {
    id("com.android.application")
    kotlin("android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.ranamaps.sdk.sample"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.ranamaps.sdk.sample"
        minSdk = 26
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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
    testImplementation("junit:junit:4.13.2")
    implementation("com.ranamaps:maps-android:0.4.0-beta.0")
    val composeBom = platform("androidx.compose:compose-bom:2025.12.00")
    implementation(composeBom)
    androidTestImplementation(composeBom)
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
}
