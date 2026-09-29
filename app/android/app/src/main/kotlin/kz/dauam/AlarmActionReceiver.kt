package kz.dauam

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class AlarmActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val spec = intent.readAlarmSpec()
        stopRinging(context)

        when (intent.action) {
            actionStopCurrent -> Unit
            actionSnooze -> AndroidAlarmScheduler.snooze(context, spec)
            actionAwake -> {
                AndroidAlarmScheduler.cancelFamily(context, spec.family)
                AndroidAlarmScheduler.setPendingAction(context, "alarm_awake")
                context.startActivity(
                    Intent(context, MainActivity::class.java).apply {
                        action = "kz.dauam.ALARM_AWAKE"
                        putExtra("alarm_action", "alarm_awake")
                        addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                Intent.FLAG_ACTIVITY_SINGLE_TOP,
                        )
                    },
                )
            }
        }
    }

    private fun stopRinging(context: Context) {
        context.stopService(Intent(context, AlarmRingingService::class.java))
    }

    companion object {
        const val actionStopCurrent = "kz.dauam.ALARM_STOP_CURRENT"
        const val actionSnooze = "kz.dauam.ALARM_SNOOZE"
        const val actionAwake = "kz.dauam.ALARM_AWAKE"
    }
}
