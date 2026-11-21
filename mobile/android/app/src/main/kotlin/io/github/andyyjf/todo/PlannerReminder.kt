package io.github.andyyjf.todo

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import androidx.work.*
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit

internal object PlannerReminder {
    const val ALARM = "io.github.andyyjf.todo.PLAN_TOMORROW"
    const val OPEN = "io.github.andyyjf.todo.OPEN_PLAN"
    private const val PERIODIC = "todo-planner-settings-periodic"
    private const val IMMEDIATE = "todo-planner-settings-now"
    private const val CHANNEL = "todo_plan_tomorrow"
    private const val REQUEST = 3401
    private const val NOTIFICATION = "plan_tomorrow"
    private const val NEXT = "plannerNextAt"
    private const val SENT = "plannerSentDate"
    private val zone = TimeZone.getTimeZone("Asia/Shanghai")
    private val timePattern = Regex("^(?:[01]\\d|2[0-3]):[0-5]\\d$")
    private val network = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

    fun bind(context: Context, immediate: Boolean) {
        val work = WorkManager.getInstance(context)
        val periodic = PeriodicWorkRequest.Builder(PlannerSettingsWorker::class.java, 30, TimeUnit.MINUTES)
            .setInitialDelay(30, TimeUnit.MINUTES)
            .setConstraints(network)
            .build()
        work.enqueueUniquePeriodicWork(PERIODIC, ExistingPeriodicWorkPolicy.KEEP, periodic)
        if (immediate) {
            val request = OneTimeWorkRequest.Builder(PlannerSettingsWorker::class.java)
                .setConstraints(network)
                .build()
            work.enqueueUniqueWork(IMMEDIATE, ExistingWorkPolicy.KEEP, request)
        }
    }

    fun clear(context: Context, prefs: SharedPreferences) {
        val work = WorkManager.getInstance(context)
        work.cancelUniqueWork(PERIODIC)
        work.cancelUniqueWork(IMMEDIATE)
        cancelAlarm(context)
        notifications(context).cancel(NOTIFICATION, REQUEST)
        prefs.edit().remove("plannerRevision").remove("plannerEnabled").remove("plannerTime")
            .remove(NEXT).remove(SENT).remove("plannerExact").commit()
    }

    private fun date(at: Long): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply { timeZone = zone }.format(Date(at))

    private fun exact(context: Context): Boolean =
        Build.VERSION.SDK_INT < 31 || alarms(context).canScheduleExactAlarms()

    private fun alarms(context: Context) = context.getSystemService(AlarmManager::class.java)
    private fun notifications(context: Context) = context.getSystemService(NotificationManager::class.java)

    private fun alarmIntent(
        context: Context, flags: Int, at: Long = 0L, account: String = "",
    ): PendingIntent? {
        val intent = Intent(context, TodoReminderReceiver::class.java)
            .setAction(ALARM)
            .putExtra("plannerAt", at)
            .putExtra("plannerAccount", account)
        return PendingIntent.getBroadcast(context, REQUEST, intent, flags or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun cancelAlarm(context: Context) {
        alarmIntent(context, PendingIntent.FLAG_NO_CREATE)?.let { alarms(context).cancel(it) }
    }

    fun apply(context: Context, prefs: SharedPreferences, origin: String, account: String, data: JSONObject) {
        val revision = data.getLong("revision")
        val time = data.getString("time")
        require(timePattern.matches(time))
        if (revision < prefs.getLong("plannerRevision", -1)) return
        val enabled = data.getBoolean("enabled")
        val changed = enabled != prefs.getBoolean("plannerEnabled", false) ||
            time != prefs.getString("plannerTime", null)
        val edit = prefs.edit().putLong("plannerRevision", revision)
            .putBoolean("plannerEnabled", enabled).putString("plannerTime", time)
        if (changed) {
            cancelAlarm(context)
            edit.remove(NEXT)
        }
        edit.commit()
        if (!enabled) notifications(context).cancel(NOTIFICATION, REQUEST)
        restore(context, prefs, origin, account, false)
    }

    fun restore(context: Context, prefs: SharedPreferences, origin: String, account: String, force: Boolean) {
        if (!prefs.getBoolean("plannerEnabled", false) || !TodoBackground.notificationsAllowed(context)) {
            if (prefs.contains(NEXT)) {
                cancelAlarm(context)
                prefs.edit().remove(NEXT).commit()
            }
            return
        }
        val now = System.currentTimeMillis()
        val planned = prefs.getLong(NEXT, 0L)
        if (planned in 1..now) {
            deliver(context, prefs, origin, account, planned, now)
        } else {
            schedule(context, prefs, account, now, force)
        }
    }

    private fun schedule(context: Context, prefs: SharedPreferences, account: String, now: Long, force: Boolean) {
        val time = prefs.getString("plannerTime", null) ?: return
        val calendar = Calendar.getInstance(zone, Locale.ROOT).apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, time.substring(0, 2).toInt())
            set(Calendar.MINUTE, time.substring(3, 5).toInt())
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val last = prefs.getString(SENT, "").orEmpty()
        if (calendar.timeInMillis <= now || date(now) <= last) calendar.add(Calendar.DATE, 1)
        val at = calendar.timeInMillis
        val exact = exact(context)
        if (!force && prefs.getLong(NEXT, 0L) == at && prefs.getBoolean("plannerExact", false) == exact) return
        val pending = checkNotNull(alarmIntent(context, PendingIntent.FLAG_UPDATE_CURRENT, at, account))
        val alarm = alarms(context)
        try {
            if (exact) alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
            else alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
        } catch (_: SecurityException) {
            alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
        }
        prefs.edit().putLong(NEXT, at).putBoolean("plannerExact", exact).commit()
    }

    fun deliver(context: Context, prefs: SharedPreferences, origin: String, account: String, at: Long,
                now: Long = System.currentTimeMillis()) {
        if (at <= 0 || at > now || at != prefs.getLong(NEXT, 0L) || !prefs.getBoolean("plannerEnabled", false)) return
        val evening = date(at)
        if (evening == date(now) && evening > prefs.getString(SENT, "").orEmpty() &&
            TodoBackground.notificationsAllowed(context)) {
            val target = Calendar.getInstance(zone, Locale.ROOT).apply {
                timeInMillis = at
                add(Calendar.DATE, 1)
            }
            prefs.edit().putString(SENT, evening).commit()
            notify(context, origin, date(target.timeInMillis))
        }
        prefs.edit().remove(NEXT).commit()
        restore(context, prefs, origin, account, false)
    }

    private fun notify(context: Context, origin: String, date: String) {
        val manager = notifications(context)
        val open = Intent(context, MainActivity::class.java).setAction(OPEN)
            .setData(Uri.parse("todo://planner/$date"))
            .putExtra("plannerDate", date)
            .putExtra("todoOrigin", origin)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val tap = PendingIntent.getActivity(context, REQUEST, open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "规划明天", NotificationManager.IMPORTANCE_DEFAULT))
            Notification.Builder(context, CHANNEL)
        } else Notification.Builder(context)
        manager.notify(NOTIFICATION, REQUEST, builder
            .setSmallIcon(R.drawable.ic_todo_notification)
            .setContentTitle("规划明天")
            .setContentText("点按打开明日安排")
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setAutoCancel(true)
            .setContentIntent(tap)
            .build())
    }
}

class PlannerSettingsWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result =
        if (TodoBackground.syncPlannerSettings(applicationContext)) Result.success() else Result.retry()
}
