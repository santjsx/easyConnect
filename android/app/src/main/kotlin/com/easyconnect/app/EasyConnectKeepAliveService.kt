package com.easyconnect.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * Lightweight, sticky, silent foreground service that keeps the Flutter Dart VM isolate warm.
 * 
 * Purpose: Prevents Android from freezing/garbage-collecting the Dart isolate when the app
 * is in the background. This eliminates 300-800ms of cold-wake latency when an incoming
 * call arrives, ensuring the incoming call screen appears within ≤1 second.
 * 
 * The notification channel uses IMPORTANCE_MIN so the notification is silent and minimally
 * visible in the notification tray.
 */
class EasyConnectKeepAliveService : Service() {

    companion object {
        private const val TAG = "KeepAliveService"
        private const val CHANNEL_ID = "easyconnect_keep_alive"
        private const val NOTIFICATION_ID = 99999

        fun start(context: Context) {
            val intent = Intent(context, EasyConnectKeepAliveService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                Log.d(TAG, "KeepAlive service start requested.")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start KeepAlive service: ${e.message}", e)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, EasyConnectKeepAliveService::class.java)
            context.stopService(intent)
            Log.d(TAG, "KeepAlive service stop requested.")
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "KeepAlive service created.")
        createNotificationChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                buildNotification(),
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
            )
        } else {
            startForeground(NOTIFICATION_ID, buildNotification())
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "KeepAlive service onStartCommand.")
        // START_STICKY: Android will restart this service if it's killed
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.d(TAG, "KeepAlive service destroyed.")
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "EasyConnect Background",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Keeps EasyConnect ready for instant incoming calls"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
                setSound(null, null)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("EasyConnect")
            .setContentText("Ready for calls")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setOngoing(true)
            .setPriority(Notification.PRIORITY_MIN)
            .build()
    }
}
