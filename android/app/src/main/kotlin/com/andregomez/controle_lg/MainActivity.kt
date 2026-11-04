package com.andregomez.controle_lg

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var picker: MethodChannel.Result? = null

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
                "list", "copy" -> Thread {
                    try {
                        val value: Any? = if (call.method == "list") {
                            val uri = Uri.parse(call.arguments as String)
                            val children = DocumentsContract.buildChildDocumentsUriUsingTree(uri, DocumentsContract.getDocumentId(uri))
                            val fields = arrayOf("document_id", "_display_name", "mime_type")
                            val rows = mutableListOf<Map<String, Any>>()
                            val cursor = contentResolver.query(children, fields, null, null, null) ?: error("Pasta indisponível")
                            cursor.use { while (it.moveToNext()) {
                                rows.add(mapOf("id" to DocumentsContract.buildDocumentUriUsingTree(uri, it.getString(0)).toString(),
                                    "name" to (it.getString(1) ?: ""), "folder" to (it.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR)))
                            } }
                            rows
                        } else {
                            val input = contentResolver.openInputStream(Uri.parse(call.argument<String>("uri"))) ?: error("Arquivo indisponível")
                            input.use { stream -> File(call.argument<String>("path")!!).outputStream().use { stream.copyTo(it) } }
                            null
                        }
                        runOnUiThread { result.success(value) }
                    } catch (e: Exception) { runOnUiThread { result.error("document", e.message, null) } }
                }.start()
                else -> result.notImplemented()
            }
        }
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
