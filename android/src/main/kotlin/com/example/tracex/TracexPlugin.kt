package com.example.tracex

import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class TracexPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    companion object {
        private const val CHANNEL_NAME = "tracex/environment"
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getEnvironmentInfo" -> getEnvironmentInfo(result)
            "getMemoryInfo" -> getMemoryInfo(result) // للأمان والتوافق الرجعي
            else -> result.notImplemented()
        }
    }

    private fun getEnvironmentInfo(result: Result) {
        try {
            // 1. Memory Info
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memoryInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memoryInfo)
            val totalRamMb = (memoryInfo.totalMem / (1024 * 1024)).toInt()
            val freeRamMb = (memoryInfo.availMem / (1024 * 1024)).toInt()
            val isLowMemory = memoryInfo.lowMemory

            // 2. Battery Info
           val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
val rawBattery = batteryManager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
val batteryLevel = if (rawBattery in 0..100) rawBattery else -1 
            // 3. Package Info
            var appVersion = "Unknown"
            try {
                val pInfo: PackageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    context.packageManager.getPackageInfo(context.packageName, PackageManager.PackageInfoFlags.of(0))
                } else {
                    @Suppress("DEPRECATION")
                    context.packageManager.getPackageInfo(context.packageName, 0)
                }
                val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    pInfo.longVersionCode
                } else {
                    @Suppress("DEPRECATION")
                    pInfo.versionCode.toLong()
                }
                appVersion = "${pInfo.versionName}+$versionCode"
            } catch (_: Exception) {}

            // 4. Device Info
            val deviceModel = Build.MODEL
            val osVersion = Build.VERSION.RELEASE
            val isPhysicalDevice = !Build.FINGERPRINT.startsWith("generic") &&
                    !Build.FINGERPRINT.startsWith("unknown") &&
                    !Build.MODEL.contains("google_sdk") &&
                    !Build.MODEL.contains("Emulator") &&
                    !Build.MODEL.contains("Android SDK built for x86")

            result.success(
                mapOf(
                    "totalRamMb" to totalRamMb,
                    "freeRamMb" to freeRamMb,
                    "isLowMemory" to isLowMemory,
                    "batteryLevel" to batteryLevel,
                    "appVersion" to appVersion,
                    "deviceModel" to deviceModel,
                    "osVersion" to osVersion,
                    "isPhysicalDevice" to isPhysicalDevice
                )
            )
        } catch (e: Exception) {
            result.error("ENV_ERROR", "Failed to collect environment info", e.message)
        }
    }

    private fun getMemoryInfo(result: Result) {
        try {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memoryInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memoryInfo)
            result.success(
                mapOf(
                    "totalRamMb" to (memoryInfo.totalMem / (1024 * 1024)).toInt(),
                    "freeRamMb" to (memoryInfo.availMem / (1024 * 1024)).toInt(),
                    "isLowMemory" to memoryInfo.lowMemory
                )
            )
        } catch (e: Exception) {
            result.error("MEMORY_ERROR", "Failed to get memory information", e.message)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}