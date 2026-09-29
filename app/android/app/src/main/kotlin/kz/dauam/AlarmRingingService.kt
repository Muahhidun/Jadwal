package kz.dauam

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

class AlarmRingingService : Service() {
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var currentSpec: DauamAlarmSpec? = null
    private val handler = Handler(Looper.getMainLooper())
    private val autoStop = Runnable { stopSelf() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val spec = intent?.readAlarmSpec() ?: return START_NOT_STICKY
        currentSpec = spec
        ensureChannel()
        startForeground(notificationId, buildNotification(spec))
        beginAlarmOutput()
        handler.removeCallbacks(autoStop)
        handler.postDelayed(autoStop, maxRingDurationMillis)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(autoStop)
        player?.runCatching {
            if (isPlaying) stop()
            release()
        }
        player = null
        vibrator?.cancel()
        vibrator = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun beginAlarmOutput() {
        player?.runCatching {
            if (isPlaying) stop()
            release()
        }
        vibrator?.cancel()

        wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Dauam:PrayerAlarm")
            .apply { acquire(maxRingDurationMillis + 5_000L) }

        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val descriptor = resources.openRawResourceFd(R.raw.dauam_wake)
        player = MediaPlayer().apply {
            setAudioAttributes(attributes)
            setDataSource(descriptor.fileDescriptor, descriptor.startOffset, descriptor.length)
            isLooping = true
            prepare()
            start()
        }
        descriptor.close()

        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                .defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        val pattern = longArrayOf(0, 500, 350, 900, 350, 500, 800)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(
                VibrationEffect.createWaveform(pattern, 0),
                attributes,
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }
    }

    private fun buildNotification(spec: DauamAlarmSpec): Notification {
        val fullScreenIntent = PendingIntent.getActivity(
            this,
            40_000 + spec.requestCode,
            Intent(this, AlarmActivity::class.java).putAlarmSpec(spec).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val awake = actionIntent(spec, AlarmActionReceiver.actionAwake, 1)
        val secondaryAction = if (spec.heavySleeper) {
            AlarmActionReceiver.actionStopCurrent
        } else {
            AlarmActionReceiver.actionSnooze
        }
        val secondary = actionIntent(spec, secondaryAction, 2)
        val kz = spec.language == "kz"

        return Notification.Builder(this, channelId)
            .setSmallIcon(R.drawable.ic_dauam_alarm)
            .setContentTitle(spec.title)
            .setContentText(
                if (spec.heavySleeper) {
                    if (kz) "Оянсаңыз, қалған дабылдарды өшіріңіз" else "Подтвердите пробуждение, чтобы отменить остальные сигналы"
                } else {
                    if (kz) "Dauam жүйелік будильнигі" else "Системный будильник Dauam"
                },
            )
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setPriority(Notification.PRIORITY_MAX)
            .setColor(Color.rgb(201, 143, 77))
            .setContentIntent(fullScreenIntent)
            .setFullScreenIntent(fullScreenIntent, true)
            .addAction(
                Notification.Action.Builder(
                    null,
                    if (spec.heavySleeper) {
                        if (kz) "3 минуттан кейін қайталау" else "Повторить через 3 минуты"
                    } else {
                        if (kz) "5 минутқа шегеру" else "Отложить на 5 минут"
                    },
                    secondary,
                ).build(),
            )
            .addAction(
                Notification.Action.Builder(
                    null,
                    if (spec.heavySleeper) {
                        if (kz) "Ояндым · бәрін өшіру" else "Я проснулся · отключить остальные"
                    } else {
                        if (kz) "Тоқтату" else "Остановить"
                    },
                    awake,
                ).build(),
            )
            .build()
    }

    private fun actionIntent(spec: DauamAlarmSpec, action: String, suffix: Int): PendingIntent =
        PendingIntent.getBroadcast(
            this,
            80_000 + spec.requestCode * 3 + suffix,
            Intent(this, AlarmActionReceiver::class.java).putAlarmSpec(spec).apply {
                this.action = action
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            channelId,
            "Будильники Dauam",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Системные будильники молитв"
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setSound(null, null)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val channelId = "dauam_native_alarm_v1"
        private const val notificationId = 7_501
        private const val maxRingDurationMillis = 10 * 60 * 1000L
    }
}
