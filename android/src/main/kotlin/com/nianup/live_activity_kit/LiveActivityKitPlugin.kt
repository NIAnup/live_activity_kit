package com.nianup.live_activity_kit

import android.app.Activity
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class LiveActivityKitPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var store: SharedPreferences
    private var applicationContext: Context? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var eventSink: EventChannel.EventSink? = null
    private val pendingEvents = ArrayDeque<Map<String, Any?>>()
    private var pendingShow: Pair<Map<String, Any?>, MethodChannel.Result>? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        applicationContext = context
        val m = manager ?: LiveActivityManager(context).also { manager = it }
        m.onEvent = { send(it) }
        store = context.getSharedPreferences(STORE_PREFS, android.content.Context.MODE_PRIVATE)

        methodChannel = MethodChannel(binding.binaryMessenger, "live_activity_kit")
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "live_activity_kit/events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val mapped = (call.arguments as? Map<*, *>)
            ?.entries
            ?.associate { it.key.toString() to it.value }
            ?: emptyMap()
        try {
            when (call.method) {
                "checkSupport" -> result.success(requireManager().support())
                "show" -> show(mapped, result)
                "update" -> {
                    requireManager().update(mapped)
                    result.success(null)
                }
                "end" -> {
                    requireManager().end(mapped)
                    result.success(null)
                }
                "endAll" -> {
                    requireManager().endAll(mapped["immediate"] as? Boolean ?: false)
                    result.success(null)
                }
                "activities" -> result.success(requireManager().all())
                "activity" -> {
                    val id = mapped["id"] as? String
                    if (id == null) {
                        result.error("invalid_argument", "Missing id.", null)
                    } else {
                        result.success(requireManager().activity(id))
                    }
                }
                "pushToStartToken" -> result.success(null)
                "storeWrite" -> writeStore(mapped, result)
                "storeRead" -> {
                    val key = mapped["key"] as? String
                    if (key == null) {
                        result.error("invalid_argument", "storeRead needs a key.", null)
                    } else {
                        result.success(store.getString(key, null))
                    }
                }
                else -> result.notImplemented()
            }
        } catch (error: LiveActivityManager.Failure) {
            result.error(error.code, error.message, null)
        } catch (error: Throwable) {
            result.error("unknown", error.message ?: error.toString(), null)
        }
    }

    private fun show(args: Map<String, Any?>, result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        if (Build.VERSION.SDK_INT >= 33 &&
            activity != null &&
            !LiveActivityManager.hasNotificationPermission(activity)
        ) {
            if (pendingShow != null) {
                result.error("invalid_argument", "A permission request is already in flight.", null)
                return
            }
            pendingShow = args to result
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                PERMISSION_REQUEST,
            )
            return
        }
        result.success(requireManager().request(args))
    }

    private fun writeStore(mapped: Map<String, Any?>, result: MethodChannel.Result) {
        val key = mapped["key"] as? String
        val value = mapped["value"] as? String
        if (key == null || value == null) {
            result.error("invalid_argument", "storeWrite needs key and value.", null)
            return
        }
        if (value.isEmpty()) store.edit().remove(key).apply()
        else store.edit().putString(key, value).apply()
        send(mapOf("type" to "store", "key" to key))
        result.success(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        while (pendingEvents.isNotEmpty()) {
            events?.success(pendingEvents.removeFirst())
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val pending = pendingShow ?: return true
        pendingShow = null
        val (args, result) = pending
        val activity: Activity? = activityBinding?.activity
        if (activity != null && LiveActivityManager.hasNotificationPermission(activity)) {
            try {
                result.success(requireManager().request(args))
            } catch (error: LiveActivityManager.Failure) {
                result.error(error.code, error.message, null)
            } catch (error: Exception) {
                result.error("unknown", error.message, null)
            }
        } else {
            result.error(
                "disabled",
                "Notification permission is off for this app. Enable it in Settings.",
                null,
            )
        }
        return true
    }

    private fun send(event: Map<String, Any?>) {
        val sink = eventSink
        if (sink != null) {
            sink.success(event)
        } else {
            if (pendingEvents.size >= 32) pendingEvents.removeFirst()
            pendingEvents.addLast(event)
        }
    }

    private fun requireManager(): LiveActivityManager {
        var m = manager
        if (m == null) {
            val ctx = applicationContext ?: activityBinding?.activity?.applicationContext
            if (ctx != null) {
                m = LiveActivityManager(ctx).apply {
                    onEvent = { send(it) }
                }
                manager = m
            }
        }
        return m ?: throw LiveActivityManager.Failure.Unsupported
    }

    companion object {
        private const val STORE_PREFS = "live_activity_kit_store"
        private const val PERMISSION_REQUEST = 0x4A1C

        @Volatile
        internal var manager: LiveActivityManager? = null

        internal val managerOrNull: LiveActivityManager?
            get() = manager
    }
}
