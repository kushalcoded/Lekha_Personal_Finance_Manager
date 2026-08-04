package com.example.personal_expanse_tracker

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Telephony
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray
import org.json.JSONObject

/**
 * Captures incoming bank/UPI SMS in real time (fires even when the app is
 * closed). Does the cheapest possible gate — a debit-ish keyword plus a digit —
 * then appends the raw message to a SharedPreferences queue. All real parsing
 * (Gemini) and filtering happens in Dart when the app next opens and drains
 * this queue via the [SmsChannel] MethodChannel.
 *
 * When the user has switched detection notifications on, it also posts a
 * heads-up with Add / Ignore buttons. The amount shown there is a plain regex
 * read of the message, not the model's answer — good enough to decide by, and
 * the booked expense always uses the parsed amount.
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

        if (prefs.getBoolean(KEY_NOTIFY, false)) notify(context, hash, body)
    }

    private fun looksFinancial(body: String): Boolean {
        val lower = body.lowercase()
        return KEYWORDS.any { lower.contains(it) } && body.any { it.isDigit() }
    }

    private fun notify(context: Context, hash: String, body: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return // toggle is on but the grant was refused/revoked — stay quiet
        }

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as? NotificationManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Detected transactions",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = "Asks whether a bank SMS should become an expense"
                }
            )
        }

        val amount = amountOf(body)
        val open = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_lekha)
            .setContentTitle(if (amount != null) "Spent $amount?" else "Transaction detected")
            .setContentText("Add it to your expenses?")
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .addAction(0, "Add", decisionIntent(context, hash, "add"))
            .addAction(0, "Ignore", decisionIntent(context, hash, "ignore"))

        if (open != null) {
            builder.setContentIntent(
                PendingIntent.getActivity(
                    context,
                    hash.hashCode(),
                    open,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
        }

        manager.notify(hash.hashCode(), builder.build())
    }

    private fun decisionIntent(context: Context, hash: String, decision: String): PendingIntent {
        val intent = Intent(context, SmsActionReceiver::class.java)
            .putExtra(SmsActionReceiver.EXTRA_HASH, hash)
            .putExtra(SmsActionReceiver.EXTRA_DECISION, decision)
        return PendingIntent.getBroadcast(
            context,
            // Both buttons target the same receiver, so the request code has to
            // differ or the second PendingIntent reuses the first one's extras.
            (hash + decision).hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** Display only. Skips a trailing "balance"/"avl bal" figure by taking the first match. */
    private fun amountOf(body: String): String? {
        val match = AMOUNT.find(body) ?: return null
        return "₹" + match.groupValues[1]
    }

    companion object {
        const val PREFS = "lekha_sms"
        const val KEY_QUEUE = "queue"
        const val KEY_NOTIFY = "notify"
        const val KEY_DECISIONS = "decisions"
        private const val CHANNEL_ID = "lekha_detections"
        private const val MAX_QUEUE = 100
        private val AMOUNT = Regex(
            """(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)""",
            RegexOption.IGNORE_CASE
        )
        private val KEYWORDS = listOf(
            "debited", "debit", "spent", "paid", "withdrawn",
            "sent", "purchase", "txn", "transaction", "deducted"
        )
    }
}
