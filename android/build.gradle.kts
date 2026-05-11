group = "com.example.flutter_usb_camera_package"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.2.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.11.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
    id("kotlin-android")
}

android {
    namespace = "com.example.flutter_usb_camera_package"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
            // This ensures Gradle sees your C/C++ files
            jni.srcDirs("src/main/jni")
        }
    }

defaultConfig {
        minSdk = 24

        ndk {
            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a", "x86_64"))
        }

        externalNativeBuild {
            ndkBuild {
                // 1. THIS IS THE MAGIC LINE:
                // Tell Gradle to only monitor our final engine library.
                targets("usb_camera_engine") 

                // 2. Keep your existing path logic
                val rawPath = System.getenv("GSTREAMER_ROOT_ANDROID") 
                    ?: "C:/gstreamer-1.0-android-universal-1.28.2"
                
                val gstRoot = rawPath.replace("\\", "/")
                
                arguments("GSTREAMER_ROOT_ANDROID=$gstRoot")
            }
        }
    }

    // 3. Point to your Android.mk file
    externalNativeBuild {
        ndkBuild {
            path = file("src/main/jni/Android.mk")
        }
    }
}

dependencies {
    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
}
