package com.nianup.live_activity_kit

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import org.json.JSONObject

internal class LiveActivityManager(private val context: Context) {

    var onEvent: ((Map<String, Any?>) -> Unit)? = null

    private val notifications: NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private val running = LinkedHashMap<String, ActivityRecord>()
    private val handler = Handler(Looper.getMainLooper())
    private val endRunnables = HashMap<String, Runnable>()

    data class ActivityRecord(
        val id: String,
        var layout: String,
        var state: String,
    )

    fun support(): Map<String, Any?> {
        val sdk = Build.VERSION.SDK_INT
        val notificationsAllowed = NotificationManagerCompat.from(context).areNotificationsEnabled()
        val promoted = if (sdk >= 36) canPostPromotedNotifications() else false
        return mapOf(
            "isSupported" to (sdk >= 26),
            "areActivitiesEnabled" to notificationsAllowed,
            "supportsDynamicIsland" to false,
            "supportsLiveUpdates" to (sdk >= 36 && promoted),
            "systemVersion" to "Android $sdk",
        )
    }

    fun request(args: Map<String, Any?>): Map<String, Any?> {
        ensureReady()
        val id = requireId(args)
        val layout = args["layout"] as? String
            ?: throw Failure.InvalidArgument("Missing layout.")
        cancelScheduledEnd(id)
        running[id] = ActivityRecord(id, layout, "active")
        post(id, layout, args["alert"] as? Map<*, *>, ongoing = true)
        emitState(id, "active")
        return handle(id)
    }

    fun update(args: Map<String, Any?>) {
        ensureReady()
        val id = requireId(args)
        val record = running[id]
        if (record == null) {
            request(args)
            return
        }
        val layout = args["layout"] as? String ?: record.layout
        record.layout = layout
        record.state = "active"
        post(id, layout, args["alert"] as? Map<*, *>, ongoing = true)
        emitState(id, "active")
    }

    fun end(args: Map<String, Any?>) {
        val id = requireId(args)
        val record = running[id] ?: return
        val layout = args["layout"] as? String ?: record.layout
        record.layout = layout
        record.state = "ended"
        val policy = args["policy"] as? Map<*, *>
        val dismissal = policy?.get("dismissal")?.toString() ?: "standard"
        val dismissAt = (policy?.get("dismissAt") as? Number)?.toDouble()
        when (dismissal) {
            "immediate" -> {
                cancel(id)
                running.remove(id)
                emitState(id, "dismissed")
            }
            "after" -> {
                post(id, layout, alert = null, ongoing = false)
                emitState(id, "ended")
                val delayMs = if (dismissAt == null) {
                    5 * 60 * 1000L
                } else {
                    (dismissAt * 1000.0 - System.currentTimeMillis()).toLong().coerceAtLeast(0L)
                }
                scheduleEnd(id, delayMs)
            }
            else -> {
                post(id, layout, alert = null, ongoing = false)
                emitState(id, "ended")
            }
        }
    }

    fun endAll(immediate: Boolean) {
        val ids = running.keys.toList()
        for (id in ids) {
            if (immediate) {
                cancel(id)
                running.remove(id)
                emitState(id, "dismissed")
            } else {
                val record = running[id] ?: continue
                record.state = "ended"
                post(id, record.layout, alert = null, ongoing = false)
                emitState(id, "ended")
            }
        }
    }

    fun all(): List<Map<String, Any?>> = running.values.map { handle(it.id) }

    fun activity(id: String): Map<String, Any?>? =
        if (running.containsKey(id)) handle(id) else null

    fun onUserDismissed(id: String) {
        if (running.remove(id) != null) {
            cancelScheduledEnd(id)
            emitState(id, "dismissed")
        }
    }

    fun onTapped(id: String, url: String?) {
        val link = url?.takeIf { it.isNotEmpty() } ?: deepLinkOf(id)
        cancel(id)
        running.remove(id)
        if (!link.isNullOrEmpty()) {
            onEvent?.invoke(mapOf("type" to "deepLink", "url" to link))
        }
        emitState(id, "dismissed")
    }

    private fun deepLinkOf(id: String): String? {
        val layout = running[id]?.layout ?: return null
        return try {
            JSONObject(layout).optString("deepLink", null)?.takeIf { it.isNotEmpty() }
        } catch (_: Exception) {
            null
        }
    }

    private fun handle(id: String): Map<String, Any?> {
        val record = running[id]!!
        return mapOf(
            "id" to id,
            "activityId" to id,
            "state" to record.state,
            "pushToken" to null,
        )
    }

