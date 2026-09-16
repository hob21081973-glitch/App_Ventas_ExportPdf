plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    ...
    defaultConfig {
        applicationId = "com.example.app_ventas_export_pdf" // Tu ID de paquete
        
        // 1. IMPORTANTE: minSdk en 21 para soportar SQLite y PDF
        minSdk = 21 
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // 2. IMPORTANTE: Desactivar minificación para que no borre las librerías nativas
            isMinifyEnabled = false
            isShrinkResources = false
            
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
