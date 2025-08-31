plugins {
    //id ("com.android.library")
    id("com.android.application") //version "8.9.1" //apply false
    // START: FlutterFire Configuration
    //d("com.google.gms.google-services") version "4.4.2"
    // END: FlutterFire Configuration
    id("kotlin-android")
    //The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("org.jetbrains.kotlin.android") //version "2.1.10"
    id("dev.flutter.flutter-gradle-plugin") //version "83.0.4"
}

dependencies {
    val kotlinVersion = "2.1.10"
    implementation("org.jetbrains.kotlin:kotlin-stdlib:$kotlinVersion")
    
    // Import the Firebase BoM
    implementation(platform("com.google.firebase:firebase-bom:33.12.0"))
    
    // TODO: Add the dependencies for Firebase products you want to use
    // When using the BoM, don't specify versions in Firebase dependencies
    implementation("com.google.firebase:firebase-auth:23.2.0")
    implementation("com.google.firebase:firebase-firestore:25.1.3")
    // https://firebase.google.com/docs/android/setup#available-libraries
    
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("com.google.firebase:firebase-analytics-ktx") // or implementation("com.google.firebase:firebase-analytics-ktx")

}

android {
    namespace = "com.bosco.bodaboda"//"com.example.boda_boda_app"
    compileSdk = 36 //flutter.compileSdkVersion
    ndkVersion = "27.0.12077973" //hapa nmebadili

    compileOptions {
        // Flag to enable support for the new language APIs
        isCoreLibraryDesugaringEnabled = true
        // Sets Java compatibility to Java 8

        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    //java {
        //toolchain {
            //languageVersion.set(JavaLanguageVersion.of(8))
        //}
    //}

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.bosco.bodaboda"//"com.bosco.boda_boda_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24 //hapa nmebadili
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro")
        }
    }
    sourceSets {
        getByName("main") {
            manifest.srcFile("src/main/AndroidManifest.xml")
        }
    }
}
flutter {
    source = "../.."
}

apply(plugin="com.google.gms.google-services")
