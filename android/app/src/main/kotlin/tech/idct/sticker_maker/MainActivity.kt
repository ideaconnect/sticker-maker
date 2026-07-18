package tech.idct.sticker_maker

import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isWhatsAppInstalled" ->
                        result.success(
                            isInstalled("com.whatsapp") || isInstalled("com.whatsapp.w4b"),
                        )
                    "addStickerPack" -> {
                        val id = call.argument<String>("identifier")
                        val name = call.argument<String>("name")
                        if (id.isNullOrEmpty() || name.isNullOrEmpty()) {
                            result.error("bad_args", "identifier and name are required", null)
                        } else {
                            addStickerPackToWhatsApp(id, name, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLATFORM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Opens a deep link (e.g. tg://resolve for @Stickers).
                    "openUri" -> {
                        val uri = call.argument<String>("uri")
                        if (uri.isNullOrEmpty()) {
                            result.error("bad_args", "uri is required", null)
                        } else {
                            try {
                                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uri)))
                                result.success(true)
                            } catch (e: Exception) {
                                result.success(false)
                            }
                        }
                    }
                    // Saves bytes into the shared Downloads collection.
                    "saveToDownloads" -> {
                        val name = call.argument<String>("fileName")
                        val mime = call.argument<String>("mimeType")
                        val bytes = call.argument<ByteArray>("bytes")
                        if (name.isNullOrEmpty() || mime.isNullOrEmpty() || bytes == null) {
                            result.error("bad_args", "fileName, mimeType and bytes are required", null)
                        } else {
                            saveToDownloads(name, mime, bytes, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Inserts [bytes] as a new file in the public Downloads collection. */
    private fun saveToDownloads(
        name: String,
        mime: String,
        bytes: ByteArray,
        result: MethodChannel.Result,
    ) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, name)
                    put(MediaStore.Downloads.MIME_TYPE, mime)
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val resolver = contentResolver
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: throw IllegalStateException("MediaStore insert returned null")
                resolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("could not open output stream")
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                result.success("Downloads/$name")
            } else {
                // API 26–28: legacy external Downloads dir (no runtime permission
                // needed for app-created files via MediaStore isn't available —
                // write directly; these OS versions predate scoped storage).
                @Suppress("DEPRECATION")
                val dir = Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOWNLOADS,
                )
                dir.mkdirs()
                val file = File(dir, name)
                file.writeBytes(bytes)
                result.success(file.absolutePath)
            }
        } catch (e: Exception) {
            result.error("save_failed", e.message, null)
        }
    }

    private fun isInstalled(pkg: String): Boolean = try {
        packageManager.getPackageInfo(pkg, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    private fun addStickerPackToWhatsApp(
        identifier: String,
        name: String,
        result: MethodChannel.Result,
    ) {
        val intent = Intent("com.whatsapp.intent.action.ENABLE_STICKER_PACK").apply {
            putExtra("sticker_pack_id", identifier)
            putExtra("sticker_pack_authority", "$packageName.stickercontentprovider")
            putExtra("sticker_pack_name", name)
        }
        try {
            startActivityForResult(intent, ADD_PACK_REQUEST)
            result.success(true)
        } catch (e: Exception) {
            result.error("no_whatsapp", "WhatsApp couldn't handle the request: ${e.message}", null)
        }
    }

    companion object {
        private const val CHANNEL = "sticker_maker/whatsapp"
        private const val PLATFORM_CHANNEL = "sticker_maker/platform"
        private const val ADD_PACK_REQUEST = 200
    }
}
