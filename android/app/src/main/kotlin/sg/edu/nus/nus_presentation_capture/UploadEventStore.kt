package sg.edu.nus.nus_presentation_capture

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object UploadEventStore {
    private const val preferencesName = "background_upload_events"
    private const val eventsKey = "events"

    @Synchronized
    fun append(context: Context, event: JSONObject) {
        val preferences = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
        val events = runCatching { JSONArray(preferences.getString(eventsKey, "[]")) }
            .getOrDefault(JSONArray())
        events.put(event)
        val trimmed = JSONArray()
        val first = maxOf(0, events.length() - 1000)
        for (index in first until events.length()) trimmed.put(events.get(index))
        preferences.edit().putString(eventsKey, trimmed.toString()).commit()
    }

    @Synchronized
    fun drain(context: Context): List<Map<String, Any?>> {
        val preferences = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
        val events = runCatching { JSONArray(preferences.getString(eventsKey, "[]")) }
            .getOrDefault(JSONArray())
        val result = mutableListOf<Map<String, Any?>>()
        for (index in 0 until events.length()) {
            val event = events.optJSONObject(index) ?: continue
            val values = mutableMapOf<String, Any?>()
            for (key in event.keys()) {
                values[key] = event.opt(key).takeUnless { it == JSONObject.NULL }
            }
            result.add(values)
        }
        preferences.edit().remove(eventsKey).commit()
        return result
    }
}
