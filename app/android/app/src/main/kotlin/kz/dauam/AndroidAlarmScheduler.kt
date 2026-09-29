package kz.dauam

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import org.json.JSONArray
import org.json.JSONObject

data class DauamAlarmSpec(
    val requestCode: Int,
    val kind: String,
    val family: String,
    val title: String,
    val timestampMillis: Long,
    val language: String,
    val heavySleeper: Boolean,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("requestCode", requestCode)
        put("kind", kind)
        put("family", family)
        put("title", title)
        put("timestampMillis", timestampMillis)
        put("language", language)
        put("heavySleeper", heavySleeper)
    }

    fun toMap(): Map<String, Any> = mapOf(
        "requestCode" to requestCode,
        "kind" to kind,
        "family" to family,
        "title" to title,
        "nextTrigger" to timestampMillis / 1000.0,
        "heavySleeper" to heavySleeper,
        "state" to "scheduled",
    )

    companion object {
        fun fromJson(json: JSONObject): DauamAlarmSpec = DauamAlarmSpec(
            requestCode = json.getInt("requestCode"),
            kind = json.getString("kind"),
            family = json.optString("family", json.getString("kind")),
            title = json.getString("title"),
            timestampMillis = json.getLong("timestampMillis"),
            language = json.optString("language", "ru"),
            heavySleeper = json.optBoolean("heavySleeper", false),
        )
    }
}

/** Native Android counterpart of iOS AlarmKit.
 *
 * Every occurrence is a one-shot `setAlarmClock` alarm. Flutter supplies a
 * rolling 14-day schedule because prayer times change every day. Specs are
 * persisted so Android can restore still-future alarms after a reboot.
 */
object AndroidAlarmScheduler {
    private const val prefsName = "dauam_native_alarms"
    private const val specsKey = "scheduled_specs_v1"
    private const val pendingActionKey = "pending_action"
    private const val testBaseRequestCode = 29_000

    fun capabilities(context: Context): Map<String, Any> {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            alarmManager.canScheduleExactAlarms()
        val fullScreen = Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE ||
            notificationManager.canUseFullScreenIntent()
        val notifications = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
        return mapOf(
            "platform" to "android",
            "canScheduleExact" to exact,
            "canUseFullScreen" to fullScreen,
            "notificationsGranted" to notifications,
            "ready" to (exact && fullScreen && notifications),
        )
    }

    /** Opens only the next missing system access screen. */
    fun requestNextPermission(context: Context): Map<String, Any> {
        val state = capabilities(context)
        val intent = when {
            state["canScheduleExact"] != true && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                    data = Uri.parse("package:${context.packageName}")
                }

            state["canUseFullScreen"] != true &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE ->
                Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                    data = Uri.parse("package:${context.packageName}")
                }

