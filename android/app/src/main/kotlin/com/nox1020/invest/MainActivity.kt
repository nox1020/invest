package com.nox1020.invest

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        @Volatile var channel: MethodChannel? = null
        @Volatile var resumed = false
        val pendingSms = mutableListOf<Map<String, Any>>()
        private const val REQ_SMS = 7101
    }

    private var permReply: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "invest/sms")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(status())
                "request" -> requestSms(result)
                "openAppSettings" -> {
                    openSettings(Settings.ACTION_APPLICATION_DETAILS_SETTINGS); result.success(null)
                }
                "openFullScreenSettings" -> {
                    if (Build.VERSION.SDK_INT >= 34) {
                        openSettings(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                    } else {
                        openSettings(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    }
                    result.success(null)
                }
                "inbox" -> {
                    val since = (call.argument<Number>("since") ?: 0).toLong()
                    try {
                        result.success(SmsReceiver.readInbox(this, since))
                    } catch (e: Exception) {
                        result.success(emptyList<Map<String, Any>>())
                    }
                }
                "takePending" -> synchronized(pendingSms) {
                    val copy = ArrayList(pendingSms); pendingSms.clear(); result.success(copy)
                }
                "takeRejected" -> result.success(SmsReceiver.takeRejected(this))
                "cancel" -> {
                    val fp = call.argument<String>("fp")
                    if (fp != null) SmsReceiver.cancel(this, fp)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        absorb(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        absorb(intent)
    }

    override fun onResume() { super.onResume(); resumed = true }
    override fun onPause() { resumed = false; super.onPause() }

    /** A tapped bank-SMS notification: hand the SMS (on-device only) to Dart. */
    private fun absorb(i: Intent?) {
        val body = i?.getStringExtra(SmsReceiver.EXTRA_BODY) ?: return
        val sms = mapOf<String, Any>(
            "address" to (i.getStringExtra(SmsReceiver.EXTRA_ADDR) ?: ""),
            "body" to body,
            "date" to i.getLongExtra(SmsReceiver.EXTRA_DATE, System.currentTimeMillis()),
        )
        i.removeExtra(SmsReceiver.EXTRA_BODY)
        val ch = channel
        if (ch != null && resumed) {
            ch.invokeMethod("smsArrived", sms)
        } else {
            synchronized(pendingSms) { pendingSms.add(sms) }
        }
    }

    private fun granted(p: String) =
        ContextCompat.checkSelfPermission(this, p) == PackageManager.PERMISSION_GRANTED

    private fun status(): Map<String, Any> {
        val nm = getSystemService(NotificationManager::class.java)
        val fullScreen = if (Build.VERSION.SDK_INT >= 34) nm.canUseFullScreenIntent() else true
        val notify = if (Build.VERSION.SDK_INT >= 33) granted(Manifest.permission.POST_NOTIFICATIONS) else nm.areNotificationsEnabled()
        return mapOf(
            "read" to granted(Manifest.permission.READ_SMS),
            "receive" to granted(Manifest.permission.RECEIVE_SMS),
            "notify" to notify,
            "fullScreen" to fullScreen,
            "sdk" to Build.VERSION.SDK_INT,
        )
    }

    private fun requestSms(result: MethodChannel.Result) {
        val perms = mutableListOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS)
        if (Build.VERSION.SDK_INT >= 33) perms.add(Manifest.permission.POST_NOTIFICATIONS)
        val missing = perms.filter { !granted(it) }
        if (missing.isEmpty()) { result.success(true); return }
        permReply?.success(false)
        permReply = result
        ActivityCompat.requestPermissions(this, missing.toTypedArray(), REQ_SMS)
    }

    override fun onRequestPermissionsResult(code: Int, perms: Array<out String>, res: IntArray) {
        super.onRequestPermissionsResult(code, perms, res)
        if (code == REQ_SMS) {
            permReply?.success(granted(Manifest.permission.READ_SMS) && granted(Manifest.permission.RECEIVE_SMS))
            permReply = null
        }
    }

    private fun openSettings(action: String) {
        try {
            startActivity(Intent(action, Uri.fromParts("package", packageName, null)))
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)))
        }
    }
}
