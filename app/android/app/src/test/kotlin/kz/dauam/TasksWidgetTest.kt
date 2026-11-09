package kz.dauam

import android.app.AlarmManager
import android.app.Application
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Looper
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAlarmManager
import java.time.Instant
import java.util.TimeZone

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [24, 26], application = Application::class)
class TasksWidgetTest {
    private val friday = Instant.parse("2026-10-23T23:59:00Z").toEpochMilli()
    private val midnight = Instant.parse("2026-10-24T00:00:00Z").toEpochMilli()
    private lateinit var context: Context
    private lateinit var originalZone: TimeZone
    private var currentTime = 0L

    @Before fun setUp() {
        context = RuntimeEnvironment.getApplication()
        originalZone = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
        currentTime = friday
        DauamTasksWidgetProvider.nowMillis = { currentTime }
        ShadowAlarmManager.setAutoSchedule(false)
    }

    @After fun tearDown() {
        TimeZone.setDefault(originalZone)
        DauamTasksWidgetProvider.nowMillis = { System.currentTimeMillis() }
    }

    private fun snapshot(language: String = "ru", atMillis: Long = friday): String = JSONObject().apply {
        put("schemaVersion", 2)
        put("generatedAt", atMillis / 1000.0)
        put("language", language)
        put("tasks", JSONArray().put(JSONObject().apply {
            put("title", "Пятничное дело")
            put("done", true)
        }))
        put("taskDone", 1)
        put("taskTotal", 1)
    }.toString()

    private fun create(language: String = "ru"): Pair<Int, org.robolectric.shadows.ShadowAppWidgetManager> {
        context.getSharedPreferences("dauam_android_widget", Context.MODE_PRIVATE)
            .edit().putString("snapshot_json", snapshot(language)).commit()
        val manager = shadowOf(AppWidgetManager.getInstance(context))
        val id = manager.createWidget(DauamTasksWidgetProvider::class.java, R.layout.widget_tasks_small)
        return id to manager
    }

    @Test fun tasksOnlyWidgetSchedulesItsOwnMidnightRefresh() {
        create()
        val alarm = shadowOf(context.getSystemService(Context.ALARM_SERVICE) as AlarmManager)
            .scheduledAlarms.firstOrNull()
        assertNotNull("Tasks widget must refresh even without a prayer widget", alarm)
        assertEquals(midnight, alarm!!.triggerAtTime)
    }

    @Test fun midnightAlarmClearsFridayCompletionWithoutOpeningFlutter() {
        val (id, widgets) = create()
        assertEquals("1 / 1", widgets.getViewFor(id).findViewById<TextView>(R.id.widget_tasks_progress_text).text.toString())
        val alarms = shadowOf(context.getSystemService(Context.ALARM_SERVICE) as AlarmManager)
        val alarm = alarms.scheduledAlarms.firstOrNull()
        assertNotNull("No midnight invalidation is registered", alarm)
        currentTime = midnight + 1_000
        alarm!!.operation!!.send()
        shadowOf(Looper.getMainLooper()).idle()
        val view = widgets.getViewFor(id)
        assertEquals("", view.findViewById<TextView>(R.id.widget_tasks_progress_text).text.toString())
        assertFalse(view.findViewById<TextView>(R.id.widget_task_1).text.contains("Пятничное"))
        assertTrue(view.findViewById<TextView>(R.id.widget_task_1).text.contains("Откройте"))
    }

    @Test fun staleKazakhSnapshotHasLocalizedEmptyState() {
        currentTime = midnight + 1_000
        val (id, widgets) = create("kz")
        assertEquals("Қолданбаны ашыңыз", widgets.getViewFor(id)
            .findViewById<TextView>(R.id.widget_task_1).text.toString())
    }

    @Test fun timeChangeInvalidatesOldChecksAndReplacesRefreshAlarm() {
        val (id, widgets) = create()
        currentTime = midnight + 1_000
        DauamTasksWidgetProvider().onReceive(context, Intent(Intent.ACTION_TIME_CHANGED))
        assertEquals("", widgets.getViewFor(id)
            .findViewById<TextView>(R.id.widget_tasks_progress_text).text.toString())
        val alarms = shadowOf(context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).scheduledAlarms
        assertEquals(1, alarms.size)
        assertEquals(midnight + 86_400_000, alarms.single().triggerAtTime)
    }

    @Test fun aFreshSnapshotRestoresTasksAfterAnEmptyState() {
        currentTime = midnight + 1_000
        val (id, widgets) = create()
        assertEquals("", widgets.getViewFor(id)
            .findViewById<TextView>(R.id.widget_tasks_progress_text).text.toString())
        DauamPrayerWidgetProvider.saveSnapshot(context, snapshot(atMillis = currentTime))
        assertEquals("1 / 1", widgets.getViewFor(id)
            .findViewById<TextView>(R.id.widget_tasks_progress_text).text.toString())
    }

    @Test fun removingTheLastWidgetCancelsItsRefresh() {
        create()
        DauamTasksWidgetProvider().onDisabled(context)
        assertTrue(shadowOf(context.getSystemService(Context.ALARM_SERVICE) as AlarmManager)
            .scheduledAlarms.isEmpty())
    }
}
