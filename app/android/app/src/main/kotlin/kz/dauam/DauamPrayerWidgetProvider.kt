package kz.dauam

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class DauamPrayerWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { render(context, appWidgetManager, it) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        render(context, appWidgetManager, appWidgetId)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == actionRefresh) updateAll(context)
    }

    companion object {
        private const val preferences = "dauam_android_widget"
        private const val snapshotKey = "snapshot_json"
        private const val actionRefresh = "kz.dauam.WIDGET_REFRESH"
        private const val refreshRequestCode = 91_201
        private const val wideWidthDp = 250

        private val prayerNameIds = intArrayOf(
            R.id.widget_prayer_1_name,
            R.id.widget_prayer_2_name,
            R.id.widget_prayer_3_name,
            R.id.widget_prayer_4_name,
            R.id.widget_prayer_5_name,
            R.id.widget_prayer_6_name,
        )
        private val prayerTimeIds = intArrayOf(
            R.id.widget_prayer_1_time,
            R.id.widget_prayer_2_time,
            R.id.widget_prayer_3_time,
            R.id.widget_prayer_4_time,
            R.id.widget_prayer_5_time,
            R.id.widget_prayer_6_time,
        )

        fun saveSnapshot(context: Context, json: String) {
            context.getSharedPreferences(preferences, Context.MODE_PRIVATE)
                .edit()
                .putString(snapshotKey, json)
                .apply()
            updateAll(context)
            DauamTasksWidgetProvider.updateAll(context)
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, DauamPrayerWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            ids.forEach { render(context, manager, it) }
        }

        private fun render(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int,
        ) {
            val minWidth = manager.getAppWidgetOptions(widgetId)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
            val wide = minWidth >= wideWidthDp
            val views = RemoteViews(
                context.packageName,
                if (wide) R.layout.widget_prayer_wide else R.layout.widget_prayer_small,
            )
            views.setOnClickPendingIntent(R.id.widget_root, launchIntent(context, widgetId))

            val raw = context.getSharedPreferences(preferences, Context.MODE_PRIVATE)
                .getString(snapshotKey, null)
            val snapshot = raw?.let { runCatching { JSONObject(it) }.getOrNull() }
            if (snapshot == null) {
                renderEmpty(views, wide)
                manager.updateAppWidget(widgetId, views)
                return
            }

            val language = snapshot.optString("language", "ru")
            val city = snapshot.optString("city", "Dauam")
            val prayersJson = snapshot.optJSONArray("prayers")
            val prayers = buildList {
                if (prayersJson != null) {
                    for (index in 0 until prayersJson.length()) {
                        val item = prayersJson.optJSONObject(index) ?: continue
                        add(
                            WidgetPrayer(
                                id = item.optString("id"),
                                title = item.optString("title"),
                                time = item.optString("time"),
                                timestampMillis = (item.optDouble("timestamp") * 1000).toLong(),
                            ),
                        )
                    }
                }
            }
            val now = System.currentTimeMillis()
            val next = prayers.firstOrNull { it.timestampMillis > now }
            if (next == null) {
                renderEmpty(views, wide)
                manager.updateAppWidget(widgetId, views)
                return
            }

            views.setTextViewText(R.id.widget_city, city)
            views.setTextViewText(
                R.id.widget_next_label,
                countdownLabel(next.id, language, next.timestampMillis, now),
            )
            views.setTextViewText(R.id.widget_exact_time, next.time)
            val elapsedTarget = SystemClock.elapsedRealtime() +
                (next.timestampMillis - System.currentTimeMillis()).coerceAtLeast(0L)
            views.setChronometer(R.id.widget_countdown, elapsedTarget, null, true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                views.setChronometerCountDown(R.id.widget_countdown, true)
            }
            views.setViewVisibility(R.id.widget_countdown, View.VISIBLE)

            if (wide) {
                val dateKey = dateKey(next.timestampMillis)
                val dayPrayers = prayers.filter { dateKey(it.timestampMillis) == dateKey }.take(6)
                prayerNameIds.indices.forEach { index ->
                    val prayer = dayPrayers.getOrNull(index)
                    views.setTextViewText(
                        prayerNameIds[index],
                        prayer?.let { shortName(it.id, language) } ?: "—",
                    )
                    views.setTextViewText(prayerTimeIds[index], prayer?.time ?: "")
                }
            }

            manager.updateAppWidget(widgetId, views)
            scheduleRefresh(context, next.timestampMillis + 1_000L)
        }

        private fun renderEmpty(views: RemoteViews, wide: Boolean) {
            views.setTextViewText(R.id.widget_city, "Dauam")
            views.setTextViewText(R.id.widget_next_label, "Откройте приложение")
            views.setTextViewText(R.id.widget_exact_time, "")
            views.setViewVisibility(R.id.widget_countdown, View.INVISIBLE)
            if (wide) {
                prayerNameIds.indices.forEach { index ->
                    views.setTextViewText(prayerNameIds[index], "—")
                    views.setTextViewText(prayerTimeIds[index], "")
                }
            }
        }

        private fun launchIntent(context: Context, widgetId: Int): PendingIntent =
            PendingIntent.getActivity(
                context,
                92_000 + widgetId,
                Intent(context, MainActivity::class.java).apply {
                    action = "kz.dauam.OPEN_FROM_WIDGET"
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        private fun scheduleRefresh(context: Context, atMillis: Long) {
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pending = PendingIntent.getBroadcast(
                context,
                refreshRequestCode,
                Intent(context, DauamPrayerWidgetProvider::class.java).apply {
                    action = actionRefresh
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            alarm.setAndAllowWhileIdle(AlarmManager.RTC, atMillis, pending)
        }

        private fun countdownLabel(
            id: String,
            language: String,
            timestamp: Long,
            now: Long,
        ): String {
            val tomorrow = dateKey(timestamp) != dateKey(now)
            return if (language == "kz") {
                val event = when (id) {
                    "fajr" -> "Таңға"
                    "sunrise" -> "Күн шығуына"
                    "dhuhr" -> "Бесінге"
                    "asr" -> "Екінтіге"
                    "maghrib" -> "Ақшамға"
                    "isha" -> "Құптанға"
                    else -> "Намазға"
                }
                if (tomorrow) "$event дейін · ертең" else "$event дейін"
            } else {
                val event = when (id) {
                    "fajr" -> "Фаджра"
                    "sunrise" -> "восхода"
                    "dhuhr" -> "Зухра"
                    "asr" -> "Асра"
                    "maghrib" -> "Магриба"
                    "isha" -> "Иша"
                    else -> "намаза"
                }
                if (tomorrow) "До $event · завтра" else "До $event"
            }
        }

        private fun shortName(id: String, language: String): String =
            if (language == "kz") {
                when (id) {
                    "fajr" -> "Таң"
                    "sunrise" -> "Күн"
                    "dhuhr" -> "Бесін"
                    "asr" -> "Екінті"
                    "maghrib" -> "Ақшам"
                    "isha" -> "Құптан"
                    else -> id
                }
            } else {
                when (id) {
                    "fajr" -> "Фаджр"
                    "sunrise" -> "Восход"
                    "dhuhr" -> "Зухр"
                    "asr" -> "Аср"
                    "maghrib" -> "Магриб"
                    "isha" -> "Иша"
                    else -> id
                }
            }

        private fun dateKey(timestampMillis: Long): String =
            SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(timestampMillis))
    }
}

private data class WidgetPrayer(
    val id: String,
    val title: String,
    val time: String,
    val timestampMillis: Long,
)
