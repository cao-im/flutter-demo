package com.clb.caoim

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * IM保活管理器（Flutter MethodChannel 端）
 * 负责启动/停止 Android 前台服务 + 动态申请通知权限
 */
class IMKeepAliveHandler(
    private val activity: Activity
) : MethodChannel.MethodCallHandler {

    companion object {
        const val REQUEST_CODE_NOTIFICATION_PERMISSION = 1001
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestNotificationPermission" -> {
                requestNotificationPermission(result)
            }
            "checkNotificationPermission" -> {
                val granted = isNotificationPermissionGranted()
                result.success(granted)
            }
            "startKeepAlive" -> {
                startKeepAlive(result)
            }
            "stopKeepAlive" -> {
                stopKeepAlive(result)
            }
            else -> result.notImplemented()
        }
    }

    /// 检查通知权限是否已授予
    private fun isNotificationPermissionGranted(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Android 13+ 需要检查 POST_NOTIFICATIONS 权限
            ContextCompat.checkSelfPermission(
                activity,
                android.Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            // Android 12 及以下，通知权限在安装时默认授予
            true
        }
    }

    /// 动态请求通知权限（Android 13+）
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (isNotificationPermissionGranted()) {
            result.success(true)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_CODE_NOTIFICATION_PERMISSION
            )
            // 权限请求结果是异步的，先返回 pending 状态
            result.success("pending")
        } else {
            result.success(true)
        }
    }

    /// 启动保活服务（自动处理通知权限）
    private fun startKeepAlive(result: MethodChannel.Result) {
        try {
            // 先创建通知渠道
            IMKeepAliveService.createNotificationChannel(activity)

            // Android 13+ 如果没有通知权限，仍然启动前台服务
            // （前台服务本身可以运行，只是通知可能不显示）
            val intent = Intent(activity, IMKeepAliveService::class.java).apply {
                action = IMKeepAliveService.ACTION_START
                // 传递是否有通知权限的信息给 Service
                putExtra("has_notification_permission", isNotificationPermissionGranted())
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activity.startForegroundService(intent)
            } else {
                activity.startService(intent)
            }

            result.success(isNotificationPermissionGranted())
        } catch (e: Exception) {
            result.error("KEEP_ALIVE_ERROR", "启动保活服务失败: ${e.message}", null)
        }
    }

    /// 停止保活服务
    private fun stopKeepAlive(result: MethodChannel.Result) {
        try {
            val intent = Intent(activity, IMKeepAliveService::class.java).apply {
                action = IMKeepAliveService.ACTION_STOP
            }
            activity.stopService(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("KEEP_ALIVE_ERROR", "停止保活服务失败: ${e.message}", null)
        }
    }
}
