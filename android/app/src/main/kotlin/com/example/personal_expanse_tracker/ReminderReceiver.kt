package com.example.personal_expanse_tracker

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.util.Calendar

/**
 * The daily "money needs attention" nudge, delivered while the app is closed.
 *
 * Done with AlarmManager rather than a notifications plugin on purpose: the app
 * already owns a notification channel and a permission flow for SMS detection,
 * and one repeating reminder did not justify two more packages plus core
 * library desugaring — which this machine can't even download through its TLS
 * proxy.
 *
 * The text is written by Dart whenever the app runs and stored here, so the
 * alarm has something to say without waking any Dart code. It repeats daily and
 * is re-armed after a reboot, which otherwise clears every alarm.
 */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            schedule(context)
            return
        }
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val title = prefs.getString(KEY_TITLE, null) ?: return
        val body = prefs.getString(KEY_BODY, "") ?: ""
        notify(context, title, body)
        // setExactAndAllowWhileIdle-style alarms are one-shot; re-arm for
        // tomorrow. setRepeating would drift and can't be inexact-while-idle.
        schedule(context)
    }

    private fun notify(context: Context, title: String, body: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Reminders",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = "Overdue debts and money that needs attention"
                }
            )
        }
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS revoked since the alarm was set. Nothing to do
            // and nothing worth crashing over.
        }
    }

    companion object {
        const val PREFS = "lekha_reminders"
        const val KEY_TITLE = "title"
        const val KEY_BODY = "body"
        const val KEY_HOUR = "hour"
        private const val CHANNEL_ID = "lekha_reminders"
        private const val NOTIFICATION_ID = 1001
        private const val REQUEST_CODE = 5150

        private fun pendingIntent(context: Context): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                REQUEST_CODE,
                Intent(context, ReminderReceiver::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

        /** Arm the next occurrence of the stored hour. Inexact: an exact alarm
         *  needs a special permission, and a debt nudge is not to the second. */
        fun schedule(context: Context) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (prefs.getString(KEY_TITLE, null) == null) return
            val hour = prefs.getInt(KEY_HOUR, 9)
            val next = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
                if (timeInMillis <= System.currentTimeMillis()) {
                    add(Calendar.DAY_OF_YEAR, 1)
                }
            }
            val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            manager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                next.timeInMillis,
                pendingIntent(context)
            )
        }

        fun cancel(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .remove(KEY_TITLE)
                .remove(KEY_BODY)
                .apply()
            val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            manager.cancel(pendingIntent(context))
            NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
        }
    }
}