            else -> null
        }

        if (intent != null) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
            } catch (_: Exception) {
                context.startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:${context.packageName}")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    },
                )
            }
        }
        return capabilities(context) + ("openedSettings" to (intent != null))
    }

    fun syncPrayerAlarms(
        context: Context,
        entries: List<Map<*, *>>,
    ): Map<String, Any> {
        val enabledEntries = entries.filter { it["enabled"] == true }
        if (enabledEntries.isNotEmpty() && capabilities(context)["canScheduleExact"] != true) {
            throw SecurityException("Exact alarm access is required")
        }

        val retained = loadSpecs(context).filter { it.family == "test" }
        loadSpecs(context)
            .filter { it.family != "test" }
            .forEach { cancelPendingIntent(context, it.requestCode) }

        val scheduled = mutableListOf<DauamAlarmSpec>()
        for (entry in enabledEntries) {
            val requestCode = (entry["requestCode"] as? Number)?.toInt() ?: continue
            val timestamp = ((entry["timestamp"] as? Number)?.toDouble() ?: 0.0) * 1000.0
            if (timestamp <= System.currentTimeMillis()) continue
            val kind = entry["id"] as? String ?: continue
            val family = entry["family"] as? String ?: kind
            val language = entry["language"] as? String ?: "ru"
            val heavy = kind == "fajr" && entry["heavySleeper"] == true
            val primary = DauamAlarmSpec(
                requestCode = requestCode,
                kind = kind,
                family = family,
                title = entry["title"] as? String ?: kind,
                timestampMillis = timestamp.toLong(),
                language = language,
                heavySleeper = heavy,
            )
            schedule(context, primary)
            scheduled += primary

            if (heavy) {
                val backupMinutes = (entry["backupMinutes"] as? List<*>)
                    ?.mapNotNull { (it as? Number)?.toInt() }
                    ?.take(3)
                    ?: listOf(3, 6, 9)
                backupMinutes.forEachIndexed { index, minutes ->
                    val backup = primary.copy(
                        requestCode = requestCode + index + 1,
                        kind = "fajr_backup_${index + 1}",
                        title = "${primary.title} · ${index + 2}/${backupMinutes.size + 1}",
                        timestampMillis = primary.timestampMillis + minutes * 60_000L,
                        heavySleeper = true,
                    )
                    schedule(context, backup)
                    scheduled += backup
                }
            }
        }

        saveSpecs(context, retained + scheduled)
        return mapOf(
            "success" to true,
            "mode" to "alarmManager",
            "scheduled" to scheduled.size,
            "alarms" to scheduled.map { it.toMap() },
        )
    }

    fun scheduleTestAlarm(
        context: Context,
        seconds: Double,
        title: String,
        language: String,
        heavySleeper: Boolean,
        backupMinutes: List<Int>,
    ): Map<String, Any> {
        if (capabilities(context)["canScheduleExact"] != true) {
            throw SecurityException("Exact alarm access is required")
        }
        cancelFamily(context, "test")
        val target = System.currentTimeMillis() + (seconds.coerceAtLeast(1.0) * 1000).toLong()
        val primary = DauamAlarmSpec(
            requestCode = testBaseRequestCode,
            kind = "test",
            family = "test",
            title = title,
            timestampMillis = target,
            language = language,
            heavySleeper = heavySleeper,
        )
        val specs = mutableListOf(primary)
        if (heavySleeper) {
            backupMinutes.take(3).forEachIndexed { index, minutes ->
                specs += primary.copy(
                    requestCode = testBaseRequestCode + index + 1,
                    kind = "test_backup_${index + 1}",
                    title = "$title · ${index + 2}/${backupMinutes.take(3).size + 1}",
                    timestampMillis = target + minutes * 60_000L,
                )
            }
        }
        specs.forEach { schedule(context, it) }
        saveSpecs(context, loadSpecs(context).filter { it.family != "test" } + specs)
        return mapOf(
            "success" to true,
            "mode" to "alarmManager",
            "scheduled" to specs.size,
        )
    }

    fun pendingAlarms(context: Context): List<Map<String, Any>> {
        val now = System.currentTimeMillis()
        return loadSpecs(context)
            .filter { it.timestampMillis > now }
            .sortedBy { it.timestampMillis }
            .map { it.toMap() }
    }

    fun restoreFutureAlarms(context: Context) {
        if (capabilities(context)["canScheduleExact"] != true) return
        val future = loadSpecs(context).filter { it.timestampMillis > System.currentTimeMillis() }
        future.forEach { schedule(context, it) }
        saveSpecs(context, future)
    }

    fun markTriggered(context: Context, requestCode: Int) {
        saveSpecs(context, loadSpecs(context).filter { it.requestCode != requestCode })
    }

    fun cancelFamily(context: Context, family: String) {
        val specs = loadSpecs(context)
        specs.filter { it.family == family }.forEach {
            cancelPendingIntent(context, it.requestCode)
        }
        saveSpecs(context, specs.filter { it.family != family })
    }

    fun snooze(context: Context, source: DauamAlarmSpec, minutes: Int = 5) {
        if (capabilities(context)["canScheduleExact"] != true) return
        val snoozed = source.copy(
            requestCode = 29_500 + (source.requestCode % 400),
            kind = "${source.kind}_snooze",
            timestampMillis = System.currentTimeMillis() + minutes * 60_000L,
            heavySleeper = false,
        )
        cancelPendingIntent(context, snoozed.requestCode)
        schedule(context, snoozed)
        saveSpecs(
            context,
            loadSpecs(context).filter { it.requestCode != snoozed.requestCode } + snoozed,
        )
    }

    fun setPendingAction(context: Context, action: String) {
        prefs(context).edit().putString(pendingActionKey, action).apply()
    }

    fun claimPendingAction(context: Context): String? {
        val value = prefs(context).getString(pendingActionKey, null)
        if (value != null) prefs(context).edit().remove(pendingActionKey).apply()
        return value
    }

    private fun schedule(context: Context, spec: DauamAlarmSpec) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val showIntent = PendingIntent.getActivity(
            context,
            9_000,
            Intent(context, MainActivity::class.java).apply {
                action = "kz.dauam.OPEN_ALARM_SETTINGS"
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarmManager.setAlarmClock(
            AlarmManager.AlarmClockInfo(spec.timestampMillis, showIntent),
            alarmPendingIntent(context, spec),
        )
    }

    private fun alarmPendingIntent(context: Context, spec: DauamAlarmSpec): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            spec.requestCode,
            Intent(context, AlarmReceiver::class.java).apply {
                action = "kz.dauam.RING_ALARM"
                putAlarmSpec(spec)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun cancelPendingIntent(context: Context, requestCode: Int) {
        val pending = PendingIntent.getBroadcast(
            context,
            requestCode,
            Intent(context, AlarmReceiver::class.java).apply {
                action = "kz.dauam.RING_ALARM"
            },
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
        if (pending != null) {
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(pending)
            pending.cancel()
        }
    }

    private fun loadSpecs(context: Context): List<DauamAlarmSpec> {
        val raw = prefs(context).getString(specsKey, "[]") ?: "[]"
        return try {
            val array = JSONArray(raw)
            buildList {
                for (index in 0 until array.length()) {
                    add(DauamAlarmSpec.fromJson(array.getJSONObject(index)))
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun saveSpecs(context: Context, specs: List<DauamAlarmSpec>) {
        val unique = specs.associateBy { it.requestCode }.values.sortedBy { it.timestampMillis }
        val array = JSONArray()
        unique.forEach { array.put(it.toJson()) }
        prefs(context).edit().putString(specsKey, array.toString()).apply()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
}

fun Intent.putAlarmSpec(spec: DauamAlarmSpec): Intent = apply {
    putExtra("alarm_request_code", spec.requestCode)
    putExtra("alarm_kind", spec.kind)
    putExtra("alarm_family", spec.family)
    putExtra("alarm_title", spec.title)
    putExtra("alarm_timestamp", spec.timestampMillis)
    putExtra("alarm_language", spec.language)
    putExtra("alarm_heavy", spec.heavySleeper)
}

fun Intent.readAlarmSpec(): DauamAlarmSpec = DauamAlarmSpec(
    requestCode = getIntExtra("alarm_request_code", 0),
    kind = getStringExtra("alarm_kind") ?: "alarm",
    family = getStringExtra("alarm_family") ?: getStringExtra("alarm_kind") ?: "alarm",
    title = getStringExtra("alarm_title") ?: "Dauam",
    timestampMillis = getLongExtra("alarm_timestamp", System.currentTimeMillis()),
    language = getStringExtra("alarm_language") ?: "ru",
    heavySleeper = getBooleanExtra("alarm_heavy", false),
)
