package com.example.qrcodeapp

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.util.Base64
import android.webkit.*
import android.view.WindowManager
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.File
import java.util.concurrent.Executors

/** Offline-only, secure virtual origin for the bundled Cimbar WASM runtime. */
class CimbarActivity : Activity() {
    private lateinit var web: WebView
    private val worker = Executors.newSingleThreadExecutor()
    @Volatile private var closed = false
    @Volatile private var selected: File? = null
    private var cameraRequest: PermissionRequest? = null
    private var picking = false
    private val saveLock = Any()
    private var saveFile: File? = null
    private var saveName = "received.bin"
    private var expectedSize = 0L
    private var written = 0L
    private var savePending = false
    private lateinit var transferDir: File
    private val origin = "https://appassets.androidplatform.net"

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        transferDir = File(cacheDir, "cimbar-${System.nanoTime()}").apply { mkdirs() }
        web = WebView(this)
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            mediaPlaybackRequiresUserGesture = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        }
        web.addJavascriptInterface(Bridge(), "CimbarNative")
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = request.url.toString() != "$origin/assets/cimbar/index.html"
            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                android.util.Log.e("Cimbar", "WebView load error: ${error.errorCode} ${error.description}")
            }
            override fun onPageFinished(view: WebView, url: String) {
                view.evaluateJavascript("JSON.stringify({title:document.title,body:document.body?.innerText.length,wasm:typeof ready==='undefined'?false:ready})") { android.util.Log.i("Cimbar", "Page loaded: $it") }
            }
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse {
                val uri = request.url
                if (uri.scheme != "https" || uri.host != "appassets.androidplatform.net") return denied()
                return try {
                    if (uri.path == "/selected-file") {
                        val file = selected ?: return denied()
                        WebResourceResponse("application/octet-stream", null, 200, "OK", mapOf("Cache-Control" to "no-store"), file.inputStream())
                    } else {
                        val path = uri.path?.removePrefix("/assets/cimbar/") ?: return denied()
                        if (!uri.path!!.startsWith("/assets/cimbar/") || path.contains("..") || path.contains('\\')) return denied()
                        val type = when (path.substringAfterLast('.')) {
                            "html" -> "text/html"
                            "js" -> "application/javascript"
                            "wasm" -> "application/wasm"
                            "css" -> "text/css"
                            else -> "text/plain"
                        }
                        WebResourceResponse(type, if (type == "application/wasm") null else "UTF-8", assets.open("cimbar/$path"))
                    }
                } catch (_: Exception) { denied() }
            }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onConsoleMessage(message: ConsoleMessage): Boolean {
                if (message.messageLevel() == ConsoleMessage.MessageLevel.ERROR) android.util.Log.e("Cimbar", "Web runtime: ${message.message()}")
                return true
            }
            override fun onPermissionRequest(request: PermissionRequest) {
                runOnUiThread {
                    if (closed || request.origin.toString().trimEnd('/') != origin ||
                        !request.resources.contains(PermissionRequest.RESOURCE_VIDEO_CAPTURE)) {
                        request.deny(); return@runOnUiThread
                    }
                    if (Build.VERSION.SDK_INT < 23 || checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                        request.grant(arrayOf(PermissionRequest.RESOURCE_VIDEO_CAPTURE))
                    } else {
                        cameraRequest?.deny(); cameraRequest = request
                        requestPermissions(arrayOf(Manifest.permission.CAMERA), 6801)
                    }
                }
            }
            override fun onPermissionRequestCanceled(request: PermissionRequest) {
                if (cameraRequest === request) cameraRequest = null
            }
        }
        setContentView(web)
        web.loadUrl("$origin/assets/cimbar/index.html")
    }

    private fun denied() = WebResourceResponse("text/plain", "UTF-8", 404, "Not Found", emptyMap(), ByteArrayInputStream(byteArrayOf()))
    private fun js(script: String) { runOnUiThread { if (!closed) web.evaluateJavascript(script, null) } }
    private fun error(message: String) = js("window.onNativeError(${JSONObject.quote(message)})")

    inner class Bridge {
        @JavascriptInterface fun report(state: String) { android.util.Log.i("Cimbar", state.take(500)) }
        @JavascriptInterface fun close() { runOnUiThread { finish() } }
        @JavascriptInterface fun setSending(enabled: Boolean) {
            runOnUiThread {
                if (!closed) window.attributes = window.attributes.apply { screenBrightness = if (enabled) 1f else -1f }
            }
        }
        @JavascriptInterface fun pickFile() {
            runOnUiThread {
                if (closed || picking) return@runOnUiThread
                picking = true
                try { startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    type = "*/*"; addCategory(Intent.CATEGORY_OPENABLE)
                }, 6802) } catch (_: Exception) { picking = false; error("无法打开文件选择器") }
            }
        }
        @JavascriptInterface fun beginSave(name: String, size: Int): Boolean = synchronized(saveLock) {
            if (closed || savePending || size < 0 || size > 32 * 1024 * 1024) return@synchronized false
            saveFile?.delete()
            saveFile = File(transferDir, "received.bin")
            try {
                saveFile!!.writeBytes(byteArrayOf()); written = 0; expectedSize = size.toLong()
                saveName = name.replace('\\', '/').substringAfterLast('/').replace(Regex("[\\x00-\\x1f\\x7f]"), "_").take(200).ifBlank { "received.bin" }
                true
            } catch (_: Exception) { false }
        }
        @JavascriptInterface fun writeSaveChunk(encoded: String): Boolean = synchronized(saveLock) {
            if (closed || savePending || encoded.length > 65536) return@synchronized false
            try {
                val file = saveFile ?: return@synchronized false
                val bytes = Base64.decode(encoded, Base64.NO_WRAP)
                if (written + bytes.size > expectedSize) return@synchronized false
                file.appendBytes(bytes); written += bytes.size; true
            } catch (_: Exception) { false }
        }
        @JavascriptInterface fun finishSave() {
            synchronized(saveLock) {
                if (closed || savePending || saveFile == null || written != expectedSize) {
                    error("文件写入未完成，请重新保存"); return
                }
                savePending = true
            }
            runOnUiThread {
                if (!closed) try { startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    type = "application/octet-stream"; addCategory(Intent.CATEGORY_OPENABLE)
                    putExtra(Intent.EXTRA_TITLE, saveName)
                }, 6803) } catch (_: Exception) {
                    synchronized(saveLock) { savePending = false }
                    js("window.onSaveResult(false)")
                }
            }
        }
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, grants: IntArray) {
        super.onRequestPermissionsResult(code, permissions, grants)
        if (code == 6801) {
            if (grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) cameraRequest?.grant(arrayOf(PermissionRequest.RESOURCE_VIDEO_CAPTURE))
            else cameraRequest?.deny()
            cameraRequest = null
        }
    }
    @Deprecated("Activity result dispatch")
    override fun onActivityResult(code: Int, result: Int, intent: Intent?) {
        super.onActivityResult(code, result, intent)
        val uri = intent?.data
        if (code == 6802) {
            picking = false
            if (result != RESULT_OK || uri == null) return
            worker.execute {
                try {
                    var name = "file.bin"
                    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                        if (c.moveToFirst()) name = c.getString(0) ?: name
                    }
                    val file = File(transferDir, "selected-${System.nanoTime()}")
                    try {
                        contentResolver.openInputStream(uri)!!.use { input -> file.outputStream().use { output ->
                            val buffer = ByteArray(65536); var size = 0
                            while (true) { val n = input.read(buffer); if (n < 0) break; size += n
                                require(size <= 16 * 1024 * 1024) { "文件最大支持 16 MB" }; output.write(buffer, 0, n) }
                        } }
                        if (!closed) { val old = selected; selected = file; old?.delete()
                            js("window.onPickedFile(${JSONObject.quote(name)},${JSONObject.quote("$origin/selected-file")})")
                        } else file.delete()
                    } catch (e: Exception) { file.delete(); throw e }
                } catch (e: Exception) { error(e.message ?: "无法读取文件") }
            }
        } else if (code == 6803) {
            if (result != RESULT_OK || uri == null) {
                synchronized(saveLock) { savePending = false }; js("window.onSaveResult(false)"); return
            }
            worker.execute {
                try {
                    val file = synchronized(saveLock) { saveFile } ?: throw IllegalStateException("文件未准备好")
                    contentResolver.openOutputStream(uri, "wt")!!.use { output ->
                        file.inputStream().use { it.copyTo(output) }
                    }
                    js("window.onSaveResult(true)")
                } catch (_: Exception) { js("window.onSaveResult(false)"); error("文件保存失败，请重试") }
                finally { synchronized(saveLock) { savePending = false } }
            }
        }
    }
    override fun onPause() { js("window.pauseTransfer && window.pauseTransfer()"); super.onPause(); web.onPause() }
    override fun onResume() { super.onResume(); if (::web.isInitialized) web.onResume() }
    override fun onDestroy() {
        closed = true; cameraRequest?.deny(); cameraRequest = null
        web.stopLoading(); web.removeJavascriptInterface("CimbarNative"); web.destroy()
        worker.execute { synchronized(saveLock) { transferDir.deleteRecursively() } }; worker.shutdown()
        super.onDestroy()
    }
}
