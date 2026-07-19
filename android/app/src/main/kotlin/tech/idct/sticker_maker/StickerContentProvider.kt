package tech.idct.sticker_maker

import android.content.ContentProvider
import android.content.ContentValues
import android.content.UriMatcher
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import org.json.JSONObject
import java.io.File

/**
 * Serves runtime-generated sticker packs to WhatsApp (#46).
 *
 * The Flutter side (`WhatsAppPackExporter`) renders each pack into
 * `<filesDir>/wa_export/<packId>/` as `contents.json` + `tray.png` + `<i>.webp`.
 * Unlike WhatsApp's sample (which serves bundled assets), `openAssetFile` here
 * streams those generated files. Cursor/URI contract per
 * github.com/WhatsApp/stickers.
 */
class StickerContentProvider : ContentProvider() {

    private lateinit var authority: String
    private lateinit var matcher: UriMatcher

    private val exportRoot: File
        get() = File(context!!.filesDir, EXPORT_DIR)

    override fun onCreate(): Boolean {
        authority = context!!.packageName + ".stickercontentprovider"
        matcher = UriMatcher(UriMatcher.NO_MATCH).apply {
            addURI(authority, METADATA, CODE_METADATA_ALL)
            addURI(authority, "$METADATA/*", CODE_METADATA_ONE)
            addURI(authority, "$STICKERS/*", CODE_STICKERS)
            addURI(authority, "$STICKERS_ASSET/*/*", CODE_ASSET)
        }
        return true
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? = when (matcher.match(uri)) {
        CODE_METADATA_ALL -> metadataCursor(allPacks())
        CODE_METADATA_ONE -> metadataCursor(listOfNotNull(readPack(uri.lastPathSegment)))
        CODE_STICKERS -> stickersCursor(readPack(uri.lastPathSegment))
        else -> null
    }

    override fun getType(uri: Uri): String? = when (matcher.match(uri)) {
        CODE_METADATA_ALL -> "vnd.android.cursor.dir/vnd.$authority.$METADATA"
        CODE_METADATA_ONE -> "vnd.android.cursor.item/vnd.$authority.$METADATA"
        CODE_STICKERS -> "vnd.android.cursor.dir/vnd.$authority.$STICKERS"
        CODE_ASSET ->
            if ((uri.lastPathSegment ?: "").endsWith(".png")) "image/png" else "image/webp"
        else -> null
    }

    override fun openAssetFile(uri: Uri, mode: String): AssetFileDescriptor? {
        if (matcher.match(uri) != CODE_ASSET) return null
        val segments = uri.pathSegments // [stickers_asset, packId, fileName]
        if (segments.size != 3) return null
        val packId = segments[1]
        val fileName = segments[2]
        // The exporter only writes plain names under wa_export; reject anything
        // traversal-shaped ('..', separators) — the provider is exported, so it
        // must never serve files outside its own export tree.
        if (!isSafeSegment(packId) || !isSafeSegment(fileName)) return null
        val file = File(File(exportRoot, packId), fileName)
        // Belt and braces: the resolved canonical path must stay under wa_export.
        val canonical = file.canonicalFile
        if (!canonical.toPath().startsWith(exportRoot.canonicalFile.toPath())) return null
        if (!canonical.exists()) return null
        val pfd = ParcelFileDescriptor.open(canonical, ParcelFileDescriptor.MODE_READ_ONLY)
        return AssetFileDescriptor(pfd, 0, AssetFileDescriptor.UNKNOWN_LENGTH)
    }

    /** True for a plain file/dir name: non-empty, no '..', no path separators. */
    private fun isSafeSegment(segment: String): Boolean =
        segment.isNotEmpty() &&
            segment != "." &&
            !segment.contains("..") &&
            !segment.contains('/') &&
            !segment.contains('\\') &&
            !segment.contains('\u0000')

    // ---- pack data (read from the Flutter-generated contents.json) ----

    private fun allPacks(): List<JSONObject> {
        val root = exportRoot
        if (!root.isDirectory) return emptyList()
        return root.listFiles { f -> f.isDirectory }
            ?.mapNotNull { readPack(it.name) }
            ?: emptyList()
    }

    /** Reads `sticker_packs[0]` from `<exportRoot>/<packId>/contents.json`. */
    private fun readPack(packId: String?): JSONObject? {
        if (packId.isNullOrEmpty()) return null
        val file = File(File(exportRoot, packId), "contents.json")
        if (!file.exists()) return null
        return try {
            val packs = JSONObject(file.readText()).getJSONArray("sticker_packs")
            if (packs.length() == 0) null else packs.getJSONObject(0)
        } catch (e: Exception) {
            null
        }
    }

    private fun metadataCursor(packs: List<JSONObject>): Cursor {
        val cursor = MatrixCursor(
            arrayOf(
                "sticker_pack_identifier",
                "sticker_pack_name",
                "sticker_pack_publisher",
                "sticker_pack_icon",
                "android_play_store_link",
                "ios_app_download_link",
                "sticker_pack_publisher_email",
                "sticker_pack_publisher_website",
                "sticker_pack_privacy_policy_website",
                "sticker_pack_license_agreement_website",
                "image_data_version",
                "whatsapp_will_not_cache_stickers",
                "animated_sticker_pack",
            ),
        )
        for (p in packs) {
            cursor.newRow()
                .add(p.optString("identifier"))
                .add(p.optString("name"))
                .add(p.optString("publisher"))
                .add(p.optString("tray_image_file"))
                .add(p.optString("android_play_store_link"))
                .add(p.optString("ios_app_store_link"))
                .add(p.optString("publisher_email"))
                .add(p.optString("publisher_website"))
                .add(p.optString("privacy_policy_website"))
                .add(p.optString("license_agreement_website"))
                .add(p.optString("image_data_version", "1"))
                .add(if (p.optBoolean("avoid_cache", false)) 1 else 0)
                .add(if (p.optBoolean("animated_sticker_pack", false)) 1 else 0)
        }
        return cursor
    }

    private fun stickersCursor(pack: JSONObject?): Cursor {
        val cursor = MatrixCursor(
            arrayOf("sticker_file_name", "sticker_emoji", "sticker_accessibility_text"),
        )
        val stickers = pack?.optJSONArray("stickers") ?: return cursor
        for (i in 0 until stickers.length()) {
            val s = stickers.getJSONObject(i)
            val emojis = s.optJSONArray("emojis")
            val emojiStr = if (emojis == null) {
                ""
            } else {
                (0 until emojis.length()).joinToString(",") { emojis.getString(it) }
            }
            cursor.newRow().add(s.optString("image_file")).add(emojiStr).add("")
        }
        return cursor
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? =
        throw UnsupportedOperationException("Not supported")

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int =
        throw UnsupportedOperationException("Not supported")

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = throw UnsupportedOperationException("Not supported")

    companion object {
        private const val EXPORT_DIR = "wa_export"
        private const val METADATA = "metadata"
        private const val STICKERS = "stickers"
        private const val STICKERS_ASSET = "stickers_asset"
        private const val CODE_METADATA_ALL = 1
        private const val CODE_METADATA_ONE = 2
        private const val CODE_STICKERS = 3
        private const val CODE_ASSET = 5
    }
}
