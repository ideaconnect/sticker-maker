package tech.idct.sticker_maker

import android.content.Intent
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
        private const val ADD_PACK_REQUEST = 200
    }
}
