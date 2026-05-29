package com.example.easyconnect

import android.content.ContentProviderOperation
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.WindowManager
import android.provider.ContactsContract
import android.telephony.TelephonyManager
import android.telecom.TelecomManager
import android.telecom.Call
import android.telecom.VideoProfile
import android.telecom.PhoneAccountHandle
import android.util.Log
import android.app.role.RoleManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.easyconnect/calling"
    private var methodChannel: MethodChannel? = null
    private val REQUEST_ROLE_DIALER = 101
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility =
                android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            window.statusBarColor = android.graphics.Color.TRANSPARENT
            window.navigationBarColor = android.graphics.Color.TRANSPARENT
        }

        // Apply UNCONDITIONAL lock-screen bypass flags at startup
        // These must be set permanently so the Activity can render over the lock screen
        // the instant an incoming call arrives — never set conditionally.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }

        // Pre-verify overlay draw permission at startup (log only, guided UI handled by Flutter)
        val canDrawOverlays = Settings.canDrawOverlays(this)
        Log.d("MainActivity", "Overlay draw permission at startup: $canDrawOverlays")

        // Launch the KeepAlive foreground service to keep Dart VM warm
        EasyConnectKeepAliveService.start(this)

        // Pre-warm AudioManager to bypass initial system service binder latency
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            audioManager.mode // Querying is non-mutating but initializes system binder fully
            Log.d("MainActivity", "AudioManager pre-warmed successfully.")
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to pre-warm AudioManager: ${e.message}")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "makeDirectCall" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")
                    if (phoneNumber != null) {
                        makeDirectCall(phoneNumber)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Phone number is null", null)
                    }
                }
                "makeWhatsAppVideoCall" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")
                    if (phoneNumber != null) {
                        val success = makeWhatsAppVideoCall(phoneNumber)
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGUMENT", "Phone number is null", null)
                    }
                }
                "createSystemContact" -> {
                    val name = call.argument<String>("name")
                    val phoneNumber = call.argument<String>("phoneNumber")
                    if (name != null && phoneNumber != null) {
                        val success = createSystemContact(name, phoneNumber)
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGUMENT", "Name or phone number is null", null)
                    }
                }
                "shareAudioToWhatsApp" -> {
                    val filePath = call.argument<String>("filePath")
                    val phoneNumber = call.argument<String>("phoneNumber")
                    if (filePath != null && phoneNumber != null) {
                        val success = shareAudioToWhatsApp(filePath, phoneNumber)
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGUMENT", "File path or phone number is null", null)
                    }
                }
                "getBatteryLevel" -> {
                    val level = getBatteryLevel()
                    result.success(level)
                }
                "isDeviceCharging" -> {
                    val charging = isDeviceCharging()
                    result.success(charging)
                }
                "getSimState" -> {
                    val simState = getSimState()
                    result.success(simState)
                }
                "getSignalStrength" -> {
                    val signal = getSignalStatus()
                    result.success(signal)
                }
                "getDeviceContacts" -> {
                    val contacts = getDeviceContacts()
                    result.success(contacts)
                }
                "isDefaultDialer" -> {
                    result.success(isDefaultDialer())
                }
                "requestDefaultDialer" -> {
                    requestDefaultDialer()
                    result.success(true)
                }
                "acceptSystemCall" -> {
                    val success = acceptSystemCall()
                    result.success(success)
                }
                "hangUpSystemCall" -> {
                    val success = hangUpSystemCall()
                    result.success(success)
                }
                "setCallMute" -> {
                    val mute = call.argument<Boolean>("mute") ?: false
                    setCallMute(mute)
                    result.success(true)
                }
                "setCallSpeaker" -> {
                    val speaker = call.argument<Boolean>("speaker") ?: false
                    setCallSpeaker(speaker)
                    result.success(true)
                }
                "getActiveSystemCall" -> {
                    val systemCall = EasyConnectInCallService.activeCall
                    if (systemCall != null) {
                        val callerNumber = systemCall.details.handle?.schemeSpecificPart ?: "Unknown"
                        val isIncoming = systemCall.state == Call.STATE_RINGING
                        val state = systemCall.state
                        val isVideo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            VideoProfile.isVideo(systemCall.details.videoState)
                        } else {
                            false
                        }
                        result.success(mapOf(
                            "number" to callerNumber,
                            "isIncoming" to isIncoming,
                            "state" to state,
                            "isVideo" to isVideo
                        ))
                    } else {
                        result.success(null)
                    }
                }
                "holdCall" -> {
                    val systemCall = EasyConnectInCallService.activeCall
                    if (systemCall != null) {
                        systemCall.hold()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "unholdCall" -> {
                    val systemCall = EasyConnectInCallService.activeCall
                    if (systemCall != null) {
                        systemCall.unhold()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "playDtmfTone" -> {
                    val digit = call.argument<String>("digit")?.firstOrNull()
                    val systemCall = EasyConnectInCallService.activeCall
                    if (digit != null && systemCall != null) {
                        systemCall.playDtmfTone(digit)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "stopDtmfTone" -> {
                    val systemCall = EasyConnectInCallService.activeCall
                    if (systemCall != null) {
                        systemCall.stopDtmfTone()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "checkOverlayPermissions" -> {
                    val canDraw = Settings.canDrawOverlays(this)
                    result.success(canDraw)
                }
                "requestOverlayPermission" -> {
                    try {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error opening overlay settings: ${e.message}", e)
                        result.success(false)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Set up static callback listeners for EasyConnectInCallService
        // Use postAtFrontOfQueue to bypass any pending messages in the main Looper queue,
        // ensuring call events are dispatched to Flutter with minimum latency.
        EasyConnectInCallService.listener = object : EasyConnectInCallService.CallStateListener {
            override fun onCallAdded(call: Call) {
                val callerNumber = call.details.handle?.schemeSpecificPart ?: "Unknown"
                val isIncoming = call.state == Call.STATE_RINGING
                val state = call.state
                val isVideo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    VideoProfile.isVideo(call.details.videoState)
                } else {
                    false
                }
                mainHandler.postAtFrontOfQueue {
                    methodChannel?.invokeMethod("onSystemCallEvent", mapOf(
                        "event" to "added",
                        "number" to callerNumber,
                        "isIncoming" to isIncoming,
                        "state" to state,
                        "isVideo" to isVideo
                    ))
                }
            }

            override fun onCallRemoved(call: Call) {
                val causeCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    call.details?.disconnectCause?.code ?: -1
                } else {
                    -1
                }
                mainHandler.postAtFrontOfQueue {
                    methodChannel?.invokeMethod("onSystemCallEvent", mapOf(
                        "event" to "removed",
                        "disconnectCause" to causeCode
                    ))
                }
            }

            override fun onCallStateChanged(call: Call, state: Int) {
                val causeCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    call.details?.disconnectCause?.code ?: -1
                } else {
                    -1
                }
                mainHandler.postAtFrontOfQueue {
                    methodChannel?.invokeMethod("onSystemCallEvent", mapOf(
                        "event" to "stateChanged",
                        "state" to state,
                        "disconnectCause" to causeCode
                    ))
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        updateLockScreenFlags()
        if (intent.getBooleanExtra("system_call_added", false)) {
            val callerNumber = intent.getStringExtra("caller_number") ?: "Unknown"
            val isIncoming = intent.getBooleanExtra("is_incoming", false)
            val state = intent.getIntExtra("call_state", if (isIncoming) Call.STATE_RINGING else Call.STATE_DIALING)
            val isVideo = intent.getBooleanExtra("is_video", false)
            methodChannel?.invokeMethod("onSystemCallEvent", mapOf(
                "event" to "added",
                "number" to callerNumber,
                "isIncoming" to isIncoming,
                "state" to state,
                "isVideo" to isVideo
            ))
        }
    }

    override fun onResume() {
        super.onResume()
        updateLockScreenFlags()
    }

    private fun updateLockScreenFlags() {
        // Lock screen flags are now unconditionally set in onCreate().
        // This method is kept for backward compatibility but is a no-op.
        Log.d("MainActivity", "updateLockScreenFlags: no-op (unconditional flags set in onCreate)")
    }

    private fun isDefaultDialer(): Boolean {
        Log.d("MainActivity", "isDefaultDialer() called. SDK_INT: ${Build.VERSION.SDK_INT}")
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val roleManager = getSystemService(Context.ROLE_SERVICE) as RoleManager
                val isAvailable = roleManager.isRoleAvailable(RoleManager.ROLE_DIALER)
                val isHeld = roleManager.isRoleHeld(RoleManager.ROLE_DIALER)
                Log.d("MainActivity", "Q+ Dialer Role: available=$isAvailable, held=$isHeld")
                isHeld
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                val defaultDialer = telecomManager.defaultDialerPackage
                Log.d("MainActivity", "M+ Default Dialer package: $defaultDialer (our package: $packageName)")
                defaultDialer == packageName
            } else {
                Log.d("MainActivity", "Pre-M device: cannot be default dialer")
                false
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error in isDefaultDialer: ${e.message}", e)
            false
        }
    }

    private fun requestDefaultDialer() {
        Log.d("MainActivity", "requestDefaultDialer() called")
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val roleManager = getSystemService(Context.ROLE_SERVICE) as RoleManager
                val isAvailable = roleManager.isRoleAvailable(RoleManager.ROLE_DIALER)
                val isHeld = roleManager.isRoleHeld(RoleManager.ROLE_DIALER)
                Log.d("MainActivity", "requestDefaultDialer Q+: available=$isAvailable, held=$isHeld")
                if (isAvailable) {
                    if (!isHeld) {
                        Log.d("MainActivity", "Creating request role intent for ROLE_DIALER via startActivityForResult")
                        val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_DIALER)
                        startActivityForResult(intent, REQUEST_ROLE_DIALER)
                        Log.d("MainActivity", "startActivityForResult(intent) invoked successfully")
                    } else {
                        Log.d("MainActivity", "Dialer role is already held")
                    }
                } else {
                    Log.e("MainActivity", "Dialer role is NOT available on this device!")
                }
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Log.d("MainActivity", "requestDefaultDialer M+: launching ACTION_CHANGE_DEFAULT_DIALER via startActivityForResult")
                val intent = Intent(TelecomManager.ACTION_CHANGE_DEFAULT_DIALER).apply {
                    putExtra(TelecomManager.EXTRA_CHANGE_DEFAULT_DIALER_PACKAGE_NAME, packageName)
                }
                startActivityForResult(intent, REQUEST_ROLE_DIALER)
                Log.d("MainActivity", "ACTION_CHANGE_DEFAULT_DIALER intent started with startActivityForResult")
            } else {
                Log.w("MainActivity", "requestDefaultDialer ignored: SDK under Marshmallow")
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Exception in requestDefaultDialer: ${e.message}", e)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_ROLE_DIALER) {
            val isHeld = isDefaultDialer()
            Log.d("MainActivity", "Role request finished: resultCode=$resultCode, isHeld=$isHeld")
            runOnUiThread {
                methodChannel?.invokeMethod("onDefaultDialerChanged", isHeld)
            }
        }
    }

    private fun acceptSystemCall(): Boolean {
        val call = EasyConnectInCallService.activeCall ?: return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                call.answer(VideoProfile.STATE_AUDIO_ONLY)
                true
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error answering active call: ${e.message}", e)
            false
        }
    }

    private fun hangUpSystemCall(): Boolean {
        val call = EasyConnectInCallService.activeCall ?: return false
        return try {
            call.disconnect()
            true
        } catch (e: Exception) {
            Log.e("MainActivity", "Error disconnecting active call: ${e.message}", e)
            false
        }
    }

    private fun setCallMute(mute: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val service = EasyConnectInCallService.instance
            if (service != null) {
                Log.d("MainActivity", "Setting call mute: $mute")
                service.setMuted(mute)
            } else {
                Log.w("MainActivity", "InCallService instance is null. Cannot set mute.")
            }
        }
    }

    private fun setCallSpeaker(speaker: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val service = EasyConnectInCallService.instance
            if (service != null) {
                Log.d("MainActivity", "Setting call speaker: $speaker")
                val route = if (speaker) {
                    android.telecom.CallAudioState.ROUTE_SPEAKER
                } else {
                    android.telecom.CallAudioState.ROUTE_EARPIECE
                }
                service.setAudioRoute(route)
            } else {
                Log.w("MainActivity", "InCallService instance is null. Cannot set speaker.")
            }
        }
    }

    private fun makeDirectCall(phoneNumber: String) {
        try {
            Log.d("MainActivity", "makeDirectCall called with: $phoneNumber")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (checkSelfPermission(android.Manifest.permission.CALL_PHONE) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    placeCallIntent(phoneNumber)
                } else {
                    Log.w("MainActivity", "CALL_PHONE not granted natively. Requesting and falling back to ACTION_DIAL...")
                    requestPermissions(arrayOf(android.Manifest.permission.CALL_PHONE), 102)
                    placeDialIntent(phoneNumber)
                }
            } else {
                placeCallIntent(phoneNumber)
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Exception in makeDirectCall: ${e.message}", e)
        }
    }

    private fun placeCallIntent(phoneNumber: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                val uri = Uri.fromParts("tel", phoneNumber, null)
                val extras = Bundle()
                
                var phoneAccountHandle: PhoneAccountHandle? = null
                if (checkSelfPermission(android.Manifest.permission.READ_PHONE_STATE) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    phoneAccountHandle = telecomManager.getDefaultOutgoingPhoneAccount("tel")
                    if (phoneAccountHandle == null) {
                        val accounts = telecomManager.callCapablePhoneAccounts
                        if (accounts != null && accounts.isNotEmpty()) {
                            phoneAccountHandle = accounts[0]
                        }
                    }
                }
                
                if (phoneAccountHandle != null) {
                    extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, phoneAccountHandle)
                    Log.d("MainActivity", "Pre-selected PhoneAccountHandle: $phoneAccountHandle")
                } else {
                    Log.w("MainActivity", "No PhoneAccountHandle found; proceeding without pre-selection")
                }
                
                extras.putInt(TelecomManager.EXTRA_START_CALL_WITH_VIDEO_STATE, VideoProfile.STATE_AUDIO_ONLY)
                
                Log.d("MainActivity", "Placing call directly via TelecomManager.placeCall")
                telecomManager.placeCall(uri, extras)
                return
            } catch (e: SecurityException) {
                Log.e("MainActivity", "SecurityException in TelecomManager.placeCall: ${e.message}. Falling back to Intent.ACTION_CALL...", e)
            } catch (e: Exception) {
                Log.e("MainActivity", "Exception in TelecomManager.placeCall: ${e.message}. Falling back to Intent.ACTION_CALL...", e)
            }
        }
        
        // Fallback
        val uri = Uri.fromParts("tel", phoneNumber, null)
        val intent = Intent(Intent.ACTION_CALL).apply {
            data = uri
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(intent)
        Log.d("MainActivity", "Call placed via fallback Intent.ACTION_CALL")
    }

    private fun placeDialIntent(phoneNumber: String) {
        val uri = Uri.fromParts("tel", phoneNumber, null)
        val intent = Intent(Intent.ACTION_DIAL).apply {
            data = uri
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(intent)
        Log.d("MainActivity", "Call placed via ACTION_DIAL fallback")
    }

    private fun makeWhatsAppVideoCall(phoneNumber: String): Boolean {
        // Strip leading zeros and all non-digits for robust suffix matching
        val cleanAppNumber = phoneNumber.replace(Regex("^0+"), "").replace(Regex("\\D"), "")
        if (cleanAppNumber.isEmpty()) return false

        val resolver = contentResolver
        val uri = ContactsContract.Data.CONTENT_URI
        val projection = arrayOf(
            ContactsContract.Data._ID,
            ContactsContract.Data.MIMETYPE,
            ContactsContract.Data.DATA1
        )
        
        // Query all WhatsApp video call records to match dynamically
        val selection = "${ContactsContract.Data.MIMETYPE} = ?"
        val selectionArgs = arrayOf("vnd.android.cursor.item/vnd.com.whatsapp.video.call")
        
        var dataId: Long? = null
        var cursor: Cursor? = null
        try {
            cursor = resolver.query(uri, projection, selection, selectionArgs, null)
            if (cursor != null) {
                while (cursor.moveToNext()) {
                    val idColumn = cursor.getColumnIndex(ContactsContract.Data._ID)
                    val data1Column = cursor.getColumnIndex(ContactsContract.Data.DATA1)
                    if (idColumn != -1 && data1Column != -1) {
                        val id = cursor.getLong(idColumn)
                        val data1 = cursor.getString(data1Column) ?: ""
                        val cleanData1 = data1.replace(Regex("^0+"), "").replace(Regex("\\D"), "")
                        
                        // Debug log to ADB logcat so we can trace real-time execution
                        android.util.Log.d("EasyConnectContacts", "Checking WhatsApp row: ID=$id, DATA1='$data1', cleanDATA1='$cleanData1' vs cleanApp='$cleanAppNumber'")
                        
                        if (cleanData1.isNotEmpty() && (cleanData1.endsWith(cleanAppNumber) || cleanAppNumber.endsWith(cleanData1))) {
                            dataId = id
                            android.util.Log.d("EasyConnectContacts", "Match found! Selecting ID=$dataId")
                            break
                        }
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
            android.util.Log.e("EasyConnectContacts", "Error querying contacts: ${e.message}")
        } finally {
            cursor?.close()
        }

        return if (dataId != null) {
            try {
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(Uri.parse("content://com.android.contacts/data/$dataId"), "vnd.android.cursor.item/vnd.com.whatsapp.video.call")
                    setPackage("com.whatsapp")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(intent)
                android.util.Log.d("EasyConnectContacts", "Successfully launched WhatsApp direct video call Intent!")
                true
            } catch (e: Exception) {
                android.util.Log.e("EasyConnectContacts", "Failed to launch intent: ${e.message}")
                false
            }
        } else {
            android.util.Log.d("EasyConnectContacts", "No matching WhatsApp contact record found in ContactsProvider.")
            false
        }
    }

    private fun createSystemContact(name: String, phoneNumber: String): Boolean {
        return try {
            val resolver = contentResolver
            val ops = ArrayList<ContentProviderOperation>()

            ops.add(ContentProviderOperation.newInsert(ContactsContract.RawContacts.CONTENT_URI)
                .withValue(ContactsContract.RawContacts.ACCOUNT_TYPE, null)
                .withValue(ContactsContract.RawContacts.ACCOUNT_NAME, null)
                .build())

            // Structured Display Name
            ops.add(ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE)
                .withValue(ContactsContract.CommonDataKinds.StructuredName.DISPLAY_NAME, name)
                .build())

            // Phone Number
            ops.add(ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE)
                .withValue(ContactsContract.CommonDataKinds.Phone.NUMBER, phoneNumber)
                .withValue(ContactsContract.CommonDataKinds.Phone.TYPE, ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE)
                .build())

            resolver.applyBatch(ContactsContract.AUTHORITY, ops)
            android.util.Log.d("EasyConnectContacts", "Successfully programmatically added system contact: $name ($phoneNumber)")
            true
        } catch (e: Exception) {
            e.printStackTrace()
            android.util.Log.e("EasyConnectContacts", "Error creating system contact: ${e.message}")
            false
        }
    }

    private fun shareAudioToWhatsApp(filePath: String, phoneNumber: String): Boolean {
        return try {
            val file = File(filePath)
            if (!file.exists()) return false

            val context = applicationContext
            val authority = "${context.packageName}.fileprovider"
            val uri = FileProvider.getUriForFile(context, authority, file)

            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "audio/*"
                putExtra(Intent.EXTRA_STREAM, uri)
                // Use JID extra format phone_number@s.whatsapp.net to pre-select and target recipient
                val cleanNumber = phoneNumber.replace(Regex("\\D"), "")
                putExtra("jid", "$cleanNumber@s.whatsapp.net")
                setPackage("com.whatsapp")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(shareIntent)
            android.util.Log.d("EasyConnectContacts", "Successfully launched WhatsApp direct voice message Intent!")
            true
        } catch (e: Exception) {
            e.printStackTrace()
            android.util.Log.e("EasyConnectContacts", "Error launching WhatsApp direct share Intent: ${e.message}")
            false
        }
    }

    private fun getBatteryLevel(): Int {
        return try {
            val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        } catch (e: Exception) {
            80 // Safe fallback
        }
    }

    private fun isDeviceCharging(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                batteryManager.isCharging
            } else {
                val intent = registerReceiver(null, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                val plugged = intent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1) ?: -1
                plugged == BatteryManager.BATTERY_PLUGGED_AC ||
                        plugged == BatteryManager.BATTERY_PLUGGED_USB ||
                        plugged == BatteryManager.BATTERY_PLUGGED_WIRELESS
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun getSignalStatus(): String {
        try {
            val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val activeNetwork = connectivityManager.activeNetwork ?: return "disconnected"
            val capabilities = connectivityManager.getNetworkCapabilities(activeNetwork) ?: return "disconnected"

            // Check if internet is available
            val hasInternet = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                    capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
            if (!hasInternet) return "disconnected"

            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as android.net.wifi.WifiManager
                val wifiInfo = wifiManager.connectionInfo
                val rssi = wifiInfo.rssi
                val level = android.net.wifi.WifiManager.calculateSignalLevel(rssi, 5)
                return if (level <= 1) "weak" else "good"
            } else if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val level = capabilities.signalStrength
                    if (level in 0..4) {
                        return if (level <= 1) "weak" else "good"
                    }
                }
                
                val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
                val networkType = telephonyManager.networkType
                return when (networkType) {
                    TelephonyManager.NETWORK_TYPE_GPRS,
                    TelephonyManager.NETWORK_TYPE_EDGE,
                    TelephonyManager.NETWORK_TYPE_CDMA,
                    TelephonyManager.NETWORK_TYPE_1xRTT,
                    TelephonyManager.NETWORK_TYPE_IDEN -> "weak"
                    else -> "good"
                }
            }
            return "good"
        } catch (e: Exception) {
            return "good"
        }
    }

    private fun getDeviceContacts(): List<Map<String, String>> {
        val contactsList = ArrayList<Map<String, String>>()
        val resolver = contentResolver
        val uri = ContactsContract.CommonDataKinds.Phone.CONTENT_URI
        val projection = arrayOf(
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
            ContactsContract.CommonDataKinds.Phone.NUMBER
        )
        
        var cursor: Cursor? = null
        try {
            cursor = resolver.query(uri, projection, null, null, "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC")
            if (cursor != null) {
                val nameCol = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                val numCol = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                
                val seenNumbers = HashSet<String>()
                
                while (cursor.moveToNext()) {
                    if (nameCol != -1 && numCol != -1) {
                        val name = cursor.getString(nameCol) ?: ""
                        val number = cursor.getString(numCol) ?: ""
                        
                        // Deduplicate using cleaned digits only
                        val cleanNum = number.replace(Regex("\\D"), "")
                        if (cleanNum.isNotEmpty() && !seenNumbers.contains(cleanNum)) {
                            seenNumbers.add(cleanNum)
                            
                            val contactMap = HashMap<String, String>()
                            contactMap["name"] = name
                            contactMap["phoneNumber"] = number
                            contactsList.add(contactMap)
                        }
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        } finally {
            cursor?.close()
        }
        return contactsList
    }

    private fun getSimState(): String {
        return try {
            val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            when (telephonyManager.simState) {
                TelephonyManager.SIM_STATE_READY -> "ready"
                TelephonyManager.SIM_STATE_ABSENT -> "absent"
                TelephonyManager.SIM_STATE_PIN_REQUIRED,
                TelephonyManager.SIM_STATE_PUK_REQUIRED,
                TelephonyManager.SIM_STATE_NETWORK_LOCKED -> "locked"
                TelephonyManager.SIM_STATE_CARD_IO_ERROR,
                TelephonyManager.SIM_STATE_CARD_RESTRICTED,
                7 -> "error" // 7 is TelephonyManager.SIM_STATE_PERMANENT_DISABLED (hidden in public SDK)
                else -> "unknown"
            }
        } catch (e: Exception) {
            "unknown"
        }
    }
}
