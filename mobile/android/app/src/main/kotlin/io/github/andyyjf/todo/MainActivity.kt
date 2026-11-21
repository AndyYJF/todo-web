package io.github.andyyjf.todo

import org.json.JSONObject
import android.app.Activity
import android.content.ActivityNotFoundException
import android.provider.OpenableColumns
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import android.os.Build
import android.os.Bundle
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private var bridge: MethodChannel? = null
    private var plannerFileResult: MethodChannel.Result? = null
    private val plannerFileRequest = 903
    private val maxPlannerFileBytes = 1024 * 1024

    @Suppress("DEPRECATION")
    private fun pickPlannerFile(result: MethodChannel.Result) {
        if (plannerFileResult != null) {
            result.error("busy", "正在选择课表文件", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
        try {
            plannerFileResult = result
            startActivityForResult(intent, plannerFileRequest)
        } catch (_: ActivityNotFoundException) {
            plannerFileResult = null
            result.error("unavailable", "未找到系统文件选择器，可以粘贴课表内容", null)
        }
    }

    @Deprecated("Uses the FlutterActivity activity result callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != plannerFileRequest) return
        val result = plannerFileResult ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            plannerFileResult = null
            result.success(null)
            return
        }
        Thread {
            try {
                val name = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                    ?.use { if (it.moveToFirst()) it.getString(0) else null }
                    ?: uri.lastPathSegment.orEmpty()
                require(name.endsWith(".ics", ignoreCase = true)) { "请选择 .ics 课表文件" }
                val raw = contentResolver.openInputStream(uri)?.use { stream ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val size = stream.read(buffer)
                        if (size == -1) break
                        require(output.size() + size <= maxPlannerFileBytes) { "课表文件不能超过 1 MiB" }
                        output.write(buffer, 0, size)
                    }
                    output.toByteArray()
                } ?: error("Cannot open calendar")
                val text = Charsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(raw)).toString()
                runOnUiThread {
                    plannerFileResult = null
                    result.success(mapOf("name" to name, "text" to text))
                }
            } catch (error: Exception) {
                val message = if (error is IllegalArgumentException) error.message else "无法读取 UTF-8 课表文件"
                runOnUiThread {
                    plannerFileResult = null
                    result.error("ics", message, null)
                }
            }
        }.start()
    }

    private var pendingTap: Map<String,Any>? = null
    private var permissionResult: MethodChannel.Result? = null
    private fun tap(intent: Intent?) {
        val origin = intent?.getStringExtra("todoOrigin") ?: return
        val date = intent.getStringExtra("plannerDate")
        val id = intent.getIntExtra("taskId", 0)
        pendingTap = when {
            intent.action == PlannerReminder.OPEN && date != null &&
                date.matches(Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}")) &&
                intent.data == Uri.parse("todo://planner/$date") -> mapOf("date" to date, "origin" to origin)
            id > 0 -> mapOf("id" to id, "origin" to origin)
            else -> return
        }
        bridge?.invokeMethod("notificationTap", null)
    }
    override fun onCreate(savedInstanceState: Bundle?) {super.onCreate(savedInstanceState);tap(intent)}
    override fun onNewIntent(intent: Intent) {super.onNewIntent(intent);setIntent(intent);tap(intent)}
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "todo/planner_files")
            .setMethodCallHandler { call, result ->
                if (call.method == "pickIcs") pickPlannerFile(result) else result.notImplemented()
            }
        val channel=MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"todo/background")
        bridge=channel;TodoBackground.channel=channel
        channel.setMethodCallHandler { call,result ->
            when(call.method) {
                "consumeTap" -> {result.success(pendingTap);pendingTap=null}
                "requestNotifications" -> {
                    if(Build.VERSION.SDK_INT>=33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)!=android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        if(permissionResult!=null) result.error("busy","正在等待系统授权",null) else {permissionResult=result;requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),902)}
                    } else result.success(TodoBackground.notificationsAllowed(this))
                }
                "openNotificationSettings" -> {startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,packageName));result.success(null)}
                "openExactSettings" -> {if(Build.VERSION.SDK_INT>=31) startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,Uri.parse("package:$packageName")));result.success(null)}
                "openBatterySettings" -> {startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:$packageName")));result.success(null)}
                else -> TodoBackground.io.execute {
                    try {
                        val value: Any? = when(call.method) {
                            "attach" -> {TodoBackground.attach(applicationContext,call.argument<String>("path")!!,call.argument<Boolean>("local")==true);TodoBackground.status(applicationContext)}
                            "stateChanged" -> {TodoBackground.stateChanged(applicationContext);TodoBackground.status(applicationContext)}
                            "status" -> TodoBackground.status(applicationContext)
                            "plannerSettings" -> {
                                val data = JSONObject(call.arguments as Map<*, *>)
                                TodoBackground.applyPlannerSettings(applicationContext, data.getString("origin"), data)
                                TodoBackground.status(applicationContext)
                            }
                            "options" -> {TodoBackground.setOptions(applicationContext,call.arguments as Map<*,*>);TodoBackground.status(applicationContext)}
                            "runNow" -> {TodoBackground.runNow(applicationContext);null}
                            "snapshot" -> TodoBackground.readSnapshot(applicationContext)
                            else -> throw IllegalArgumentException()
                        }
                        runOnUiThread {result.success(value)}
                    } catch (_: Exception) {runOnUiThread {result.error("background","后台任务暂时无法更新",null)}}
                }
            }
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int,permissions: Array<out String>,grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode,permissions,grantResults)
        if (requestCode == 902) {
            permissionResult?.success(TodoBackground.notificationsAllowed(this))
            permissionResult = null
            TodoBackground.io.execute { TodoBackground.restore(applicationContext) }
        }
    }
    override fun onDestroy() {if(TodoBackground.channel===bridge) TodoBackground.channel=null;super.onDestroy()}

    override fun onResume() {
        super.onResume()
        TodoBackground.io.execute { TodoBackground.restore(applicationContext, foreground = true) }
        @Suppress("DEPRECATION")
        val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else windowManager.defaultDisplay
        val currentMode = currentDisplay?.mode ?: return
        val preferred = currentDisplay.supportedModes
            .filter { it.physicalWidth == currentMode.physicalWidth && it.physicalHeight == currentMode.physicalHeight }
            .maxByOrNull { it.refreshRate } ?: return
        window.attributes = window.attributes.apply { preferredDisplayModeId = preferred.modeId }
    }
}
