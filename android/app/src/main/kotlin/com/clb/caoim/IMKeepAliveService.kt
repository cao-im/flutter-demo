package com.clb.caoim

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * IM前台保活服务
 * 通过常驻通知栏通知，防止APP在后台被系统杀死
 */
class IMKeepAliveService : Service() {

    companion object {
        const val CHANNEL_ID = "im_keep_alive_channel"
        const val CHANNEL_NAME = "IM消息服务"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "com.clb.caoim.START_KEEP_ALIVE"
        const val ACTION_STOP = "com.clb.caoim.STOP_KEEP_ALIVE"

        /**
         * 创建通知渠道（Android 8.0+ 必须）
         */
        fun createNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "保持IM连接在线，接收新消息"
                    setShowBadge(false)
                    setSound(null, null)
                    enableVibration(false)
                }

                val manager = context.getSystemService(NotificationManager::class.java)
                manager.createNotificationChannel(channel)
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val notification = createNotification()
                startForeground(NOTIFICATION_ID, notification)
            }
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_STICKY // 服务被杀死后自动重启
    }

    private fun createNotification(): Notification {
        // 点击通知后打开应用
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("曹操IM")
            .setContentText("正在后台运行，保持连接在线")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true) // 不可滑动删除
            .setContentIntent(pendingIntent)
            .build()
    }
}
