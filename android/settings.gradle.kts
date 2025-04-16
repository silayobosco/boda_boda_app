pluginManagement {
    plugins {
        //id("com.android.application") version "8.9.1" apply false
        //id("com.android.library") version "8.9.1" apply false
        //id("org.jetbrains.kotlin.android") version "2.1.10" apply false
        //id("com.google.gms.google-services") version "4.4.2" apply false 
    }
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        maven { 
            url = uri("https://storage.googleapis.com/download.flutter.io") 
            url = uri("https://api.mapbox.com/downloads/v2/releases/maven")
            credentials {
                username = "mapbox"
                password = providers.gradleProperty("MAPBOX_DOWNLOADS_TOKEN").get()
            }
            authentication {
                create<BasicAuthentication>("basic")
            }
        }
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    //START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.4.2") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
}

include(":app")
