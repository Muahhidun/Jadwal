package kz.dauam

import android.app.Activity
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class AlarmActivity : Activity() {
    private lateinit var spec: DauamAlarmSpec

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        configureWindow()
        render(intent.readAlarmSpec())
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        render(intent.readAlarmSpec())
    }

    @Suppress("DEPRECATION")
    private fun configureWindow() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD,
        )
        window.statusBarColor = background
        window.navigationBarColor = background
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LAYOUT_STABLE
    }

    private fun render(value: DauamAlarmSpec) {
        spec = value
        val kz = spec.language == "kz"
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(28), dp(40), dp(28), dp(34))
            setBackgroundColor(AlarmActivity.background)
        }

        root.addView(label("دوام", 22f, gold, true))
        root.addView(spacer(36))
        root.addView(label(spec.title, 30f, Color.WHITE, true))
        root.addView(spacer(14))
        root.addView(
            label(
                SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date()),
                72f,
                Color.WHITE,
                false,
            ),
        )
        root.addView(spacer(18))
        root.addView(
            label(
                if (spec.heavySleeper) {
                    if (kz) "Қатты ұйқы режимі қосулы" else "Режим «Крепкий сон» включён"
                } else {
                    if (kz) "Намаз уақыты" else "Время молитвы"
                },
                16f,
                muted,
                false,
            ),
        )

        val space = LinearLayout.LayoutParams(1, 0, 1f)
        root.addView(View(this), space)

        val repeat = actionButton(
            if (spec.heavySleeper) {
                if (kz) "3 минуттан кейін қайталау" else "Повторить через 3 минуты"
            } else {
                if (kz) "5 минутқа шегеру" else "Отложить на 5 минут"
            },
            filled = true,
        ) {
            sendAction(
                if (spec.heavySleeper) AlarmActionReceiver.actionStopCurrent
                else AlarmActionReceiver.actionSnooze,
            )
        }
        root.addView(repeat)
        root.addView(spacer(8))
        root.addView(
            actionButton(
                if (spec.heavySleeper) {
                    if (kz) "Ояндым · қалғандарын өшіру" else "Я проснулся · отключить остальные"
                } else {
                    if (kz) "Будильникті тоқтату" else "Остановить будильник"
                },
                filled = false,
            ) {
                sendAction(AlarmActionReceiver.actionAwake)
            },
        )

        setContentView(root)
    }

    private fun sendAction(action: String) {
        sendBroadcast(
            Intent(this, AlarmActionReceiver::class.java).putAlarmSpec(spec).apply {
                this.action = action
            },
        )
        finishAndRemoveTask()
    }

    private fun actionButton(text: String, filled: Boolean, onClick: () -> Unit): Button =
        Button(this).apply {
            this.text = text
            textSize = if (filled) 17f else 15f
            isAllCaps = false
            setTextColor(if (filled) Color.WHITE else muted)
            backgroundTintList = ColorStateList.valueOf(
                if (filled) gold else Color.TRANSPARENT,
            )
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(if (filled) 58 else 48),
            )
            setOnClickListener { onClick() }
        }

    private fun label(text: String, size: Float, color: Int, bold: Boolean): TextView =
        TextView(this).apply {
            this.text = text
            textSize = size
            setTextColor(color)
            gravity = Gravity.CENTER
            if (bold) setTypeface(typeface, android.graphics.Typeface.BOLD)
        }

    private fun spacer(height: Int) = View(this).apply {
        layoutParams = LinearLayout.LayoutParams(1, dp(height))
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        private val background = Color.rgb(8, 16, 31)
        private val panel = Color.rgb(27, 38, 57)
        private val gold = Color.rgb(201, 143, 77)
        private val muted = Color.rgb(173, 183, 198)
    }
}
