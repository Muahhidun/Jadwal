package kz.dauam

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class DauamTasksWidgetProvider : AppWidgetProvider() {
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

    companion object {
        private const val preferences = "dauam_android_widget"
        private const val snapshotKey = "snapshot_json"
        private const val wideWidthDp = 250

        private val rowIds = intArrayOf(
            R.id.widget_task_1,
            R.id.widget_task_2,
            R.id.widget_task_3,
            R.id.widget_task_4,
        )

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, DauamTasksWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach { render(context, manager, it) }
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
                if (wide) R.layout.widget_tasks_wide else R.layout.widget_tasks_small,
            )
            views.setOnClickPendingIntent(R.id.widget_tasks_root, launchIntent(context, widgetId))

            val raw = context.getSharedPreferences(preferences, Context.MODE_PRIVATE)
                .getString(snapshotKey, null)
            val snapshot = raw?.let { runCatching { JSONObject(it) }.getOrNull() }
            if (snapshot == null || !isCurrentDay(snapshot)) {
                renderEmpty(views)
                manager.updateAppWidget(widgetId, views)
                return
            }

            val kz = snapshot.optString("language", "ru") == "kz"
            val tasksJson = snapshot.optJSONArray("tasks")
            val tasks = buildList {
                if (tasksJson != null) {
                    for (index in 0 until tasksJson.length()) {
                        val item = tasksJson.optJSONObject(index) ?: continue
                        add(
                            WidgetTask(
                                title = item.optString("title"),
                                done = item.optBoolean("done"),
                            ),
                        )
                    }
                }
            }
            val total = snapshot.optInt("taskTotal", tasks.size)
            val done = snapshot.optInt("taskDone", tasks.count { it.done })

            views.setTextViewText(
                R.id.widget_tasks_title,
                if (kz) "Бүгінгі істер" else "Дела сегодня",
            )
            views.setTextViewText(R.id.widget_tasks_progress_text, "$done / $total")
            views.setProgressBar(R.id.widget_tasks_progress, total.coerceAtLeast(1), done, false)

            rowIds.forEachIndexed { index, rowId ->
                val task = tasks.getOrNull(index)
                if (task == null || (!wide && index >= 3)) {
                    views.setViewVisibility(rowId, View.GONE)
                } else {
                    views.setViewVisibility(rowId, View.VISIBLE)
                    views.setTextViewText(
                        rowId,
                        "${if (task.done) "✓" else "○"}  ${task.title}",
                    )
                    views.setTextColor(
                        rowId,
                        if (task.done) 0xFFD69A54.toInt() else 0xFFF7F4EE.toInt(),
                    )
                }
            }

            if (tasks.isEmpty()) {
                views.setViewVisibility(R.id.widget_task_1, View.VISIBLE)
                views.setTextViewText(
                    R.id.widget_task_1,
                    if (kz) "Бүгін жоспарланған іс жоқ" else "На сегодня дел нет",
                )
            }

            manager.updateAppWidget(widgetId, views)
        }

        private fun renderEmpty(views: RemoteViews) {
            views.setTextViewText(R.id.widget_tasks_title, "Dauam")
            views.setTextViewText(R.id.widget_tasks_progress_text, "")
            views.setProgressBar(R.id.widget_tasks_progress, 1, 0, false)
            rowIds.forEach { views.setViewVisibility(it, View.GONE) }
            views.setViewVisibility(R.id.widget_task_1, View.VISIBLE)
            views.setTextViewText(R.id.widget_task_1, "Откройте приложение")
            views.setTextColor(R.id.widget_task_1, 0xFFAEB7C6.toInt())
        }

        private fun isCurrentDay(snapshot: JSONObject): Boolean {
            val generatedAt = (snapshot.optDouble("generatedAt") * 1000).toLong()
            if (generatedAt <= 0L) return false
            val format = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            return format.format(Date(generatedAt)) == format.format(Date())
        }

        private fun launchIntent(context: Context, widgetId: Int): PendingIntent =
            PendingIntent.getActivity(
                context,
                93_000 + widgetId,
                Intent(context, MainActivity::class.java).apply {
                    action = "kz.dauam.OPEN_TASKS_FROM_WIDGET"
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
    }
}

private data class WidgetTask(
    val title: String,
    val done: Boolean,
)
