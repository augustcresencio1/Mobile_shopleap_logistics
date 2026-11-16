package com.example.mobileshopleap_logistic_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build

class MainActivity : FlutterActivity() {
    private var notificationResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "shopleap/rider_tracking")
            .setMethodCallHandler { call, result ->
                if (call.method != "requestNotificationPermission") {
                    result.notImplemented()
                } else if (Build.VERSION.SDK_INT < 33 ||
                    checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                    result.success(true)
                } else if (notificationResult != null) {
                    result.error("permission_pending", "A permission request is already open.", null)
                } else {
                    notificationResult = result
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 12061)
                }
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 12061) {
            notificationResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            notificationResult = null
        }
    }
}
