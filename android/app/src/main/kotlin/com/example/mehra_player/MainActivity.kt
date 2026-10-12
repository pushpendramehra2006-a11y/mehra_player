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
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getThumbnail" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        try {
                            val bitmap = ThumbnailUtils.createVideoThumbnail(path, MediaStore.Images.Thumbnails.MINI_KIND)
                            if (bitmap != null) {
                                val stream = ByteArrayOutputStream()
                                bitmap.compress(Bitmap.CompressFormat.JPEG, 60, stream)
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
                "cancelNotification" -> {
                    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    manager.cancel(101)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        when (intent.action) {
            "ACTION_PLAY_PAUSE" -> methodChannel?.invokeMethod("onPlayPauseTrigger", null)
            "ACTION_PREV" -> methodChannel?.invokeMethod("onPrevTrigger", null)
            "ACTION_NEXT" -> methodChannel?.invokeMethod("onNextTrigger", null)
        }
    }

    private fun showMediaNotification(title: String, isPlaying: Boolean) {
        try {
            val channelId = "mehra_media_playback"
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val chan = NotificationChannel(channelId, "Mehra Player Playback", NotificationManager.IMPORTANCE_LOW)
                chan.description = "Audio & Video playback controls"
                manager.createNotificationChannel(chan)
            }

            val openIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val flagImmutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

            val pOpenIntent = PendingIntent.getActivity(this, 0, openIntent, flagImmutable)
            val pPrev = PendingIntent.getActivity(this, 1, Intent(this, MainActivity::class.java).apply { action = "ACTION_PREV" }, flagImmutable)
            val pPlay = PendingIntent.getActivity(this, 2, Intent(this, MainActivity::class.java).apply { action = "ACTION_PLAY_PAUSE" }, flagImmutable)
            val pNext = PendingIntent.getActivity(this, 3, Intent(this, MainActivity::class.java).apply { action = "ACTION_NEXT" }, flagImmutable)

            val playIcon = if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, channelId)
            } else {
                Notification.Builder(this)
            }

            builder.setSmallIcon(android.R.drawable.ic_media_play)
                .setContentTitle(title)
                .setContentText("Mehra Player")
                .setContentIntent(pOpenIntent)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setOngoing(isPlaying)
                .addAction(Notification.Action.Builder(android.R.drawable.ic_media_previous, "Previous", pPrev).build())
                .addAction(Notification.Action.Builder(playIcon, "Play/Pause", pPlay).build())
                .addAction(Notification.Action.Builder(android.R.drawable.ic_media_next, "Next", pNext).build())

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                builder.style = Notification.MediaStyle().setShowActionsInCompactView(0, 1, 2)
            }

            manager.notify(101, builder.build())
        } catch (e: Exception) {
            // Keep app safe from notification crashes
        }
    }
}
