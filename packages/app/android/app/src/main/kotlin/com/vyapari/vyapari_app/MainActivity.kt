package com.vyapari.vyapari_app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null
    private var multicastUsers = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vyapari/settings")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openHotspot" -> {
                        openHotspotSettings()
                        result.success(null)
                    }
                    "multicastLock" -> {
                        setMulticast(call.arguments as? Boolean ?: false)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Android drops Wi-Fi broadcast/multicast (UDP discovery, mDNS) unless an
    // app holds a multicast lock. Hosting and "Join nearby" each ask for it;
    // it is released when neither needs it.
    private fun setMulticast(on: Boolean) {
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        if (on) {
            multicastUsers++
            if (multicastLock == null) {
                multicastLock = wifi.createMulticastLock("vyapari-discovery").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
        } else {
            multicastUsers = maxOf(0, multicastUsers - 1)
            if (multicastUsers == 0) {
                multicastLock?.let { if (it.isHeld) it.release() }
                multicastLock = null
            }
        }
    }

    override fun onDestroy() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
        super.onDestroy()
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
