package com.example.tracex

import android.app.ActivityManager
import android.content.Context
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

    override fun onAttachedToEngine(
        flutterPluginBinding: FlutterPlugin.FlutterPluginBinding
    ) {
        context = flutterPluginBinding.applicationContext

        channel = MethodChannel(
            flutterPluginBinding.binaryMessenger,
            CHANNEL_NAME
        )

        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {

            "getMemoryInfo" -> {
                getMemoryInfo(result)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

   private fun getMemoryInfo(result: Result) {
    try {
        val activityManager =
            context.getSystemService(
                Context.ACTIVITY_SERVICE
            ) as ActivityManager

        val memoryInfo = ActivityManager.MemoryInfo()

        activityManager.getMemoryInfo(memoryInfo)

        val totalRamMb =
            memoryInfo.totalMem / (1024 * 1024)

        val freeRamMb =
            memoryInfo.availMem / (1024 * 1024)

        val isLowMemory =
            memoryInfo.lowMemory

        result.success(
            mapOf(
                "totalRamMb" to totalRamMb,
                "freeRamMb" to freeRamMb,
                "isLowMemory" to isLowMemory
            )
        )
    } catch (e: Exception) {
        result.error(
            "MEMORY_ERROR",
            "Failed to get memory information",
            e.message
        )
    }
}

    override fun onDetachedFromEngine(
        binding: FlutterPlugin.FlutterPluginBinding
    ) {
        channel.setMethodCallHandler(null)
    }
}
