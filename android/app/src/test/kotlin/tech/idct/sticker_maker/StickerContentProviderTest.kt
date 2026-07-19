package tech.idct.sticker_maker

import android.content.Context
import android.net.Uri
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import androidx.test.core.app.ApplicationProvider
import java.io.File

/**
 * Pins the cross-language contract between the Flutter exporter
 * (`WhatsAppPackExporter`, which writes `<filesDir>/wa_export/<packId>/`) and
 * the Kotlin [StickerContentProvider] WhatsApp reads packs through
 * (docs/reviews/2026-07-19-review.md, "StickerContentProvider has zero
 * automated tests"). Also pins the openAssetFile path-traversal guard.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class StickerContentProviderTest {

    private lateinit var context: Context
    private lateinit var authority: String
    private lateinit var provider: StickerContentProvider
    private lateinit var exportRoot: File
    private lateinit var packDir: File

    private val trayBytes = byteArrayOf(0x50, 0x4E, 0x47, 0x00, 0x01)
    private val sticker0Bytes = byteArrayOf(0x52, 0x49, 0x46, 0x46, 0x10, 0x20)
    private val sticker1Bytes = byteArrayOf(0x52, 0x49, 0x46, 0x46, 0x7F, 0x01, 0x02)

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        authority = context.packageName + ".stickercontentprovider"

        // Fixture tree mirroring exactly what WhatsAppPackExporter writes.
        exportRoot = File(context.filesDir, "wa_export")
        packDir = File(exportRoot, PACK_ID)
        packDir.mkdirs()
        File(packDir, "contents.json").writeText(exporterShapedContentsJson())
        File(packDir, "tray.png").writeBytes(trayBytes)
        File(packDir, "0.webp").writeBytes(sticker0Bytes)
        File(packDir, "1.webp").writeBytes(sticker1Bytes)

        // A file OUTSIDE wa_export that a traversal-shaped URI would reach.
        File(context.filesDir, "secret.txt").writeBytes(byteArrayOf(1, 2, 3))

        provider = Robolectric.setupContentProvider(
            StickerContentProvider::class.java,
            authority,
        )
    }

    /** Same shape (nesting + field names) as WhatsAppPackExporter.export(). */
    private fun exporterShapedContentsJson(): String =
        """
        {
          "android_play_store_link": "",
          "ios_app_store_link": "",
          "sticker_packs": [
            {
              "identifier": "$PACK_ID",
              "name": "Doodle Cats",
              "publisher": "Sticker Maker",
              "tray_image_file": "tray.png",
              "image_data_version": "1",
              "avoid_cache": false,
              "animated_sticker_pack": false,
              "publisher_email": "",
              "publisher_website": "",
              "privacy_policy_website": "",
              "license_agreement_website": "",
              "stickers": [
                {"image_file": "0.webp", "emojis": ["😀", "🎉"]},
                {"image_file": "1.webp", "emojis": ["🔥"]}
              ]
            }
          ]
        }
        """.trimIndent()

    private fun metadataUri(packId: String? = null): Uri =
        Uri.parse("content://$authority/metadata" + if (packId != null) "/$packId" else "")

    private fun stickersUri(packId: String): Uri =
        Uri.parse("content://$authority/stickers/$packId")

    private fun assetUri(packId: String, fileName: String): Uri =
        Uri.parse("content://$authority/stickers_asset/$packId/$fileName")

    // ---- 1. metadata contract ----

    @Test
    fun metadataQuery_returnsWhatsApps13ColumnsWithContentsJsonValues() {
        val cursor = provider.query(metadataUri(PACK_ID), null, null, null, null)
        assertNotNull(cursor)
        cursor!!.use {
            assertArrayEquals(
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
                it.columnNames,
            )
            assertEquals(1, it.count)
            assertTrue(it.moveToFirst())
            assertEquals(PACK_ID, it.getString(0))
            assertEquals("Doodle Cats", it.getString(1))
            assertEquals("Sticker Maker", it.getString(2))
            assertEquals("tray.png", it.getString(3))
            // The exporter writes the store links at the top level of
            // contents.json, not inside the pack object, so the provider
            // serves them as empty strings.
            assertEquals("", it.getString(4))
            assertEquals("", it.getString(5))
            assertEquals("", it.getString(6))
            assertEquals("", it.getString(7))
            assertEquals("", it.getString(8))
            assertEquals("", it.getString(9))
            assertEquals("1", it.getString(10)) // image_data_version
            assertEquals(0, it.getInt(11)) // avoid_cache=false -> 0
            assertEquals(0, it.getInt(12)) // animated_sticker_pack=false -> 0
        }
    }

    @Test
    fun metadataQuery_appliesDefaultsWhenOptionalFieldsMissing() {
        val minimalDir = File(exportRoot, "minimal_pack")
        minimalDir.mkdirs()
        File(minimalDir, "contents.json").writeText(
            """
            {
              "sticker_packs": [
                {"identifier": "minimal_pack", "name": "Min", "publisher": "P",
                 "tray_image_file": "tray.png", "stickers": []}
              ]
            }
            """.trimIndent(),
        )
        val cursor = provider.query(metadataUri("minimal_pack"), null, null, null, null)
        assertNotNull(cursor)
        cursor!!.use {
            assertTrue(it.moveToFirst())
            assertEquals("1", it.getString(10)) // image_data_version defaults to "1"
            assertEquals(0, it.getInt(11)) // avoid_cache defaults to false
            assertEquals(0, it.getInt(12)) // animated defaults to false
        }
    }

    @Test
    fun metadataQuery_allPacks_listsTheFixturePack() {
        val cursor = provider.query(metadataUri(), null, null, null, null)
        assertNotNull(cursor)
        cursor!!.use {
            assertEquals(1, it.count)
            assertTrue(it.moveToFirst())
            assertEquals(PACK_ID, it.getString(0))
        }
    }

    // ---- 2. stickers contract ----

    @Test
    fun stickersQuery_rowsCarryFileNameCommaJoinedEmojisAndAccessibilityText() {
        val cursor = provider.query(stickersUri(PACK_ID), null, null, null, null)
        assertNotNull(cursor)
        cursor!!.use {
            assertArrayEquals(
                arrayOf("sticker_file_name", "sticker_emoji", "sticker_accessibility_text"),
                it.columnNames,
            )
            assertEquals(2, it.count)
            assertTrue(it.moveToFirst())
            assertEquals("0.webp", it.getString(0))
            assertEquals("😀,🎉", it.getString(1))
            assertEquals("", it.getString(2))
            assertTrue(it.moveToNext())
            assertEquals("1.webp", it.getString(0))
            assertEquals("🔥", it.getString(1))
            assertEquals("", it.getString(2))
        }
    }

    // ---- 3. openAssetFile ----

    @Test
    fun openAssetFile_servesTheFixtureBytesForAnExistingFile() {
        val afd = provider.openAssetFile(assetUri(PACK_ID, "0.webp"), "r")
        assertNotNull(afd)
        val bytes = afd!!.createInputStream().use { it.readBytes() }
        assertArrayEquals(sticker0Bytes, bytes)

        val trayAfd = provider.openAssetFile(assetUri(PACK_ID, "tray.png"), "r")
        assertNotNull(trayAfd)
        val trayRead = trayAfd!!.createInputStream().use { it.readBytes() }
        assertArrayEquals(trayBytes, trayRead)
    }

    @Test
    fun openAssetFile_returnsNullForAMissingFile() {
        assertNull(provider.openAssetFile(assetUri(PACK_ID, "missing.webp"), "r"))
        assertNull(provider.openAssetFile(assetUri("no_such_pack", "0.webp"), "r"))
    }

    @Test
    fun openAssetFile_rejectsTraversalShapedSegments() {
        // secret.txt exists at <filesDir>/secret.txt — one level above
        // wa_export — and must never be reachable through the provider.
        assertTrue(File(context.filesDir, "secret.txt").exists())

        // '..' as the pack segment: <wa_export>/../secret.txt.
        assertNull(
            provider.openAssetFile(
                Uri.parse("content://$authority/stickers_asset/../secret.txt"),
                "r",
            ),
        )
        // Encoded '/' smuggling extra traversal inside one segment.
        assertNull(
            provider.openAssetFile(
                Uri.parse(
                    "content://$authority/stickers_asset/$PACK_ID/..%2F..%2Fsecret.txt",
                ),
                "r",
            ),
        )
        // '..'-shaped file segment inside a valid pack.
        assertNull(
            provider.openAssetFile(
                Uri.parse("content://$authority/stickers_asset/$PACK_ID/.."),
                "r",
            ),
        )
        // Backslash separator variant.
        assertNull(
            provider.openAssetFile(
                Uri.parse(
                    "content://$authority/stickers_asset/$PACK_ID/..%5C..%5Csecret.txt",
                ),
                "r",
            ),
        )
    }

    // ---- 4. corrupt contents.json ----

    @Test
    fun corruptContentsJson_yieldsEmptyCursorsWithoutCrashing() {
        val corruptDir = File(exportRoot, "corrupt_pack")
        corruptDir.mkdirs()
        File(corruptDir, "contents.json").writeText("{ this is not json !!!")

        val metadata = provider.query(metadataUri("corrupt_pack"), null, null, null, null)
        assertNotNull(metadata)
        metadata!!.use { assertEquals(0, it.count) }

        val stickers = provider.query(stickersUri("corrupt_pack"), null, null, null, null)
        assertNotNull(stickers)
        stickers!!.use { assertEquals(0, it.count) }

        // The healthy pack still shows up in the all-packs listing.
        val all = provider.query(metadataUri(), null, null, null, null)
        assertNotNull(all)
        all!!.use {
            assertEquals(1, it.count)
            assertTrue(it.moveToFirst())
            assertEquals(PACK_ID, it.getString(0))
        }
    }

    // ---- 5. getType ----

    @Test
    fun getType_returnsImagePngForTrayAndImageWebpOtherwise() {
        assertEquals("image/png", provider.getType(assetUri(PACK_ID, "tray.png")))
        assertEquals("image/webp", provider.getType(assetUri(PACK_ID, "0.webp")))
        assertEquals("image/webp", provider.getType(assetUri(PACK_ID, "1.webp")))
    }

    private companion object {
        const val PACK_ID = "pack_1721400000000000"
    }
}
