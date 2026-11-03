package com.vyapari.vyapari_app

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vyapari/settings")
            .setMethodCallHandler { call, result ->
                if (call.method == "openHotspot") {
                    openHotspotSettings()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    // Apps cannot switch the hotspot on themselves on modern Android, so we
    // open the tethering screen (falling back to wireless settings).
    private fun openHotspotSettings() {
        val tether = Intent(Intent.ACTION_MAIN).apply {
            component = ComponentName("com.android.settings", "com.android.settings.TetherSettings")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(tether)
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}
