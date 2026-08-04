package com.example.personal_expanse_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject

/**
 * Handles the Add / Ignore buttons on a detection notification. This runs with
 * the app dead, so it can't parse the SMS or touch Hive — it only records the
 * decision next to the queued message. The app applies it on the next drain:
 * `add` skips the review card and books the expense, `ignore` retires the SMS
 * without ever calling the model.
 */
class SmsActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val hash = intent.getStringExtra(EXTRA_HASH) ?: return
        val decision = intent.getStringExtra(EXTRA_DECISION) ?: return
        if (decision != "add" && decision != "ignore") return

        val prefs = context.getSharedPreferences(SmsReceiver.PREFS, Context.MODE_PRIVATE)
        val decisions = JSONObject(prefs.getString(SmsReceiver.KEY_DECISIONS, "{}"))
        decisions.put(hash, decision)
        prefs.edit().putString(SmsReceiver.KEY_DECISIONS, decisions.toString()).apply()

        NotificationManagerCompat.from(context).cancel(hash.hashCode())
    }

    companion object {
        const val EXTRA_HASH = "hash"
        const val EXTRA_DECISION = "decision"
    }
}