    private fun ensureReady() {
        if (Build.VERSION.SDK_INT < 26) {
            throw Failure.Unsupported
        }
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            throw Failure.Disabled
        }
        ensureChannel()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        val existing = notifications.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.live_activity_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = context.getString(R.string.live_activity_channel_description)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setShowBadge(true)
            enableVibration(true)
            enableLights(true)
        }
        notifications.createNotificationChannel(channel)
    }

    private fun post(
        id: String,
        layout: String,
        alert: Map<*, *>?,
        ongoing: Boolean,
    ) {
        val model = LayoutFlattener.flatten(layout)
        val isApi36LiveUpdate = Build.VERSION.SDK_INT >= 36 && ongoing

        val smallIconRes = context.applicationInfo.icon.takeIf { it != 0 } ?: R.drawable.ic_live_activity

        val builder = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(smallIconRes)
            .setContentTitle(model.title)
            .setOngoing(ongoing)
            .setShowWhen(false)
            .setOnlyAlertOnce(alert == null)
            .setAutoCancel(!ongoing)
            .setCategory(Notification.CATEGORY_CALL)
            .setPriority(Notification.PRIORITY_MAX)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(pending(id, LiveActivityActionReceiver.ACTION_TAP, model.deepLink))
            .setDeleteIntent(pending(id, LiveActivityActionReceiver.ACTION_DISMISS, null))

        if (model.iconBitmap != null) {
            builder.setLargeIcon(model.iconBitmap)
        }

        if (model.badgeText != null) {
            builder.setSubText(model.badgeText)
        }

        if (isApi36LiveUpdate) {
            val text = when {
                !model.subtitle.isNullOrBlank() && model.body.isNotBlank() -> "${model.subtitle} · ${model.body}"
                !model.subtitle.isNullOrBlank() -> model.subtitle
                else -> model.body.ifBlank { null }
            }
            builder.setContentText(text)
            val fullBody = listOfNotNull(model.subtitle?.takeIf { it.isNotBlank() }, model.body.takeIf { it.isNotBlank() }).joinToString("\n")
            if (model.progress == null && fullBody.isNotBlank()) {
                builder.setStyle(Notification.BigTextStyle().bigText(fullBody).setBigContentTitle(model.title))
            }
            applyLiveUpdates(builder, model, ongoing)
        } else {
            val content = buildRemoteViews(model)
            builder.setContentText(model.body.ifBlank { null })
                .setCustomContentView(content)
                .setCustomBigContentView(content)
                .setStyle(Notification.DecoratedCustomViewStyle())
            model.tintArgb?.let { builder.setColor(it).setColorized(true) }
        }

        if (alert != null) {
            builder.setContentTitle(alert["title"]?.toString() ?: model.title)
            builder.setContentText(alert["body"]?.toString() ?: model.body)
            builder.setDefaults(Notification.DEFAULT_ALL)
            builder.setPriority(Notification.PRIORITY_MAX)
        }

        notifications.notify(notifyId(id), builder.build())
    }

    private fun canPostPromotedNotifications(): Boolean {
        return try {
            val method = notifications.javaClass.getMethod("canPostPromotedNotifications")
            method.invoke(notifications) as? Boolean ?: false
        } catch (_: Throwable) {
            false
        }
    }

    private fun applyLiveUpdates(
        builder: Notification.Builder,
        model: LayoutFlattener.Model,
        ongoing: Boolean,
    ) {
        if (!ongoing || Build.VERSION.SDK_INT < 36) return
        try {
            val promoteMethod = builder.javaClass.methods.firstOrNull { it.name == "setRequestPromotedOngoing" }
            promoteMethod?.invoke(builder, true)

            val chipText = (model.badgeText ?: model.title).take(7)
            try {
                val shortTextMethod = builder.javaClass.methods.firstOrNull { it.name == "setShortCriticalText" }
                shortTextMethod?.invoke(builder, chipText)
            } catch (_: Throwable) {}

            val progress = model.progress
            if (progress != null) {
                val pct = (progress.coerceIn(0.0, 1.0) * 100).toInt()
                val styleClass = Class.forName("android.app.Notification\$ProgressStyle")
                val style = styleClass.getDeclaredConstructor().newInstance()
                styleClass.getMethod("setStyledByProgress", java.lang.Boolean.TYPE)
                    .invoke(style, true)
                styleClass.getMethod("setProgress", Integer.TYPE).invoke(style, pct)
                val segmentClass = Class.forName("android.app.Notification\$ProgressStyle\$Segment")
                val segment = segmentClass.getConstructor(Integer.TYPE).newInstance(100)
                styleClass.getMethod("setProgressSegments", MutableList::class.java)
                    .invoke(style, listOf(segment))
                builder.setStyle(style as Notification.Style)
            }
        } catch (_: Throwable) {
            // compileSdk / runtime may not have Live Updates yet.
        }
    }

    private fun buildRemoteViews(model: LayoutFlattener.Model): RemoteViews {
        val pkg = context.resources.getResourcePackageName(R.layout.live_activity_notification)
        val views = RemoteViews(pkg, R.layout.live_activity_notification)
        views.setTextViewText(R.id.la_title, model.title)

        if (model.iconBitmap != null) {
            views.setViewVisibility(R.id.la_icon, View.VISIBLE)
            views.setImageViewBitmap(R.id.la_icon, model.iconBitmap)
        } else {
            views.setViewVisibility(R.id.la_icon, View.GONE)
        }

        if (model.subtitle.isNullOrBlank()) {
            views.setViewVisibility(R.id.la_subtitle, View.GONE)
        } else {
            views.setViewVisibility(R.id.la_subtitle, View.VISIBLE)
            views.setTextViewText(R.id.la_subtitle, model.subtitle)
        }

        if (model.body.isBlank()) {
            views.setViewVisibility(R.id.la_body, View.GONE)
        } else {
            views.setViewVisibility(R.id.la_body, View.VISIBLE)
            views.setTextViewText(R.id.la_body, model.body)
        }

        if (model.badgeText.isNullOrBlank()) {
            views.setViewVisibility(R.id.la_badge, View.GONE)
        } else {
            views.setViewVisibility(R.id.la_badge, View.VISIBLE)
            views.setTextViewText(R.id.la_badge, model.badgeText)
            model.badgeColorArgb?.let {
                views.setInt(R.id.la_badge, "setBackgroundColor", it)
            }
        }

        val until = model.countdownUntilEpochSec
        if (until != null && model.countdownStyle != "time") {
            views.setViewVisibility(R.id.la_chrono, View.VISIBLE)
            val untilMillis = (until * 1000.0).toLong()
            val now = System.currentTimeMillis()
            val countDown = untilMillis > now
            val base = if (countDown) {
                SystemClock.elapsedRealtime() + (untilMillis - now)
            } else {
                SystemClock.elapsedRealtime() - (now - untilMillis)
            }
            views.setChronometer(R.id.la_chrono, base, formatChrono(model), true)
            if (Build.VERSION.SDK_INT >= 24) {
                views.setChronometerCountDown(R.id.la_chrono, countDown)
            }
        } else {
            views.setViewVisibility(R.id.la_chrono, View.GONE)
        }

        val progress = model.progress
        if (progress != null) {
            views.setViewVisibility(R.id.la_progress, View.VISIBLE)
            views.setProgressBar(
                R.id.la_progress,
                1000,
                (progress.coerceIn(0.0, 1.0) * 1000).toInt(),
                false,
            )
            val label = model.progressLabel
            if (label.isNullOrBlank()) {
                views.setViewVisibility(R.id.la_progress_label, View.GONE)
            } else {
                views.setViewVisibility(R.id.la_progress_label, View.VISIBLE)
                views.setTextViewText(R.id.la_progress_label, label)
            }
        } else {
            views.setViewVisibility(R.id.la_progress, View.GONE)
            views.setViewVisibility(R.id.la_progress_label, View.GONE)
        }
        return views
    }

    private fun formatChrono(model: LayoutFlattener.Model): String {
        val prefix = model.countdownPrefix?.let { "$it " } ?: ""
        val suffix = model.countdownSuffix?.let { " $it" } ?: ""
        return "${prefix}%s$suffix"
    }

    private fun pending(id: String, action: String, url: String?): PendingIntent {
        val intent = Intent(context, LiveActivityActionReceiver::class.java).apply {
            this.action = action
            putExtra(LiveActivityActionReceiver.EXTRA_ID, id)
            if (!url.isNullOrEmpty()) putExtra(LiveActivityActionReceiver.EXTRA_URL, url)
        }
        val requestCode = (action.hashCode() xor id.hashCode())
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun cancel(id: String) {
        cancelScheduledEnd(id)
        notifications.cancel(notifyId(id))
    }

    private fun scheduleEnd(id: String, delayMs: Long) {
        cancelScheduledEnd(id)
        val runnable = Runnable {
            cancel(id)
            running.remove(id)
            emitState(id, "dismissed")
        }
        endRunnables[id] = runnable
        handler.postDelayed(runnable, delayMs)
    }

    private fun cancelScheduledEnd(id: String) {
        endRunnables.remove(id)?.let { handler.removeCallbacks(it) }
    }

    private fun emitState(id: String, state: String) {
        onEvent?.invoke(mapOf("type" to "state", "id" to id, "state" to state))
    }

    private fun requireId(args: Map<String, Any?>): String =
        args["id"] as? String ?: throw Failure.InvalidArgument("Missing id.")

    private fun notifyId(id: String): Int = 0x4A1C0000 or (id.hashCode() and 0xFFFF)

    companion object {
        const val CHANNEL_ID = "live_activity_kit"

        fun hasNotificationPermission(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < 33) return true
            return ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    sealed class Failure(val code: String, override val message: String) : Exception(message) {
        object Unsupported : Failure(
            "unsupported",
            "Live activities on Android require API 26 (notification channels).",
        )
        object Disabled : Failure(
            "disabled",
            "Notification permission is off for this app. Enable it in Settings.",
        )
        class NotFound(id: String) : Failure("not_found", "No running Live Activity with id \"$id\".")
        class InvalidArgument(detail: String) : Failure("invalid_argument", detail)
    }
}
