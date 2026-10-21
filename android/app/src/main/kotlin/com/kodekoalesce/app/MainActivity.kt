package com.kodekoalesce.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.kodekoalesce.app/share"
        ).setMethodCallHandler { call, result ->
            if (call.method == "openUrl") {
                val url = call.argument<String>("url")
                val uri = android.net.Uri.parse(url ?: "")
                if (url.isNullOrBlank() ||
                    (uri.scheme != "https" && uri.scheme != "http") ||
                    uri.host.isNullOrBlank()
                ) {
                    result.error("invalid_url", "A valid web URL is required.", null)
                    return@setMethodCallHandler
                }
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, uri))
                    result.success(null)
                } catch (error: Exception) {
                    result.error("cannot_open_url", "No browser could open this link.", null)
                }
                return@setMethodCallHandler
            }

            if (call.method != "shareText") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val text = call.argument<String>("text")
            if (text.isNullOrBlank()) {
                result.error("empty_text", "There is no post text to share.", null)
                return@setMethodCallHandler
            }

            val title = call.argument<String>("title") ?: "Share post"
            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
            }
            startActivity(Intent.createChooser(sendIntent, title))
            result.success(null)
        }
    }
}
