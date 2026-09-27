package com.example.qrcodeapp

import android.app.Activity
import android.content.Intent
import android.provider.OpenableColumns
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var sender: RaptorTransferCodec.Sender? = null
    private val receiver = RaptorTransferCodec.Receiver()
    private var pendingPicker: MethodChannel.Result? = null
    private var pendingSave: MethodChannel.Result? = null
    private var destroyed = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "qrcodeapp/raptorq")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openCimbar" -> {
                        startActivity(Intent(this, CimbarActivity::class.java))
                        result.success(null)
                    }
                    "keepAwake" -> {
                        if (call.argument<Boolean>("enabled") == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    "pickFile" -> {
                        if (pendingPicker != null) result.error("busy", "正在选择文件", null)
                        else {
                            pendingPicker = result
                            try {
                                startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                    type = "*/*"
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                }, 6330)
                            } catch (e: Exception) {
                                pendingPicker = null
                                result.error("picker", "无法打开文件选择器", null)
                            }
                        }
                    }
                    "createText" -> {
                        val text = call.argument<String>("text") ?: ""
                        background(result) {
                            require(text.isNotEmpty()) { "请输入文本" }
                            val next = RaptorTransferCodec.Sender("文本.txt", text.toByteArray(Charsets.UTF_8))
                            sender = next
                            senderInfo(next)
                        }
                    }
                    "nextFrame" -> background(result) {
                        checkNotNull(sender) { "请先选择文件或输入文本" }.nextFrame()
                    }
                    "clearSender" -> background(result) { sender = null; null }
                    "acceptFrame" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        background(result) {
                            val status = receiver.accept(bytes)
                            val file = receiver.file()
                            mapOf("status" to status, "received" to receiver.received,
                                "needed" to receiver.needed, "progress" to receiver.progress(),
                                "name" to file?.name, "size" to file?.bytes?.size)
                        }
                    }
                    "resetReceiver" -> background(result) { receiver.reset(); null }
                    "saveReceived" -> {
                        val file = receiver.file()
                        if (file == null) result.error("empty", "文件尚未恢复完成", null)
                        else if (pendingSave != null) result.error("busy", "正在保存文件", null)
                        else {
                            pendingSave = result
                            try {
                                startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                    type = "application/octet-stream"
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    putExtra(Intent.EXTRA_TITLE, file.name)
                                }, 6331)
                            } catch (e: Exception) {
                                pendingSave = null
                                result.error("save", "无法打开保存对话框", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun senderInfo(value: RaptorTransferCodec.Sender) = mapOf(
        "name" to value.name, "size" to value.fileSize,
        "sourceSymbols" to value.sourceSymbols, "blocks" to value.blocks)

    private fun background(result: MethodChannel.Result, action: () -> Any?) {
        worker.execute {
            try {
                val value = action()
                runOnUiThread { if (!destroyed) result.success(value) }
            } catch (e: Exception) {
                val message = e.message ?: "文件处理失败，请重试"
                runOnUiThread { if (!destroyed) result.error("transfer", message, null) }
            }
        }
    }

    @Deprecated("Used by FlutterActivity's activity-result dispatch")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 6330) {
            val result = pendingPicker ?: return
            pendingPicker = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return }
            background(result) {
                var name = "file.bin"
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (nameIndex >= 0) name = cursor.getString(nameIndex) ?: name
                        val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                        if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                            require(cursor.getLong(sizeIndex) <= RaptorTransferCodec.MAX_FILE_SIZE) { "文件最大支持 8 MB" }
                        }
                    }
                }
                val out = ByteArrayOutputStream()
                checkNotNull(contentResolver.openInputStream(uri)) { "无法读取所选文件" }.use { input ->
                    val buffer = ByteArray(8192)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        require(out.size() + count <= RaptorTransferCodec.MAX_FILE_SIZE) { "文件最大支持 8 MB" }
                        out.write(buffer, 0, count)
                    }
                }
                val next = RaptorTransferCodec.Sender(name, out.toByteArray())
                sender = next
                senderInfo(next)
            }
        } else if (requestCode == 6331) {
            val result = pendingSave ?: return
            pendingSave = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) { result.success(false); return }
            background(result) {
                val file = checkNotNull(receiver.file()) { "接收结果已被清空" }
                checkNotNull(contentResolver.openOutputStream(uri, "w")) { "无法写入该位置" }.use {
                    it.write(file.bytes)
                    it.flush()
                }
                true
            }
        }
    }

    override fun onDestroy() {
        destroyed = true
        pendingPicker?.error("closed", "页面已关闭", null)
        pendingSave?.error("closed", "页面已关闭", null)
        pendingPicker = null; pendingSave = null
        worker.shutdownNow()
        super.onDestroy()
    }
}
