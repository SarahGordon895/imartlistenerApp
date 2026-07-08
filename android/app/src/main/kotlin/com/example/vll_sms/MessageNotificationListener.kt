package com.example.vll_sms

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.text.TextUtils
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Captures SMS + WhatsApp notifications so the Flutter app can sync them
 * into the portal inbox for manual reply.
 */
class MessageNotificationListener : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null || sbn.isOngoing) return
        val pkg = sbn.packageName ?: return
        val channel = when (pkg) {
            "com.whatsapp", "com.whatsapp.w4b" -> "whatsapp"
            "com.google.android.apps.messaging",
            "com.android.mms",
            "com.samsung.android.messaging",
            "com.android.messaging" -> "sms"
            else -> null
        } ?: return

        val extras: Bundle = sbn.notification?.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim().orEmpty()
        val body = when {
            bigText.isNotEmpty() -> bigText
            text.isNotEmpty() -> text
            else -> return
        }
        if (body.isEmpty() || title.equals("WhatsApp", ignoreCase = true)) return
        // Skip group summary / reaction-only noise.
        if (body.equals("Checking for new messages", ignoreCase = true)) return

        val phone = extractPhone(title) ?: extractPhone(body)
        val payload = JSONObject()
            .put("channel", channel)
            .put("package", pkg)
            .put("sender", phone ?: "")
            .put("contact_name", title)
            .put("body", body)
            .put("time_ms", sbn.postTime)
            .toString()

        Companion.emit(payload)
    }

    private fun extractPhone(raw: String): String? {
        val digits = raw.replace(Regex("[^0-9+]"), " ")
        val match = Regex("(\\+?\\d[\\d\\s-]{8,}\\d)").find(digits)?.groupValues?.getOrNull(1)
            ?: return null
        val cleaned = match.replace(Regex("[^0-9]"), "")
        return if (cleaned.length in 9..15) cleaned else null
    }

    companion object {
        private val queue = ConcurrentLinkedQueue<String>()
        @Volatile private var sink: EventChannel.EventSink? = null

        fun emit(payload: String) {
            val s = sink
            if (s != null) {
                try {
                    s.success(payload)
                } catch (_: Throwable) {
                    queue.offer(payload)
                }
            } else {
                queue.offer(payload)
                while (queue.size > 200) queue.poll()
            }
        }

        fun attach(eventSink: EventChannel.EventSink?) {
            sink = eventSink
            if (eventSink == null) return
            while (true) {
                val next = queue.poll() ?: break
                try {
                    eventSink.success(next)
                } catch (_: Throwable) {
                    queue.offer(next)
                    break
                }
            }
        }

        fun isEnabled(context: Context): Boolean {
            val flat = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners"
            ) ?: return false
            val me = ComponentName(context, MessageNotificationListener::class.java)
            val splitter = TextUtils.SimpleStringSplitter(':')
            splitter.setString(flat)
            while (splitter.hasNext()) {
                val cn = ComponentName.unflattenFromString(splitter.next())
                if (cn != null && cn == me) return true
            }
            return false
        }

        fun openSettings(context: Context) {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            } else {
                Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }
    }
}
