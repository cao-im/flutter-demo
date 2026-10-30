package com.clb.caoim

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val KEEP_ALIVE_CHANNEL = "com.clb.caoim/keep_alive"
    private val APP_CHANNEL = "com.clb.caoim/app"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 注册IM保活服务MethodChannel（传入Activity用于权限请求）
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            KEEP_ALIVE_CHANNEL
        ).setMethodCallHandler(IMKeepAliveHandler(this))

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_CHANNEL
        ).setMethodCallHandler { call, result ->
            if (call.method == "moveToBackground") {
                moveTaskToBack(true)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }
}
