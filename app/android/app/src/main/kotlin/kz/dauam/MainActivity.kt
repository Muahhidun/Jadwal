package kz.dauam

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorManager
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var alarmChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kz.dauam/compass_capability",
        ).setMethodCallHandler { call, result ->
            if (call.method != "isCompassAvailable") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
            val hasMagnetometer =
                sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD) != null
            val hasAccelerometer =
                sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) != null

            // An accelerometer alone can describe tilt, but cannot provide a
            // trustworthy absolute bearing to north (and therefore to Qibla).
            result.success(hasMagnetometer && hasAccelerometer)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kz.dauam/widgets",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveSnapshot" -> {
                    val snapshot = call.arguments as? String
                    if (snapshot == null) {
                        result.error("INVALID_ARGS", "Expected a JSON snapshot.", null)
                    } else {
                        DauamPrayerWidgetProvider.saveSnapshot(this, snapshot)
                        result.success(null)
                    }
                }

                // This target is used by iOS App Intents. Android alarm actions
                // are delivered through the dedicated alarm channel instead.
                "getPendingIntentTarget" -> result.success(null)

                else -> result.notImplemented()
            }
        }

        alarmChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "kz.dauam/alarm",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAlarmCapabilities" ->
                        result.success(AndroidAlarmScheduler.capabilities(this))

                    "requestAlarmPermissions" ->
                        result.success(AndroidAlarmScheduler.requestNextPermission(this))

                    "getPendingAlarmAction" ->
                        result.success(AndroidAlarmScheduler.claimPendingAction(this))

                    "getPendingAlarms" ->
                        result.success(AndroidAlarmScheduler.pendingAlarms(this))

                    "syncPrayerAlarms" -> {
                        val args = call.arguments as? Map<*, *>
                        val raw = args?.get("alarms") as? List<*>
                        if (raw == null) {
                            result.error("INVALID_ARGS", "Expected an alarms array.", null)
                            return@setMethodCallHandler
                        }
                        val entries = raw.mapNotNull { it as? Map<*, *> }
                        try {
                            result.success(
                                AndroidAlarmScheduler.syncPrayerAlarms(this, entries),
                            )
                        } catch (_: SecurityException) {
                            result.error(
                                "ALARM_PERMISSION_REQUIRED",
                                "Allow exact alarms for Dauam in Android settings.",
                                AndroidAlarmScheduler.capabilities(this),
                            )
                        } catch (error: Exception) {
                            result.error("ALARM_SCHEDULE_FAILED", error.message, null)
                        }
                    }

                    "testFajrAlarm" -> {
                        val args = call.arguments as? Map<*, *>
                        val seconds = (args?.get("seconds") as? Number)?.toDouble() ?: 10.0
                        val title = args?.get("title") as? String ?: "Фаджр (Тест)"
                        val language = args?.get("language") as? String ?: "ru"
                        val heavy = args?.get("heavySleeper") == true
                        val backupMinutes = (args?.get("backupMinutes") as? List<*>)
                            ?.mapNotNull { (it as? Number)?.toInt() }
                            ?: listOf(3, 6, 9)
                        try {
                            result.success(
                                AndroidAlarmScheduler.scheduleTestAlarm(
                                    this,
                                    seconds,
                                    title,
                                    language,
                                    heavy,
                                    backupMinutes,
                                ),
                            )
                        } catch (_: SecurityException) {
                            result.error(
                                "ALARM_PERMISSION_REQUIRED",
                                "Allow exact alarms for Dauam in Android settings.",
                                AndroidAlarmScheduler.capabilities(this),
                            )
                        } catch (error: Exception) {
                            result.error("ALARM_SCHEDULE_FAILED", error.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = intent.getStringExtra("alarm_action") ?: return
        AndroidAlarmScheduler.setPendingAction(this, action)
        alarmChannel?.invokeMethod("onAlarmAction", action)
    }
}
