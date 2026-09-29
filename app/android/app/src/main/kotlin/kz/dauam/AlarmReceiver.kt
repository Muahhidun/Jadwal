package kz.dauam

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val spec = intent.readAlarmSpec()
        AndroidAlarmScheduler.markTriggered(context, spec.requestCode)
        val serviceIntent = Intent(context, AlarmRingingService::class.java)
            .putAlarmSpec(spec)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
