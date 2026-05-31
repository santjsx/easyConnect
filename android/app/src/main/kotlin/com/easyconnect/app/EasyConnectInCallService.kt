package com.easyconnect.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.telecom.Call
import android.telecom.InCallService
import android.telecom.TelecomManager
import android.telecom.VideoProfile
import android.util.Log
import android.media.ToneGenerator
import android.media.AudioManager

class EasyConnectInCallService : InCallService() {
    private var proximityWakeLock: PowerManager.WakeLock? = null
    private var toneGenerator: ToneGenerator? = null

    companion object {
        var activeCall: Call? = null
        var listener: CallStateListener? = null
        var instance: EasyConnectInCallService? = null
        private const val TAG = "EasyConnectInCall"
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.d(TAG, "EasyConnectInCallService instance created.")
    }

    override fun onDestroy() {
        instance = null
        Log.d(TAG, "EasyConnectInCallService instance destroyed.")
        super.onDestroy()
    }

    private fun startRingbackTone() {
        // Disabled custom ToneGenerator to prevent AudioFlinger / Telephony audio routing contention.
        // The cellular network/carrier plays the ringback tone naturally over STREAM_VOICE_CALL,
        // so avoiding a concurrent application-level ToneGenerator prevents routing delays and enables
        // call signaling to establish instantly (saving up to 4 seconds of connection latency).
        Log.d(TAG, "Custom ringback tone skipped (avoiding audio routing contention for fast dialing).")
    }

