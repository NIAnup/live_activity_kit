package com.nianup.live_activity_kit

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
        val body: String,
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
        var progress: Double? = null
        var progressLabel: String? = null
        var countdownUntil: Double? = null
        var countdownStyle = "timer"
        var countdownPrefix: String? = null
        var countdownSuffix: String? = null

        walk(node, texts) { p, label, until, style, prefix, suffix ->
            if (progress == null && p != null) {
                progress = p
                progressLabel = label
            }
            if (countdownUntil == null && until != null) {
                countdownUntil = until
                countdownStyle = style ?: "timer"
                countdownPrefix = prefix
                countdownSuffix = suffix
            }
        }

        val title = texts.firstOrNull().orEmpty().ifBlank { "Live activity" }
        val body = texts.drop(1).joinToString(" · ")
        val theme = root.optJSONObject("theme")
        return Model(
            title = title,
            body = body,
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
        capture: (
            progress: Double?,
            progressLabel: String?,
            until: Double?,
            style: String?,
            prefix: String?,
            suffix: String?,
        ) -> Unit,
    ) {
        if (node == null) return
        when (node.optString("type")) {
            "text" -> {
                val value = node.optString("value")
                if (value.isNotEmpty()) texts.add(value)
            }
            "row", "column" -> children(node).forEach { walk(it, texts, capture) }
            "progress", "circularProgress" -> {
                capture(
                    node.optDouble("value", Double.NaN).takeUnless { it.isNaN() },
                    node.optString("label", null)?.takeIf { it.isNotEmpty() },
                    null, null, null, null,
                )
                walk(node.optJSONObject("center"), texts, capture)
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
            )
            "padding", "container" -> walk(node.optJSONObject("child"), texts, capture)
            else -> {
                walk(node.optJSONObject("child"), texts, capture)
                children(node).forEach { walk(it, texts, capture) }
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
