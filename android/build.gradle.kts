//plugins {
    //id ("com.android.library")
   // id("com.android.application") version "8.9.1" //apply false
    // START: FlutterFire Configuration
  //  id("com.google.gms.google-services") version "4.4.2" apply false
    // END: FlutterFire Configuration
    //id("kotlin-android")
  //  id("org.jetbrains.kotlin.android") version "2.1.10" apply false
    //id("dev.flutter.flutter-gradle-plugin") //version "83.0.4"
//}


buildscript {
    repositories {
        google()
        mavenCentral()
    }
   
    dependencies {
        val kotlinVersion = "2.1.10" // Correctly defined
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion") // Corrected line!
        classpath("com.android.tools.build:gradle:8.1.0")
        classpath("com.google.gm" + "s:google-services:4.4.2")
        //classpath ("com.android.tools.build:gradle:8.1.0")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
