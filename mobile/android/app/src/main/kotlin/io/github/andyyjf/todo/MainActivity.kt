package io.github.andyyjf.todo

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
    private var pendingTap: Map<String,Any>? = null
    private var permissionResult: MethodChannel.Result? = null
    private fun tap(intent: Intent?) {
        val id=intent?.getIntExtra("taskId",0) ?: 0
        val origin=intent?.getStringExtra("todoOrigin")
        if(id>0 && origin!=null) {pendingTap=mapOf("id" to id,"origin" to origin);bridge?.invokeMethod("notificationTap",null)}
    }
    override fun onCreate(savedInstanceState: Bundle?) {super.onCreate(savedInstanceState);tap(intent)}
    override fun onNewIntent(intent: Intent) {super.onNewIntent(intent);setIntent(intent);tap(intent)}
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
        if(requestCode==902) {permissionResult?.success(TodoBackground.notificationsAllowed(this));permissionResult=null}
    }
    override fun onDestroy() {if(TodoBackground.channel===bridge) TodoBackground.channel=null;super.onDestroy()}

    override fun onResume() {
        super.onResume()
        TodoBackground.io.execute { TodoBackground.restore(applicationContext) }
        @Suppress("DEPRECATION")
        val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else windowManager.defaultDisplay
        val currentMode = currentDisplay?.mode ?: return
        val preferred = currentDisplay.supportedModes
            .filter { it.physicalWidth == currentMode.physicalWidth && it.physicalHeight == currentMode.physicalHeight }
            .maxByOrNull { it.refreshRate } ?: return
        window.attributes = window.attributes.apply { preferredDisplayModeId = preferred.modeId }
    }
}
