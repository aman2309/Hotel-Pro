package com.example.my_first_app

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "hotel_pro/offline_export")
            .setMethodCallHandler { call, result ->
                worker.execute {
                    try {
                        val value: Any = when (call.method) {
                            "readOriginalPreferences" -> readOriginalPreferences()
                            "saveVerifiedBackup" -> saveVerifiedBackup(call.arguments as String)
                            else -> throw IllegalArgumentException("Unknown export method")
                        }
                        runOnUiThread { result.success(value) }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("BACKUP_FAILED", error.message, null) }
                    }
                }
            }
    }

    private fun readOriginalPreferences(): String {
        val file = File(applicationInfo.dataDir, "shared_prefs/FlutterSharedPreferences.xml")
        if (!file.exists()) throw IllegalStateException("Original preferences XML is missing; no defaults created.")
        val before = file.readBytes()
        val values = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE).all
        val prefs = JSONObject()
        values.forEach { (key, value) ->
            prefs.put(key, if (value is Set<*>) JSONArray(value.toList()) else value)
        }
        if (!before.contentEquals(file.readBytes())) throw IllegalStateException("Preferences changed during read; retry export.")
        return JSONObject().put("preferences", prefs).put("rawXml", before.toString(Charsets.UTF_8))
            .put("metadata", JSONObject().put("package", packageName).put("sdk", Build.VERSION.SDK_INT)
                .put("sourceXmlSha256", hash(before))
                .put("exporter", "network-disabled; reads original preferences; no defaults/migration"))
            .toString()
    }

    private fun hash(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }

    private fun saveVerifiedBackup(text: String): Map<String, Any> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            throw IllegalStateException("Downloads export requires Android 10+; no original data changed.")
        }
        val payload = JSONObject(text) // Validate before creating any backup file.
        val originalHash = payload.getJSONObject("nativeMetadata").getString("sourceXmlSha256")
        val source = File(applicationInfo.dataDir, "shared_prefs/FlutterSharedPreferences.xml")
        if (hash(source.readBytes()) != originalHash) throw IllegalStateException("Preferences changed before save; retry export.")
        val bytes = text.toByteArray(Charsets.UTF_8)
        val name = "Hotel_Pro_1_Full_Backup_${System.currentTimeMillis()}.json"
        val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/HotelProRecovery")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }) ?: throw IllegalStateException("Cannot create Downloads backup")
        try {
            contentResolver.openOutputStream(uri, "w")?.use { it.write(bytes); it.flush() }
                ?: throw IllegalStateException("Cannot open backup output")
            val read = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: throw IllegalStateException("Cannot read saved backup")
            if (!bytes.contentEquals(read)) throw IllegalStateException("Backup read-back differs")
            if (hash(source.readBytes()) != originalHash) throw IllegalStateException("Preferences changed during save; retry export.")
            contentResolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
            return mapOf("verified" to true, "name" to name, "bytes" to read.size,
                "sha256" to hash(read), "uri" to uri.toString())
        } catch (error: Exception) {
            // Only this newly-created incomplete export is removed, never source data.
            contentResolver.delete(uri, null, null)
            throw error
        }
    }
}
