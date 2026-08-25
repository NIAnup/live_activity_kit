package com.nianup.live_activity_kit

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject

/**
 * Pulls a notification-sized summary out of the same JSON layout iOS renders
 * as SwiftUI. Android has no Dynamic Island, so we prefer the lock-screen tree
 * and fall back through expanded / compact regions.
 */
internal object LayoutFlattener {

    data class Model(
        val title: String,
        val subtitle: String?,
        val body: String,
        val badgeText: String?,
        val badgeColorArgb: Int?,
        val iconBitmap: Bitmap?,
        val progress: Double?,
        val progressLabel: String?,
        val countdownUntilEpochSec: Double?,
        val countdownStyle: String,
        val countdownPrefix: String?,
        val countdownSuffix: String?,
        val tintArgb: Int?,
        val backgroundArgb: Int?,
        val deepLink: String?,
    )

    fun flatten(layoutJson: String): Model {
        val root = JSONObject(layoutJson)
        val regions = root.optJSONObject("regions") ?: JSONObject()
        val node = pickRegion(regions)
        val texts = ArrayList<String>()
        var iconBitmap: Bitmap? = null
        var progress: Double? = null
        var progressLabel: String? = null
        var countdownUntil: Double? = null
        var countdownStyle = "timer"
        var countdownPrefix: String? = null
        var countdownSuffix: String? = null
        var badgeText: String? = null
        var badgeColor: Int? = null

        walk(node, texts, onImage = { bmp ->
            if (iconBitmap == null && bmp != null) {
                iconBitmap = bmp
            }
        }, capture = { p, label, until, style, prefix, suffix, badge, badgeClr ->
            if (progress == null && p != null) {
                progress = p
                progressLabel = label
            }
            if (until != null &&
                (countdownUntil == null || (countdownStyle == "time" && style != "time"))
            ) {
                countdownUntil = until
                countdownStyle = style ?: "timer"
                countdownPrefix = prefix
                countdownSuffix = suffix
            }
            if (badgeText == null && badge != null) {
                badgeText = badge
                badgeColor = badgeClr
            }
        })

        val title = texts.firstOrNull().orEmpty().ifBlank { "Live activity" }
        val subtitle = if (texts.size > 1) texts[1] else null
        val body = if (texts.size > 2) texts.drop(2).joinToString(" · ") else ""
        val theme = root.optJSONObject("theme")
        return Model(
            title = title,
            subtitle = subtitle,
            body = body,
            badgeText = badgeText,
            badgeColorArgb = badgeColor ?: parseColor("#E53935"),
            iconBitmap = iconBitmap,
            progress = progress,
            progressLabel = progressLabel,
            countdownUntilEpochSec = countdownUntil,
            countdownStyle = countdownStyle,
            countdownPrefix = countdownPrefix,
            countdownSuffix = countdownSuffix,
            tintArgb = parseColor(theme?.optString("tint", null)),
            backgroundArgb = parseColor(theme?.optString("background", null)),
            deepLink = root.optString("deepLink", null)?.takeIf { it.isNotEmpty() },
        )
    }

    private fun pickRegion(regions: JSONObject): JSONObject? {
        val order = listOf(
            "lockScreen",
            "expandedBottom",
            "expandedCenter",
            "compactTrailing",
            "compactLeading",
            "minimal",
            "expandedLeading",
            "expandedTrailing",
        )
        for (key in order) {
            val node = regions.optJSONObject(key)
            if (node != null) return node
        }
        val keys = regions.keys()
        while (keys.hasNext()) {
            val node = regions.optJSONObject(keys.next())
            if (node != null) return node
        }
        return null
    }

    private fun walk(
        node: JSONObject?,
        texts: MutableList<String>,
        onImage: (Bitmap?) -> Unit,
        capture: (
            progress: Double?,
            progressLabel: String?,
            until: Double?,
            style: String?,
            prefix: String?,
            suffix: String?,
            badge: String?,
            badgeColor: Int?,
        ) -> Unit,
    ) {
        if (node == null) return
        when (node.optString("type")) {
            "text" -> {
                val value = node.optString("value")
                if (value.isNotEmpty()) {
                    if (value.startsWith("⚠️") || value.contains("Fraud") || value.contains("诈骗")) {
                        capture(null, null, null, null, null, null, value, parseColor("#D32F2F"))
                    } else {
                        texts.add(value)
                    }
                }
            }
            "badge" -> {
                val value = node.optString("value")
                val color = parseColor(node.optString("color", null))
                if (value.isNotEmpty()) {
                    capture(null, null, null, null, null, null, value, color)
                }
            }
            "image" -> {
                val base64Str = node.optString("bytes", null)
                if (!base64Str.isNullOrEmpty()) {
                    try {
                        val bytes = Base64.decode(base64Str, Base64.DEFAULT)
                        val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        onImage(bmp)
                    } catch (_: Throwable) {}
                }
            }
            "row", "column" -> children(node).forEach { walk(it, texts, onImage, capture) }
            "progress", "circularProgress" -> {
                capture(
                    node.optDouble("value", Double.NaN).takeUnless { it.isNaN() },
                    node.optString("label", null)?.takeIf { it.isNotEmpty() },
                    null, null, null, null, null, null,
                )
                walk(node.optJSONObject("center"), texts, onImage, capture)
            }
            "metric" -> {
                val label = node.optString("label")
                val value = node.optString("value")
                val unit = node.optString("unit")
                val line = listOf(label, listOf(value, unit).filter { it.isNotEmpty() }.joinToString(" "))
                    .filter { it.isNotEmpty() }
                    .joinToString(" ")
                if (line.isNotEmpty()) texts.add(line)
            }
            "countdown" -> capture(
                null, null,
                node.optDouble("until", Double.NaN).takeUnless { it.isNaN() },
                node.optString("style", "timer"),
                node.optString("prefix", null)?.takeIf { it.isNotEmpty() },
                node.optString("suffix", null)?.takeIf { it.isNotEmpty() },
                null, null,
            )
            "padding", "container" -> walk(node.optJSONObject("child"), texts, onImage, capture)
            else -> {
                walk(node.optJSONObject("child"), texts, onImage, capture)
                children(node).forEach { walk(it, texts, onImage, capture) }
            }
        }
    }

    private fun children(node: JSONObject): List<JSONObject> {
        val array: JSONArray = node.optJSONArray("children") ?: return emptyList()
        return List(array.length()) { i -> array.optJSONObject(i) }.filterNotNull()
    }

    internal fun parseColor(raw: String?): Int? {
        if (raw.isNullOrBlank()) return null
        var hex = raw.trim()
        if (hex.startsWith("#")) hex = hex.substring(1)
        if (hex.length == 3) {
            hex = hex.map { "$it$it" }.joinToString("")
        }
        val argb = when (hex.length) {
            6 -> "FF$hex"
            8 -> {
                val rgb = hex.substring(0, 6)
                val a = hex.substring(6)
                "$a$rgb"
            }
            else -> return null
        }
        return argb.toLongOrNull(16)?.toInt()
    }
}
