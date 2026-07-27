package com.example.personal_expanse_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import org.json.JSONArray
import org.json.JSONObject

/**
 * Captures incoming bank/UPI SMS in real time (fires even when the app is
 * closed). Does the cheapest possible gate — a debit-ish keyword plus a digit —
 * then appends the raw message to a SharedPreferences queue. All real parsing
 * (Gemini) and filtering happens in Dart when the app next opens and drains
 * this queue via the [SmsChannel] MethodChannel.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (messages.isEmpty()) return

        val address = messages[0].originatingAddress ?: ""
        val timestamp = messages[0].timestampMillis
        // Long SMS arrive split into parts; stitch the bodies back together.
        val body = messages.joinToString("") { it.messageBody ?: "" }
        if (!looksFinancial(body)) return

        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val queue = JSONArray(prefs.getString(KEY_QUEUE, "[]"))
        val hash = (body + timestamp).hashCode().toString()

        for (i in 0 until queue.length()) {
            if (queue.getJSONObject(i).optString("hash") == hash) return // already queued
        }

        queue.put(
            JSONObject().apply {
                put("hash", hash)
                put("address", address)
                put("timestamp", timestamp)
                put("body", body)
            }
        )

        // Keep the queue bounded in case the app isn't opened for a long time.
        val capped = if (queue.length() > MAX_QUEUE) {
            JSONArray().also { c ->
                for (i in queue.length() - MAX_QUEUE until queue.length()) c.put(queue.get(i))
            }
        } else {
            queue
        }

        prefs.edit().putString(KEY_QUEUE, capped.toString()).apply()
    }

    private fun looksFinancial(body: String): Boolean {
        val lower = body.lowercase()
        return KEYWORDS.any { lower.contains(it) } && body.any { it.isDigit() }
    }

    companion object {
        const val PREFS = "lekha_sms"
        const val KEY_QUEUE = "queue"
        private const val MAX_QUEUE = 100
        private val KEYWORDS = listOf(
            "debited", "debit", "spent", "paid", "withdrawn",
            "sent", "purchase", "txn", "transaction", "deducted"
        )
    }
}
