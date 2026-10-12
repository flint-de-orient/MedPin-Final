package com.fdo.medpin

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// FragmentActivity: required by local_auth for the app-lock prompt.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // "Download" on prescriptions and reports: saves into the phone's
        // Downloads/MedPin folder (MediaStore, no storage permission needed).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "medpin/downloads").setMethodCallHandler { call, result ->
            if (call.method != "save") return@setMethodCallHandler result.notImplemented()
            val source = call.argument<String>("path")
            val name = call.argument<String>("name")
            val mime = call.argument<String>("mime") ?: "application/pdf"
            if (source == null || name == null) return@setMethodCallHandler result.error("ARGS", "path and name are required", null)
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return@setMethodCallHandler result.error("OLD_ANDROID", "Saving needs Android 10 or later", null)
            try {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, name)
                    put(MediaStore.Downloads.MIME_TYPE, mime)
                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/MedPin")
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val resolver = contentResolver
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: return@setMethodCallHandler result.error("SAVE", "Couldn't create the file", null)
                resolver.openOutputStream(uri).use { out -> File(source).inputStream().use { it.copyTo(out!!) } }
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                // The name Android actually used ("… (1).pdf" when one exists).
                var saved = name
                resolver.query(uri, arrayOf(MediaStore.Downloads.DISPLAY_NAME), null, null, null)?.use { c ->
                    if (c.moveToFirst()) saved = c.getString(0) ?: name
                }
                result.success(mapOf("uri" to uri.toString(), "name" to saved))
            } catch (e: Exception) {
                result.error("SAVE", e.message, null)
            }
        }
    }
}
