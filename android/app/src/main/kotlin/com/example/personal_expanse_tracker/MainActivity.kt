package com.example.personal_expanse_tracker

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
                    else -> result.notImplemented()
                }
            }
    }

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

    /**
     * Return the queued candidate SMS (JSON array string). Read-only on purpose:
     * entries persist so an offline parse failure can be retried on the next
     * open — Dart skips ones it has already processed. The receiver caps and
     * dedups the queue, so it can't grow without bound.
     */
    private fun readQueue(): String {
        val prefs = getSharedPreferences(SmsReceiver.PREFS, Context.MODE_PRIVATE)
        return prefs.getString(SmsReceiver.KEY_QUEUE, "[]") ?: "[]"
    }

    companion object {
        private const val CHANNEL = "lekha/sms"
    }
}
