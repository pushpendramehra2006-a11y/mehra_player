package com.example.mehra_player

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL_BRIGHTNESS = "com.mehra.player/brightness"
    private val CHANNEL_MEDIA = "com.mehra.player/media"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_BRIGHTNESS).setMethodCallHandler { call, result ->
            if (call.method == "setBrightness") {
                val b = call.argument<Double>("brightness")?.toFloat() ?: -1f
                runOnUiThread {
                    val lp = window.attributes
                    lp.screenBrightness = b
                    window.attributes = lp
                }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_MEDIA).setMethodCallHandler { call, result ->
            if (call.method == "showNotification") {
                val title = call.argument<String>("title") ?: "Mehra Player"
                val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                showMediaNotification(title, isPlaying)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun showMediaNotification(title: String, isPlaying: Boolean) {
        val channelId = "mehra_media_channel"
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val chan = NotificationChannel(channelId, "Media Playback", NotificationManager.IMPORTANCE_LOW)
            manager.createNotificationChannel(chan)
        }
        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle("Mehra Player")
            .setContentText(title)
            .setOngoing(isPlaying)
            .setPriority(NotificationCompat.PRIORITY_LOW)
        manager.notify(101, builder.build())
    }
}
