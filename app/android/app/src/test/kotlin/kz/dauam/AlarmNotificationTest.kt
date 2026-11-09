package kz.dauam

import android.app.Application
import android.app.Notification
import android.content.ComponentName
import android.os.Build
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import android.content.Intent
import org.robolectric.Shadows.shadowOf
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [24, 26], application = Application::class)
class AlarmNotificationTest {
    @Test
    fun heavySleepActionDescribesStoppingOnlyTheCurrentSignal() {
        for ((language, label) in listOf(
            "ru" to "Выключить этот сигнал",
            "kz" to "Осы дабылды өшіру",
        )) {
            val service = Robolectric.buildService(AlarmRingingService::class.java).get()
            val spec = DauamAlarmSpec(
                requestCode = 20_000,
                kind = "fajr",
                family = "fajr:2026-10-22",
                title = "Фаджр",
                timestampMillis = System.currentTimeMillis(),
                language = language,
                heavySleeper = true,
            )
            val method = AlarmRingingService::class.java.getDeclaredMethod(
                "buildNotification", DauamAlarmSpec::class.java,
            ).apply { isAccessible = true }
            val notification = method.invoke(service, spec) as Notification
            assertEquals(label, notification.actions[0].title.toString())
            assertEquals(
                AlarmActionReceiver.actionStopCurrent,
                shadowOf(notification.actions[0].actionIntent).savedIntent.action,
            )

            val controller = Robolectric.buildActivity(
                AlarmActivity::class.java,
                Intent(service, AlarmActivity::class.java).putAlarmSpec(spec),
            ).create()
            val root = controller.get().findViewById<android.view.ViewGroup>(android.R.id.content)
            fun hasLabel(view: android.view.View): Boolean =
                (view is android.widget.Button && view.text.toString() == label) ||
                    (view is android.view.ViewGroup && (0 until view.childCount).any {
                        hasLabel(view.getChildAt(it))
                    })
            org.junit.Assert.assertTrue(hasLabel(root))
            controller.destroy()
        }
    }

    @Test
    fun alarmNotificationCanBeBuiltOnEverySupportedApi() {
        val service = Robolectric.buildService(AlarmRingingService::class.java).get()
        val spec = DauamAlarmSpec(
            requestCode = 20_000,
            kind = "fajr",
            family = "fajr:2026-10-22",
            title = "Фаджр",
            timestampMillis = System.currentTimeMillis() + 60_000,
            language = "ru",
            heavySleeper = false,
        )
        val method = AlarmRingingService::class.java.getDeclaredMethod(
            "buildNotification", DauamAlarmSpec::class.java,
        ).apply { isAccessible = true }
        val notification = method.invoke(service, spec) as Notification

        assertEquals(Notification.CATEGORY_ALARM, notification.category)
        assertEquals(2, notification.actions.size)
        assertNotNull(notification.contentIntent)
        if (Build.VERSION.SDK_INT >= 26) {
            assertEquals("dauam_native_alarm_v1", notification.channelId)
        }
    }

    @Test
    fun notificationActionReceiverIsRegisteredAndNotExported() {
        val context = RuntimeEnvironment.getApplication()
        val receiver = context.packageManager.getReceiverInfo(
            ComponentName(context.packageName,
                "com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver"),
            0,
        )
        assertFalse(receiver.exported)
        assertEquals(context.packageName, receiver.packageName)
    }
}
