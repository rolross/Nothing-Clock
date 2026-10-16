package com.rolros.nothingclock

import android.content.Context
import java.net.HttpURLConnection
import java.net.URL

object HaClient {
    private fun prefs(context: Context) =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    fun trigger(context: Context, event: String, done: (() -> Unit)? = null) {
        val app = context.applicationContext
        Thread {
            try {
                val p = prefs(app)
                val url = (p.getString("flutter.ha_url", "") ?: "").trim().trimEnd('/')
                val token = (p.getString("flutter.ha_token", "") ?: "").trim()
                if (url.isNotEmpty() && token.isNotEmpty()) {
                    post(url, token, "/api/events/nothingclock_$event", "{\"event\":\"$event\"}")
                    val entity = (p.getString("flutter.ha_entity_$event", "") ?: "").trim()
                    if (entity.isNotEmpty()) {
                        val domain = entity.substringBefore('.')
                        val known = domain == "script" || domain == "scene" || domain == "automation"
                        val svcDomain = if (known) domain else "homeassistant"
                        val service = if (domain == "automation") "trigger" else "turn_on"
                        post(url, token, "/api/services/$svcDomain/$service", "{\"entity_id\":\"$entity\"}")
                    }
                }
            } catch (e: Exception) {
            } finally {
                done?.invoke()
            }
        }.start()
    }

    private fun post(base: String, token: String, path: String, body: String) {
        val conn = URL(base + path).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = "POST"
            conn.connectTimeout = 3500
            conn.readTimeout = 3500
            conn.doOutput = true
            conn.setRequestProperty("Authorization", "Bearer $token")
            conn.setRequestProperty("Content-Type", "application/json")
            conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            if (code >= 400) throw Exception("HTTP $code")
        } finally {
            conn.disconnect()
        }
    }
}
