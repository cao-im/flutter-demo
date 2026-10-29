import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val umengProperties = Properties()
val umengPropertiesFile = rootProject.file("local.properties")
if (umengPropertiesFile.exists()) {
    umengPropertiesFile.inputStream().use { umengProperties.load(it) }
}

fun umengProperty(name: String): String = umengProperties.getProperty(name) ?: ""

android {
    namespace = "com.clb.caoim"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // ✅ 启用 core library desugaring（flutter_local_notifications 等插件需要）
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.clb.caoim"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 21)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 友盟和厂商参数写在 android/local.properties，不提交到仓库。
        manifestPlaceholders["UMENG_APPKEY"] = umengProperty("umeng.appkey")
        manifestPlaceholders["UMENG_MESSAGE_SECRET"] = umengProperty("umeng.message.secret")
        manifestPlaceholders["UMENG_CHANNEL"] = umengProperty("umeng.channel").ifBlank { "caoim" }
        manifestPlaceholders["HUAWEI_APP_ID"] = umengProperty("huawei.appid")
        manifestPlaceholders["HONOR_APP_ID"] = umengProperty("honor.appid")
        manifestPlaceholders["XIAOMI_APP_ID"] = umengProperty("xiaomi.appid")
        manifestPlaceholders["XIAOMI_APP_KEY"] = umengProperty("xiaomi.appkey")
        manifestPlaceholders["OPPO_APP_KEY"] = umengProperty("oppo.appkey")
        manifestPlaceholders["OPPO_APP_SECRET"] = umengProperty("oppo.appsecret")
        manifestPlaceholders["VIVO_APP_ID"] = umengProperty("vivo.appid")
        manifestPlaceholders["VIVO_APP_KEY"] = umengProperty("vivo.appkey")
        manifestPlaceholders["MEIZU_APP_ID"] = umengProperty("meizu.appid")
        manifestPlaceholders["MEIZU_APP_KEY"] = umengProperty("meizu.appkey")
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ✅ core library desugaring 依赖
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
