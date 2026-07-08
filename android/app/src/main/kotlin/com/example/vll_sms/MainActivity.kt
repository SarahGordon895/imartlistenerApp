package com.example.vll_sms

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "imart/notification_capture"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isEnabled" -> result.success(MessageNotificationListener.isEnabled(this))
                "openSettings" -> {
                    MessageNotificationListener.openSettings(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "imart/notification_events"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            private val main = Handler(Looper.getMainLooper())

            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                // Bridge posts from NotificationListener thread onto main for Flutter.
                MessageNotificationListener.attach(object : EventChannel.EventSink {
                    override fun success(event: Any?) {
                        main.post { events?.success(event) }
                    }

                    override fun error(code: String?, message: String?, details: Any?) {
                        main.post { events?.error(code, message, details) }
                    }

                    override fun endOfStream() {
                        main.post { events?.endOfStream() }
                    }
                })
            }

            override fun onCancel(arguments: Any?) {
                MessageNotificationListener.attach(null)
            }
        })
    }
}
