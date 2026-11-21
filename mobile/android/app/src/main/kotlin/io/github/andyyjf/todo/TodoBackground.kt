package io.github.andyyjf.todo

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.net.Uri
import android.os.*
import androidx.work.*
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

internal object TodoBackground {
    const val PERIODIC = "todo-read-periodic"
    const val ONCE = "todo-read-now"
    val io = Executors.newSingleThreadExecutor()
    private val lock = Any()
    private val networkLock = Any()
    private val plannerNetworkLock = Any()
    var channel: MethodChannel? = null
    private var processInitialized = false
    private fun prefs(c: Context) = synchronized(lock) {
        c.getSharedPreferences("todo-background",Context.MODE_PRIVATE).also {
            if(!processInitialized) {processInitialized=true;it.edit().putBoolean("running",false).commit()}
        }
    }
    private fun signal() = Handler(Looper.getMainLooper()).post { channel?.invokeMethod("backgroundChanged", null) }
    private data class Session(val path: File, val state: JSONObject, val origin: String, val cookie: String, val key: String)
    private fun utc(value: String): Long = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.ROOT).apply { timeZone=TimeZone.getTimeZone("UTC");isLenient=false }.parse(value.take(19))!!.time
    private fun due(value: String): Long? = try { SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.ROOT).apply { timeZone=TimeZone.getTimeZone("GMT+08:00");isLenient=false }.parse(value.take(16))?.time } catch (_: Exception) { null }
    private fun key(origin: String, cookie: String) = MessageDigest.getInstance("SHA-256").digest((origin+"\n"+cookie).toByteArray()).joinToString("") { "%02x".format(it) }
    private fun session(c: Context): Session? = try {
        val path=File(prefs(c).getString("path", "")!!)
        val state=JSONObject(path.readText())
        val origin=state.getString("origin");val uri=Uri.parse(origin)
        val local=BuildConfig.DEBUG && prefs(c).getBoolean("local", false) && uri.scheme=="http" && uri.host in listOf("127.0.0.1", "localhost", "::1")
        require((uri.scheme=="https" || local) && !uri.host.isNullOrEmpty() && uri.userInfo==null && uri.query==null && uri.fragment==null && (uri.path.isNullOrEmpty() || uri.path=="/"))
        val auth=state.getJSONObject("session");require(utc(auth.getString("expiresAt"))>System.currentTimeMillis())
        val cookie=auth.getString("value");require(cookie.isNotEmpty() && !cookie.contains('\n') && !cookie.contains('\r'))
        Session(path,state,origin.trimEnd('/'),cookie,key(origin,cookie))
    } catch (_: Exception) { null }
    private fun backgroundFile(s: Session) = File(s.path.parentFile,"todo-background.json")
    private fun background(s: Session): JSONObject? = try { JSONObject(backgroundFile(s).readText()).takeIf { it.optString("sessionKey")==s.key && it.optLong("baseWriteGeneration",0)==s.state.optLong("writeGeneration",0) } } catch (_: Exception) { null }
    private fun latest(s: Session): JSONObject? {
        val main=s.state.optJSONObject("snapshot")?.takeIf { it.optString("origin").trimEnd('/')==s.origin }
        val bg=background(s)
        return if(bg!=null && (main==null || bg.optString("readAt")>main.optString("readAt"))) bg else main
    }
    private fun rows(snapshot: JSONObject?): List<JSONObject> {
        val array=snapshot?.optJSONArray("tasks") ?: return emptyList()
        return (0 until array.length()).map { array.getJSONObject(it) }
    }
    private fun tasksValid(array: JSONArray) {
        val ids=mutableSetOf<Int>()
        for(i in 0 until array.length()) {
            val task=array.getJSONObject(i);require(task.getInt("id")>0 && ids.add(task.getInt("id")))
            for(field in listOf("title","note","project","priority")) require(task.get(field) is String)
            for(field in listOf("done","quick","pinned")) require(task.get(field) in listOf(0,1))
            for(field in listOf("urgent","important")) require(task.isNull(field) || task.get(field) in listOf(0,1))
        }
    }
    fun attach(c: Context, path: String, local: Boolean) = synchronized(lock) {
        val file=File(path).canonicalFile
        require(file.path.startsWith(c.filesDir.canonicalPath+File.separator) && file.name=="todo-state.json")
        if(prefs(c).getString("path",null)!=file.path) clearAccount(c)
        prefs(c).edit().putString("path",file.path).putBoolean("local",BuildConfig.DEBUG && local).commit()
        stateChanged(c)
    }
    private fun cancelAlarm(c: Context,id: Int) {
        c.getSystemService(AlarmManager::class.java).cancel(alarmIntent(c,id,0,"",0))
    }
    private fun clearAccount(c: Context) {
        val p=prefs(c);val old=JSONObject(p.getString("alarms","{}")!!)
        for(id in old.keys()) cancelAlarm(c,id.toInt())
        PlannerReminder.clear(c, p)
        c.getSystemService(NotificationManager::class.java).cancelAll()
        WorkManager.getInstance(c).cancelUniqueWork(PERIODIC);WorkManager.getInstance(c).cancelUniqueWork(ONCE)
        p.edit().remove("activeKey").remove("seen").remove("processed").remove("lastSuccess").remove("lastAttempt").remove("message").remove("sessionInvalid").putString("alarms","{}").putStringSet("sent",emptySet()).commit()
    }
    fun stateChanged(c: Context) = synchronized(lock) {
        val s=session(c);val p=prefs(c)
        if(s==null) { if(p.contains("activeKey")) clearAccount(c);return@synchronized }
        val changed = p.getString("activeKey", null) != s.key
        if (changed) {clearAccount(c);p.edit().putString("activeKey",s.key).commit()}
        if(p.getBoolean("sessionInvalid",false)) return@synchronized
        if (changed) PlannerReminder.bind(c, immediate = true)
        PlannerReminder.restore(c, p, s.origin, s.key, force = false)
        if(p.getBoolean("enabled",false)) {
            val request=PeriodicWorkRequest.Builder(TodoReadWorker::class.java,30,TimeUnit.MINUTES).setInitialDelay(30,TimeUnit.MINUTES).setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()).build()
            WorkManager.getInstance(c).enqueueUniquePeriodicWork(PERIODIC,ExistingPeriodicWorkPolicy.KEEP,request)
        } else {WorkManager.getInstance(c).cancelUniqueWork(PERIODIC);WorkManager.getInstance(c).cancelUniqueWork(ONCE)}
        latest(s)?.let { applySnapshot(c,s,it) }
    }
    fun setOptions(c: Context, options: Map<*,*>) = synchronized(lock) {
        val edit=prefs(c).edit()
        for(name in listOf("enabled","campus","deadline")) (options[name] as? Boolean)?.let {edit.putBoolean(name,it)}
        edit.commit();stateChanged(c);scheduleAlarms(c,session(c),true);signal()
    }
    fun runNow(c: Context) = synchronized(lock) {
        require(prefs(c).getBoolean("enabled",false) && session(c)!=null && !prefs(c).getBoolean("sessionInvalid",false))
        if(prefs(c).getBoolean("running",false)) return@synchronized
        WorkManager.getInstance(c).enqueueUniqueWork(ONCE,ExistingWorkPolicy.REPLACE,OneTimeWorkRequest.Builder(TodoReadWorker::class.java).setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()).build())
    }
    fun notificationsAllowed(c: Context) = (Build.VERSION.SDK_INT<33 || c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED) && c.getSystemService(NotificationManager::class.java).areNotificationsEnabled()
    private fun exact(c: Context) = Build.VERSION.SDK_INT<31 || c.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()
    fun status(c: Context): Map<String,Any?> = synchronized(lock) {
        val p=prefs(c)
        mapOf("enabled" to p.getBoolean("enabled",false),"campus" to p.getBoolean("campus",false),"deadline" to p.getBoolean("deadline",false),"notificationsAllowed" to notificationsAllowed(c),"exactAllowed" to exact(c),"sessionInvalid" to p.getBoolean("sessionInvalid",false),"lastAttempt" to p.getLong("lastAttempt",0),"lastSuccess" to p.getLong("lastSuccess",0),"message" to p.getString("message",null),"running" to p.getBoolean("running",false),"scheduledAlarms" to JSONObject(p.getString("alarms","{}")!!).length(),
            "plannerNextAt" to p.getLong("plannerNextAt", 0L))
    }
    fun readSnapshot(c: Context): Map<String,Any?>? = synchronized(lock) {
        val s=session(c) ?: return@synchronized null
        if(prefs(c).getBoolean("sessionInvalid",false)) return@synchronized null
        background(s)?.let { mapOf("origin" to s.origin,"readAt" to it.getString("readAt"),"tasksJson" to it.getJSONArray("tasks").toString()) }
    }
    private fun applySnapshot(c: Context,s: Session,snapshot: JSONObject) {
        val p=prefs(c);val tasks=rows(snapshot);val marker=snapshot.optString("readAt")
        if(marker!=p.getString("processed",null)) {
            val existing=p.getStringSet("seen",null);val seen=existing?.toMutableSet() ?: mutableSetOf()
            for(task in tasks.filter { !it.isNull("externalId") }) {
                val id=task.getInt("id");val fresh=seen.add(id.toString())
                if(existing!=null && fresh && task.optInt("done")==0 && p.getBoolean("campus",false)) notifyTask(c,s,task,"campus")
            }
            p.edit().putStringSet("seen",seen).putString("processed",marker).commit()
        }
            val active=tasks.filter {it.optInt("done")==0}.map {it.getInt("id")}.toSet()
            for(notification in c.getSystemService(NotificationManager::class.java).activeNotifications) {
                if(notification.tag?.startsWith("due:")==true || notification.tag?.startsWith("campus:")==true) {
                    if(notification.id !in active || (notification.tag?.startsWith("due:")==true && tasks.find {it.optInt("id")==notification.id}?.let {due(it.optString("dueAt"))?.let {at -> at>System.currentTimeMillis()} ?: true}==true)) c.getSystemService(NotificationManager::class.java).cancel(notification.tag,notification.id)
                }
            }
        scheduleAlarms(c,s,false)
    }
    private fun alarmIntent(c: Context,id: Int,at: Long,origin: String,epoch: Long): PendingIntent {
        val intent=Intent(c,TodoReminderReceiver::class.java).setAction("io.github.andyyjf.todo.DEADLINE").setData(Uri.parse("todo://deadline/$id")).putExtra("taskId",id).putExtra("due",at).putExtra("origin",origin).putExtra("epoch",epoch)
        return PendingIntent.getBroadcast(c,id,intent,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    private fun scheduleAlarms(c: Context,s: Session?,force: Boolean) {
        val p=prefs(c);val old=JSONObject(p.getString("alarms","{}")!!);val next=JSONObject();val mode=exact(c)
        if(s!=null && !p.getBoolean("sessionInvalid",false) && p.getBoolean("deadline",false)) {
            val sent=p.getStringSet("sent",emptySet())!!
            for(task in rows(latest(s)).filter {it.optInt("done")==0}) {
                val id=task.getInt("id");val at=due(task.optString("dueAt")) ?: continue
                if("$id:$at" in sent) continue
                if(at<=System.currentTimeMillis()) {
                    if(old.optLong(id.toString(),0)==at) deliverDeadline(c,id,at,s.origin)
                    continue
                }
                next.put(id.toString(),at)
                if(force || old.optLong(id.toString(),0)!=at || p.getBoolean("alarmMode",false)!=mode) {
                    val alarm=c.getSystemService(AlarmManager::class.java);val pending=alarmIntent(c,id,at,s.origin,0)
                    try {if(mode) alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,at,pending) else alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,at,pending)} catch (_: SecurityException) {alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,at,pending)}
                }
            }
        }
        for(id in old.keys()) if(!next.has(id)) cancelAlarm(c,id.toInt())
        p.edit().putString("alarms",next.toString()).putBoolean("alarmMode",mode).commit()
    }
    fun restore(c: Context, foreground: Boolean = false) = synchronized(lock) {
        stateChanged(c)
        val s = session(c)
        scheduleAlarms(c, s, true)
        val p = prefs(c)
        if (s != null && !p.getBoolean("sessionInvalid", false)) {
            PlannerReminder.restore(c, p, s.origin, s.key, force = true)
            PlannerReminder.bind(c, immediate = foreground)
        }
        signal()
    }

    fun applyPlannerSettings(c: Context, origin: String, data: JSONObject) = synchronized(lock) {
        stateChanged(c)
        val s = session(c)
        val p = prefs(c)
        if (s != null && s.origin == origin && !p.getBoolean("sessionInvalid", false)) {
            PlannerReminder.apply(c, p, s.origin, s.key, data)
        }
    }

    fun deliverPlanner(c: Context, at: Long, account: String) = synchronized(lock) {
        val s = session(c)
        val p = prefs(c)
        if (s != null && s.key == account && !p.getBoolean("sessionInvalid", false)) {
            PlannerReminder.deliver(c, p, s.origin, s.key, at)
            signal()
        }
    }

    fun syncPlannerSettings(c: Context): Boolean = synchronized(plannerNetworkLock) {
        val start = synchronized(lock) {
            session(c)?.takeIf { !prefs(c).getBoolean("sessionInvalid", false) }
        } ?: return@synchronized true
        try {
            val connection = URL(start.origin + "/api/planner/settings").openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 12000
            connection.readTimeout = 20000
            connection.setRequestProperty("Cookie", "todo_session=" + start.cookie)
            connection.setRequestProperty("Accept", "application/json")
            val status: Int
            val data: JSONObject?
            try {
                status = connection.responseCode
                data = if (status == 200) JSONObject(connection.inputStream.bufferedReader().use { it.readText() }) else null
            } finally {
                connection.disconnect()
            }
            synchronized(lock) apply@{
                val current = session(c)
                val p = prefs(c)
                if (current?.key != start.key || current.path != start.path || p.getBoolean("sessionInvalid", false)) {
                    return@apply true
                }
                when (status) {
                    200 -> PlannerReminder.apply(c, p, current.origin, current.key, checkNotNull(data))
                    401 -> {
                        clearAccount(c)
                        p.edit().putString("activeKey", start.key).putBoolean("sessionInvalid", true)
                            .putString("message", "会话已失效，请打开 App 重新登录").commit()
                    }
                    404 -> Unit
                    else -> return@apply false
                }
                signal()
                true
            }
        } catch (_: Exception) {
            false
        }
    }
    fun deliverDeadline(c: Context,id: Int,at: Long,origin: String) = synchronized(lock) {
        val s=session(c) ?: return@synchronized;val p=prefs(c)
        if(s.origin!=origin || p.getBoolean("sessionInvalid",false) || !p.getBoolean("deadline",false)) return@synchronized
        val task=rows(latest(s)).find {it.optInt("id")==id && it.optInt("done")==0 && due(it.optString("dueAt"))==at} ?: return@synchronized
        val sent=p.getStringSet("sent",emptySet())!!.toMutableSet();if(!sent.add("$id:$at")) return@synchronized
        notifyTask(c,s,task,"due");val alarms=JSONObject(p.getString("alarms","{}")!!);alarms.remove(id.toString());p.edit().putStringSet("sent",sent).putString("alarms",alarms.toString()).commit()
    }
    private fun channels(c: Context) {
        if(Build.VERSION.SDK_INT>=26) for((id,title) in listOf("campus" to "新校园任务","due" to "任务到期","session" to "会话状态")) c.getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel("todo_$id",title,NotificationManager.IMPORTANCE_DEFAULT))
    }
    private fun notifyTask(c: Context,s: Session,task: JSONObject,kind: String) {
        if(!notificationsAllowed(c)) return
        channels(c);val id=task.getInt("id")
        val intent=Intent(c,MainActivity::class.java).setAction(Intent.ACTION_VIEW).setData(Uri.parse("todo://task/$id")).putExtra("taskId",id).putExtra("todoOrigin",s.origin).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pending=PendingIntent.getActivity(c,id,intent,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        @Suppress("DEPRECATION") val builder=if(Build.VERSION.SDK_INT>=26) Notification.Builder(c,"todo_$kind") else Notification.Builder(c)
        val notification=builder.setSmallIcon(R.drawable.ic_todo_notification).setContentTitle(task.getString("title")).setContentText(if(kind=="due") "任务已到截止时间，点按查看" else "收到新的校园任务，点按查看").setContentIntent(pending).setAutoCancel(true).setVisibility(Notification.VISIBILITY_PRIVATE).build()
        c.getSystemService(NotificationManager::class.java).notify("$kind:$id",id,notification)
    }
    fun perform(c: Context): Boolean = synchronized(networkLock) {
        val p=prefs(c)
        val start=synchronized(lock) {val s=session(c);if(s==null) stateChanged(c);if(s==null || !p.getBoolean("enabled",false) || p.getBoolean("sessionInvalid",false)) null else s} ?: return@synchronized true
        p.edit().putLong("lastAttempt",System.currentTimeMillis()).putBoolean("running",true).putString("message","正在从 Todo 服务读取").commit();signal()
        try {
            val connection=URL(start.origin+"/api/tasks?view=all").openConnection() as HttpURLConnection
            connection.instanceFollowRedirects=false;connection.connectTimeout=12000;connection.readTimeout=20000;connection.setRequestProperty("Cookie","todo_session="+start.cookie);connection.setRequestProperty("Accept","application/json")
            val code: Int;val data: JSONArray?
            try {code=connection.responseCode;data=if(code==200) JSONObject(connection.inputStream.bufferedReader().use {it.readText()}).getJSONArray("tasks") else null} finally {connection.disconnect()}
            synchronized(lock) {
                val now=session(c)
                if(now==null || now.key!=start.key || now.path!=start.path || now.state.optLong("revision")!=start.state.optLong("revision") || !p.getBoolean("enabled",false)) return@synchronized
                if(code==401) {
                    clearAccount(c);p.edit().putString("activeKey",start.key).putBoolean("sessionInvalid",true).putString("message","会话已失效，请打开 App 重新登录").commit()
                    if(notificationsAllowed(c)) {channels(c);@Suppress("DEPRECATION") val b=if(Build.VERSION.SDK_INT>=26) Notification.Builder(c,"todo_session") else Notification.Builder(c);val open=PendingIntent.getActivity(c,0,Intent(c,MainActivity::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE);c.getSystemService(NotificationManager::class.java).notify(0,b.setSmallIcon(R.drawable.ic_todo_notification).setContentTitle("Todo 需要重新登录").setContentIntent(open).setAutoCancel(true).build())}
                    return@synchronized
                }
                require(code==200 && data!=null);tasksValid(data)
                val stamp=SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",Locale.ROOT).apply {timeZone=TimeZone.getTimeZone("UTC")}.format(Date())
                val snapshot=JSONObject().put("origin",start.origin).put("sessionKey",start.key).put("readAt",stamp).put("baseWriteGeneration",start.state.optLong("writeGeneration",0)).put("tasks",data)
                val file=backgroundFile(start);val temp=File(file.path+".tmp");temp.writeText(snapshot.toString());check(temp.renameTo(file))
                p.edit().putLong("lastSuccess",System.currentTimeMillis()).putString("message","后台读取完成：${data.length()} 条任务").commit();applySnapshot(c,now,snapshot)
            }
            true
        } catch (failure: Exception) {if(BuildConfig.DEBUG) android.util.Log.w("TodoBackground",failure.javaClass.simpleName+" at "+failure.stackTrace.firstOrNull()?.toString());synchronized(lock) {if(session(c)?.key==start.key) p.edit().putString("message","后台读取失败，保留最近快照；系统稍后重试").commit()};false} finally {p.edit().putBoolean("running",false).commit();signal()}
    }
}

class TodoReadWorker(context: Context,params: WorkerParameters): Worker(context,params) {
    override fun doWork(): Result = if(TodoBackground.perform(applicationContext)) Result.success() else Result.retry()
}
class TodoReminderReceiver: BroadcastReceiver() {
    override fun onReceive(context: Context,intent: Intent) {
        val pending = goAsync()
        TodoBackground.io.execute {
            try {
                when (intent.action) {
                    "io.github.andyyjf.todo.DEADLINE" -> TodoBackground.deliverDeadline(
                        context, intent.getIntExtra("taskId", 0), intent.getLongExtra("due", 0),
                        intent.getStringExtra("origin").orEmpty(),
                    )
                    PlannerReminder.ALARM -> TodoBackground.deliverPlanner(
                        context, intent.getLongExtra("plannerAt", 0), intent.getStringExtra("plannerAccount").orEmpty(),
                    )
                    else -> TodoBackground.restore(context)
                }
            } finally {
                pending.finish()
            }
        }
    }
}
