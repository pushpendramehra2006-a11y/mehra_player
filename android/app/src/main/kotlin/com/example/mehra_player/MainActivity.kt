package com.example.mehra_player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.media.ThumbnailUtils
import android.os.Build
import android.provider.MediaStore
import android.util.Rational
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.mehra.player/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getThumbnail" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        try {
                            val bitmap = ThumbnailUtils.createVideoThumbnail(path, MediaStore.Images.Thumbnails.MINI_KIND)
                            if (bitmap != null) {
                                val stream = ByteArrayOutputStream()
                                bitmap.compress(Bitmap.CompressFormat.JPEG, 70, stream)
                                result.success(stream.toByteArray())
                            } else {
                                result.success(null)
                            }
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    } else {
                        result.success(null)
                    }
                }
                "enterPip" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(16, 9))
                                .build()
                            enterPictureInPictureMode(params)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "setBrightness" -> {
                    val b = call.argument<Double>("brightness")?.toFloat() ?: -1f
                    runOnUiThread {
                        val lp = window.attributes
                        lp.screenBrightness = b
                        window.attributes = lp
                    }
                    result.success(null)
                }
                "showNotification" -> {
                    val title = call.argument<String>("title") ?: "Mehra Player"
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    showMediaNotification(title, isPlaying)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun showMediaNotification(title: String, isPlaying: Boolean) {
        val channelId = "mehra_music_channel"
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val chan = NotificationChannel(channelId, "Media Playback", NotificationManager.IMPORTANCE_LOW)
            manager.createNotificationChannel(chan)
        }
        val intent = Intent(this, MainActivity::class.java)
        val pIntent = PendingIntent.getActivity(
            this, 0, intent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            Notification.Builder(this)
        }

        builder.setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle("Mehra Player")
            .setContentText(title)
            .setContentIntent(pIntent)
            .setOngoing(isPlaying)

        manager.notify(1001, builder.build())
    }
}
