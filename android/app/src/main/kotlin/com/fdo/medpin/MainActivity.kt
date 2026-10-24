package com.fdo.medpin

import android.content.ContentValues
import android.content.Intent
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

// FragmentActivity: required by local_auth for the app-lock prompt.
class MainActivity : FlutterFragmentActivity() {
    // PDF pages are drawn one at a time, off the UI thread.
    private val pdfWorker = Executors.newSingleThreadExecutor()

    // Profile › Alarm sound: Android's own sound picker, and a short preview at alarm volume.
    private var soundResult: MethodChannel.Result? = null
    private var preview: Ringtone? = null
    private val pickSound = 4711

    private fun stopPreview() {
        try { preview?.stop() } catch (_: Exception) {}
        preview = null
    }

    @Deprecated("Activity results for the ringtone picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickSound) return
        val result = soundResult ?: return
        soundResult = null
        if (resultCode != RESULT_OK) return result.success(null)
        @Suppress("DEPRECATION")
        val uri: Uri? = data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        if (uri == null) return result.success(null)
        val title = try { RingtoneManager.getRingtone(this, uri)?.getTitle(this) } catch (_: Exception) { null }
        result.success(mapOf("uri" to uri.toString(), "title" to (title ?: "Sound from this phone")))
    }

    override fun onPause() {
        stopPreview()
        super.onPause()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // pick {current?} → {uri, title} or null; preview {uri}; stop; title {uri} → name.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "medpin/sound").setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> {
                    if (soundResult != null) return@setMethodCallHandler result.error("BUSY", "The sound picker is already open", null)
                    stopPreview()
                    val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                        putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM or RingtoneManager.TYPE_RINGTONE)
                        putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                        putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                        putExtra(RingtoneManager.EXTRA_RINGTONE_DEFAULT_URI, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))
                        call.argument<String>("current")?.let { putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, Uri.parse(it)) }
                    }
                    soundResult = result
                    try {
                        @Suppress("DEPRECATION")
                        startActivityForResult(intent, pickSound)
                    } catch (e: Exception) {
                        soundResult = null
                        result.error("NO_PICKER", "This phone has no sound picker", null)
                    }
                }
                "preview" -> {
                    stopPreview()
                    val uri = call.argument<String>("uri") ?: return@setMethodCallHandler result.error("ARGS", "uri is required", null)
                    try {
                        val r = RingtoneManager.getRingtone(this, Uri.parse(uri)) ?: return@setMethodCallHandler result.success(false)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                            r.audioAttributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
                        }
                        r.play()
                        preview = r
                        // A preview, not the alarm: it stops by itself after a few seconds.
                        window.decorView.postDelayed({ if (preview === r) stopPreview() }, 6000)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "stop" -> {
                    stopPreview()
                    result.success(true)
                }
                "title" -> {
                    val uri = call.argument<String>("uri")
                    val title = try { if (uri == null) null else RingtoneManager.getRingtone(this, Uri.parse(uri))?.getTitle(this) } catch (_: Exception) { null }
                    result.success(title)
                }
                else -> result.notImplemented()
            }
        }
        // Reports and prescriptions shown inside the app: a page of a PDF as a
        // PNG, with Android's own PdfRenderer (no extra library).
        // render {path, page (0-based), width px} → {png, pages, width, height}
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "medpin/pdf").setMethodCallHandler { call, result ->
            if (call.method != "render") return@setMethodCallHandler result.notImplemented()
            val path = call.argument<String>("path") ?: return@setMethodCallHandler result.error("ARGS", "path is required", null)
            val wanted = call.argument<Int>("page") ?: 0
            val width = (call.argument<Int>("width") ?: 1080).coerceIn(64, 2400)
            pdfWorker.execute {
                try {
                    val fd = ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
                    val renderer = PdfRenderer(fd)
                    try {
                        val pages = renderer.pageCount
                        if (pages == 0) throw IllegalStateException("The PDF has no pages")
                        val page = renderer.openPage(wanted.coerceIn(0, pages - 1))
                        try {
                            val height = (width.toFloat() * page.height / page.width).toInt().coerceAtLeast(1)
                            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                            bitmap.eraseColor(Color.WHITE) // PDFs without a background would show black
                            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            val out = ByteArrayOutputStream()
                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                            bitmap.recycle()
                            val png = out.toByteArray()
                            runOnUiThread { result.success(mapOf("png" to png, "pages" to pages, "width" to width, "height" to height)) }
                        } finally {
                            page.close()
                        }
                    } finally {
                        renderer.close()
                        fd.close()
                    }
                } catch (e: Exception) {
                    // Password-protected or damaged files land here.
                    runOnUiThread { result.error("PDF", e.message ?: "Couldn't open the PDF", null) }
                }
            }
        }
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
