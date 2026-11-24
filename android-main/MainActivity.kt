package com.hubgitme.aichat

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// MainActivity با کانالِ نیتیوِ «aichat/downloads»: ذخیرهٔ فایل در پوشهٔ
// عمومی Downloads با MediaStore (اندروید ۱۰ به بالا، بدون نیاز به مجوز
// ذخیره‌سازی). جایگزینِ پکیجِ media_store_plus که با SDK 33 ساخته شده
// و با نسخه‌های جدید AndroidX نمی‌سازد.
class MainActivity : FlutterActivity() {
  private val channelName = "aichat/downloads"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
      .setMethodCallHandler { call, result ->
        if (call.method == "saveToDownloads") {
          val bytes = call.argument<ByteArray>("bytes")
          val filename = call.argument<String>("filename")
          val mime = call.argument<String>("mime") ?: "application/octet-stream"
          if (bytes == null || filename == null) {
            result.success(null)
            return@setMethodCallHandler
          }
          result.success(saveToDownloads(bytes, filename, mime))
        } else {
          result.notImplemented()
        }
      }
  }

  private fun saveToDownloads(bytes: ByteArray, filename: String, mime: String): String? {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
    return try {
      val values = ContentValues().apply {
        put(MediaStore.Downloads.DISPLAY_NAME, filename)
        put(MediaStore.Downloads.MIME_TYPE, mime)
        put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
      }
      val uri = contentResolver.insert(
        MediaStore.Downloads.EXTERNAL_CONTENT_URI,
        values,
      ) ?: return null
      contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
      "Downloads/$filename"
    } catch (e: Exception) {
      null
    }
  }
}