    private fun stopRingbackTone() {
        // No-op (Custom ToneGenerator disabled)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent != null) {
            val action = intent.action
            Log.d(TAG, "onStartCommand action: $action")
            when (action) {
                "com.easyconnect.app.ACTION_DECLINE" -> {
                    Log.d(TAG, "Declining call via notification action.")
                    activeCall?.disconnect()
                    cancelIncomingCallNotification()
                }
            }
        }
        return super.onStartCommand(intent, flags, startId)
    }

    interface CallStateListener {
        fun onCallAdded(call: Call)
        fun onCallRemoved(call: Call)
        fun onCallStateChanged(call: Call, state: Int)
    }

    private val callCallback = object : Call.Callback() {
        override fun onStateChanged(call: Call, state: Int) {
            super.onStateChanged(call, state)
            Log.d(TAG, "Call state changed: $state")
            if (state != Call.STATE_RINGING) {
                cancelIncomingCallNotification()
            }
            if (state == Call.STATE_SELECT_PHONE_ACCOUNT) {
                handlePhoneAccountSelection(call)
            }
            if (state == Call.STATE_ACTIVE || state == Call.STATE_DISCONNECTED || state == Call.STATE_DISCONNECTING) {
                stopRingbackTone()
            }
            listener?.onCallStateChanged(call, state)
        }
    }

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        Log.d(TAG, "onCallAdded: $call")
        activeCall = call
        call.registerCallback(callCallback)

        // Elevate call setup & main thread priority to prevent stuttering/delay
        try {
            Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
            Log.d(TAG, "Thread priority elevated to THREAD_PRIORITY_AUDIO.")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set thread priority: ${e.message}")
        }

        // Initialize and acquire proximity wake lock
        acquireProximityWakeLock()

        val callerNumber = call.details.handle?.schemeSpecificPart ?: "Unknown"
        val isIncoming = call.state == Call.STATE_RINGING

        if (isIncoming) {
            // CRITICAL: Fire native Full-Screen Intent notification FIRST
            // This ensures the screen wakes up and draws before Flutter processes the event.
            showIncomingCallNotification(callerNumber)
            
            // THEN notify Flutter via MethodChannel
            listener?.onCallAdded(call)
        } else {
            // Outgoing call - notify Flutter first, then launch MainActivity
            listener?.onCallAdded(call)
            
            Log.d(TAG, "Launching MainActivity for outgoing call. Caller number: $callerNumber")
            startRingbackTone()
            val isVideo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                VideoProfile.isVideo(call.details.videoState)
            } else {
                false
            }
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("system_call_added", true)
                putExtra("caller_number", callerNumber)
                putExtra("is_incoming", false)
                putExtra("call_state", call.state)
                putExtra("is_video", isVideo)
            }
            startActivity(intent)
        }

        // If the call requires phone account selection, handle it immediately
        if (call.state == Call.STATE_SELECT_PHONE_ACCOUNT) {
            handlePhoneAccountSelection(call)
        }
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        Log.d(TAG, "onCallRemoved: $call")
        call.unregisterCallback(callCallback)
        listener?.onCallRemoved(call)
        if (activeCall == call) {
            activeCall = null
        }

        stopRingbackTone()

        // Clean up the notification
        cancelIncomingCallNotification()

        // Release proximity wake lock
        releaseProximityWakeLock()

        // Reset thread priority to default
        try {
            Process.setThreadPriority(Process.THREAD_PRIORITY_DEFAULT)
            Log.d(TAG, "Thread priority reset to default.")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to reset thread priority: ${e.message}")
        }
    }

    override fun onCallAudioStateChanged(audioState: android.telecom.CallAudioState) {
        super.onCallAudioStateChanged(audioState)
        Log.d(TAG, "onCallAudioStateChanged: route=${audioState.route}")
        
        // If speaker is active, release proximity lock. Otherwise, acquire it (earpiece/headset).
        if (audioState.route == android.telecom.CallAudioState.ROUTE_SPEAKER) {
            releaseProximityWakeLock()
        } else {
            acquireProximityWakeLock()
        }
    }

    private fun handlePhoneAccountSelection(call: Call) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                
                // 1. Try default outgoing phone account first
                val defaultAccount = telecomManager.getDefaultOutgoingPhoneAccount("tel")
                if (defaultAccount != null) {
                    Log.d(TAG, "Auto-selecting default outgoing phone account: $defaultAccount")
                    call.phoneAccountSelected(defaultAccount, false)
                    return
                }

                // 2. Fall back to the first call-capable account from the list
                @Suppress("MissingPermission")
                val phoneAccounts = telecomManager.callCapablePhoneAccounts
                if (phoneAccounts != null && phoneAccounts.isNotEmpty()) {
                    Log.d(TAG, "Auto-selecting first capable phone account: ${phoneAccounts[0]}")
                    call.phoneAccountSelected(phoneAccounts[0], false)
                    return
                }
                Log.w(TAG, "No capable phone accounts found to auto-select.")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to auto-select phone account: ${e.message}", e)
            }
        }
    }

    private fun showIncomingCallNotification(callerNumber: String) {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channelId = "incoming_calls"
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    channelId,
                    "Incoming Calls",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Notification for incoming calls"
                    enableLights(true)
                    enableVibration(true)
                    setSound(null, null) // Sound is handled by the app's accessibility readouts/TTS loop
                }
                notificationManager.createNotificationChannel(channel)
            }

            // Full-Screen Intent PendingIntent
            val isVideo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                VideoProfile.isVideo(activeCall?.details?.videoState ?: 0)
            } else {
                false
            }
            val mainIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("system_call_added", true)
                putExtra("caller_number", callerNumber)
                putExtra("is_incoming", true)
                putExtra("call_state", Call.STATE_RINGING)
                putExtra("is_video", isVideo)
            }
            val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val mainPendingIntent = PendingIntent.getActivity(this, 101, mainIntent, pendingFlags)

            // Action Intent: Accept (Directly open MainActivity to avoid Android 12+ notification trampoline restriction)
            val acceptIntent = Intent(this, MainActivity::class.java).apply {
                action = "com.easyconnect.app.ACTION_ACCEPT"
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("system_call_added", true)
                putExtra("caller_number", callerNumber)
                putExtra("is_incoming", true)
                putExtra("call_state", Call.STATE_ACTIVE)
                putExtra("is_video", isVideo)
            }
            val acceptPendingIntent = PendingIntent.getActivity(this, 201, acceptIntent, pendingFlags)

            val actionFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            // Action Intent: Decline
            val declineIntent = Intent(this, EasyConnectInCallService::class.java).apply {
                action = "com.easyconnect.app.ACTION_DECLINE"
            }
            val declinePendingIntent = PendingIntent.getService(this, 202, declineIntent, actionFlags)

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, channelId)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }

            // Build Actions
            val acceptAction = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
                Notification.Action.Builder(
                    android.R.drawable.ic_menu_call,
                    "Accept",
                    acceptPendingIntent
                ).build()
            } else {
                null
            }

            val declineAction = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
                Notification.Action.Builder(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "Decline",
                    declinePendingIntent
                ).build()
            } else {
                null
            }

            builder
                .setContentTitle("Incoming Call")
                .setContentText("Call from $callerNumber")
                .setSmallIcon(android.R.drawable.ic_menu_call)
                .setCategory(Notification.CATEGORY_CALL)
                .setPriority(Notification.PRIORITY_HIGH)
                .setFullScreenIntent(mainPendingIntent, true)
                .setAutoCancel(true)
                .setOngoing(true)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
                if (acceptAction != null) builder.addAction(acceptAction)
                if (declineAction != null) builder.addAction(declineAction)
            }

            notificationManager.notify(12345, builder.build())
            Log.d(TAG, "Incoming call notification posted.")
        } catch (e: Exception) {
            Log.e(TAG, "Error posting notification: ${e.message}", e)
        }
    }

    private fun cancelIncomingCallNotification() {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(12345)
            Log.d(TAG, "Incoming call notification cancelled.")
        } catch (e: Exception) {
            Log.e(TAG, "Error cancelling notification: ${e.message}")
        }
    }

    private fun acquireProximityWakeLock() {
        try {
            if (proximityWakeLock == null) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    if (powerManager.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) {
                        proximityWakeLock = powerManager.newWakeLock(
                            PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
                            "easyconnect:proximity_wakelock"
                        )
                        Log.d(TAG, "Proximity wake lock created.")
                    }
                }
            }
            if (proximityWakeLock != null && !proximityWakeLock!!.isHeld) {
                proximityWakeLock!!.acquire(1 * 60 * 60 * 1000L) // Safe limit to 1 hour max
                Log.d(TAG, "Proximity wake lock acquired.")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error acquiring proximity wake lock: ${e.message}", e)
        }
    }

    private fun releaseProximityWakeLock() {
        try {
            if (proximityWakeLock != null && proximityWakeLock!!.isHeld) {
                proximityWakeLock!!.release()
                Log.d(TAG, "Proximity wake lock released.")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing proximity wake lock: ${e.message}", e)
        }
    }
}
