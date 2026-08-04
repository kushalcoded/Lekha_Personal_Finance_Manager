package com.example.personal_expanse_tracker

import android.Manifest
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    /** Held while the POST_NOTIFICATIONS dialog is up, so Dart learns the answer. */
    private var notifyResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> result.success(hasSmsPermission())
                    "requestPermission" -> {
                        requestSmsPermission()
                        result.success(hasSmsPermission())
                    }
                    "readQueue" -> result.success(readQueue())
                    "setNotify" -> setNotify(call.arguments as? Boolean ?: false, result)
                    "readDecisions" -> result.success(
                        prefs().getString(SmsReceiver.KEY_DECISIONS, "{}")
                    )
                    "clearDecisions" -> {
                        clearDecisions(call.arguments as? List<*> ?: emptyList<Any>())
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun prefs(): SharedPreferences =
        getSharedPreferences(SmsReceiver.PREFS, Context.MODE_PRIVATE)

    private fun hasSmsPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return checkSelfPermission(Manifest.permission.RECEIVE_SMS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestSmsPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !hasSmsPermission()) {
            requestPermissions(arrayOf(Manifest.permission.RECEIVE_SMS), 4242)
        }
    }

    private fun hasNotifyPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    /**
     * The receiver runs with the app dead and can't read Hive, so the Settings
     * toggle is mirrored here. Returns whether notifications can actually be
     * posted — Dart uses that to warn instead of silently doing nothing.
     */
    private fun setNotify(on: Boolean, result: MethodChannel.Result) {
        prefs().edit().putBoolean(SmsReceiver.KEY_NOTIFY, on).apply()
        if (!on || hasNotifyPermission()) {
            result.success(hasNotifyPermission())
            return
        }
        // A rapid re-toggle would otherwise leave the first call hanging forever.
        notifyResult?.success(false)
        notifyResult = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFY_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFY_REQUEST) return
        notifyResult?.success(
            grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        )
        notifyResult = null
    }

    /**
     * Return the queued candidate SMS (JSON array string). Read-only on purpose:
     * entries persist so an offline parse failure can be retried on the next
     * open — Dart skips ones it has already processed. The receiver caps and
     * dedups the queue, so it can't grow without bound.
     */
    private fun readQueue(): String {
        return prefs().getString(SmsReceiver.KEY_QUEUE, "[]") ?: "[]"
    }

    /**
     * Drop the notification decisions Dart has finished acting on. Cleared by
     * hash rather than wholesale, so a decision whose parse failed offline is
     * still waiting on the next drain.
     */
    private fun clearDecisions(hashes: List<*>) {
        val decisions = JSONObject(prefs().getString(SmsReceiver.KEY_DECISIONS, "{}"))
        for (hash in hashes) decisions.remove(hash?.toString() ?: continue)
        prefs().edit().putString(SmsReceiver.KEY_DECISIONS, decisions.toString()).apply()
    }

    companion object {
        private const val CHANNEL = "lekha/sms"
        private const val NOTIFY_REQUEST = 4243
    }
}
