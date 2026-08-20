package com.nianup.live_activity_kit

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LayoutFlattenerTest {
    @Test
    fun lockScreenPreferredAndProgressExtracted() {
        val json = """
            {
              "deepLink": "myapp://order/1042",
              "theme": { "tint": "#0A84FF" },
              "regions": {
                "compactTrailing": { "type": "text", "value": "12 min" },
                "lockScreen": {
                  "type": "column",
                  "children": [
                    { "type": "text", "value": "Out for delivery", "weight": "bold" },
                    { "type": "progress", "value": 0.7, "label": "3/4" },
                    { "type": "countdown", "until": 1710000000.0, "style": "relative", "prefix": "arrives" }
                  ]
                }
              }
            }
        """.trimIndent()

        val model = LayoutFlattener.flatten(json)
        assertEquals("Out for delivery", model.title)
        assertEquals(0.7, model.progress!!, 0.0001)
        assertEquals("3/4", model.progressLabel)
        assertEquals(1710000000.0, model.countdownUntilEpochSec!!, 0.01)
        assertEquals("relative", model.countdownStyle)
        assertEquals("arrives", model.countdownPrefix)
        assertEquals("myapp://order/1042", model.deepLink)
        assertEquals(0xFF0A84FF.toInt(), model.tintArgb)
    }

    @Test
    fun compactFallbackWhenLockScreenMissing() {
        val json = """
            {"regions":{"compactTrailing":{"type":"text","value":"🍱 1:00"}}}
        """.trimIndent()
        val model = LayoutFlattener.flatten(json)
        assertEquals("🍱 1:00", model.title)
        assertTrue(model.body.isEmpty())
        assertNull(model.progress)
    }

    @Test
    fun metricAndNestedRowFlattenToText() {
        val json = """
            {
              "regions": {
                "lockScreen": {
                  "type": "row",
                  "children": [
                    { "type": "metric", "value": "4.21", "unit": "km", "label": "distance" },
                    { "type": "text", "value": "live" }
                  ]
                }
              }
            }
        """.trimIndent()
        val model = LayoutFlattener.flatten(json)
        assertEquals("distance 4.21 km", model.title)
        assertEquals("live", model.body)
    }
}
