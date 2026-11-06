package com.andregomez.controle_lg

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Point
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.net.wifi.WifiManager
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var picker: MethodChannel.Result? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "sixf/library").setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> {
                    if (picker != null) { result.error("busy", "Seleção em andamento", null); return@setMethodCallHandler }
                    picker = result
                    try { startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), 6103) }
                    catch (e: Exception) { picker = null; result.error("folder", e.message, null) }
                }
                // mDNS (descoberta da porta ADB do Chromecast): o Android descarta pacotes
                // multicast recebidos enquanto nenhum app segura um MulticastLock.
                "multicastLock" -> {
                    try {
                        val lock = multicastLock ?: (applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager)
                            .createMulticastLock("sixf-mdns").also { it.setReferenceCounted(false); multicastLock = it }
                        if (!lock.isHeld) lock.acquire()
                        result.success(true)
                    } catch (e: Exception) { result.success(false) }
                }
                "multicastUnlock" -> {
                    try { multicastLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
                    result.success(null)
                }
                "list", "copy", "thumbnail" -> Thread {
                    try {
                        val value: Any? = when (call.method) {
                            "list" -> {
                                val uri = Uri.parse(call.arguments as String)
                                val children = DocumentsContract.buildChildDocumentsUriUsingTree(uri, DocumentsContract.getDocumentId(uri))
                                val fields = arrayOf("document_id", "_display_name", "mime_type", "_size")
                                val rows = mutableListOf<Map<String, Any?>>()
                                val cursor = contentResolver.query(children, fields, null, null, null) ?: error("Pasta indisponível")
                                cursor.use { while (it.moveToNext()) {
                                    val mime = it.getString(2)
                                    rows.add(mapOf(
                                        "id" to DocumentsContract.buildDocumentUriUsingTree(uri, it.getString(0)).toString(),
                                        "name" to (it.getString(1) ?: ""),
                                        "folder" to (mime == DocumentsContract.Document.MIME_TYPE_DIR),
                                        "mime" to mime,
                                        "size" to (if (it.isNull(3)) null else it.getLong(3)),
                                    ))
                                } }
                                rows
                            }
                            "copy" -> {
                                val input = contentResolver.openInputStream(Uri.parse(call.argument<String>("uri"))) ?: error("Arquivo indisponível")
                                input.use { stream -> File(call.argument<String>("path")!!).outputStream().use { stream.copyTo(it) } }
                                null
                            }
                            else -> thumbnail(
                                Uri.parse(call.argument<String>("uri")),
                                File(call.argument<String>("path")!!),
                                call.argument<Int>("size") ?: 256,
                                call.argument<Boolean>("video") == true,
                            )
                        }
                        runOnUiThread { result.success(value) }
                    } catch (e: Exception) { runOnUiThread { result.error("document", e.message, null) } }
                }.start()
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Miniatura de um documento SAF (pasta local ou Google Drive pelo seletor nativo).
     * 1) miniatura oferecida pelo provedor; 2) quadro do vídeo; 3) imagem reduzida.
     * Retorna o caminho do JPEG gravado, ou null quando não há como gerar.
     */
    private fun thumbnail(uri: Uri, target: File, size: Int, video: Boolean): String? {
        var bitmap: Bitmap? = try {
            DocumentsContract.getDocumentThumbnail(contentResolver, uri, Point(size, size), null)
        } catch (_: Exception) { null }
        if (bitmap == null && video) {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(this, uri)
                val frame = retriever.getFrameAtTime(3_000_000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    ?: retriever.getFrameAtTime(0)
                if (frame != null) {
                    val scale = size.toFloat() / maxOf(frame.width, frame.height)
                    bitmap = if (scale < 1f) Bitmap.createScaledBitmap(frame, (frame.width * scale).toInt().coerceAtLeast(1), (frame.height * scale).toInt().coerceAtLeast(1), true) else frame
                }
            } catch (_: Exception) {
            } finally { try { retriever.release() } catch (_: Exception) {} }
        }
        if (bitmap == null && !video) {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= size && bounds.outHeight / (sample * 2) >= size) sample *= 2
            bitmap = contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
            }
        }
        val result = bitmap ?: return null
        target.parentFile?.mkdirs()
        target.outputStream().use { result.compress(Bitmap.CompressFormat.JPEG, 82, it) }
        return target.path
    }

    override fun onDestroy() {
        try { multicastLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        super.onDestroy()
    }

    @Deprecated("Activity result callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 6103) return
        val result = picker ?: return
        picker = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return }
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            result.success(DocumentsContract.buildDocumentUriUsingTree(uri, DocumentsContract.getTreeDocumentId(uri)).toString())
        } catch (e: Exception) { result.error("folder", e.message, null) }
    }
}
