package com.varad.bolo

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bolo").setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences("bolo", MODE_PRIVATE)
            when (call.method) {
                "status" -> result.success(mapOf(
                    "mic" to (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED),
                    "service" to (Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
                        ?.contains("$packageName/") == true),
                    "lang" to prefs.getString("lang", "unknown"),
                    "mode" to prefs.getString("mode", "transcribe"),
                ))
                "askMic" -> { requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 1); result.success(null) }
                "openAccessibility" -> { startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)); result.success(null) }
                "set" -> { prefs.edit().putString(call.argument("key"), call.argument<String>("value")).apply(); result.success(null) }
                "history" -> result.success(History.read(this).toString())
                "clearHistory" -> { History.clear(this); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
}
