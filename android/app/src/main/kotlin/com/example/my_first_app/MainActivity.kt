package com.example.my_first_app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import kotlin.math.max

class MainActivity : FlutterActivity() {
    private val ocrExecutor = Executors.newSingleThreadExecutor()

    /**
     * Back on the first screen sends the app to the background instead of
     * finishing the activity, so reopening it from Recents resumes the same
     * screen without reloading. Inner screens and dialogs still pop normally.
     */
    override fun popSystemNavigator(): Boolean {
        moveTaskToBack(true)
        return true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hotel_pro/ocr")
            .setMethodCallHandler { call, result ->
                if (call.method != "recognizeText") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.arguments as? String
                if (path.isNullOrBlank()) {
                    result.success("")
                    return@setMethodCallHandler
                }
                ocrExecutor.execute {
                    val text = try {
                        recognizeBest(path)
                    } catch (_: Exception) {
                        ""
                    }
                    runOnUiThread { result.success(text) }
                }
            }
    }

    private fun recognizeBest(path: String): String {
        val original = loadBitmap(path) ?: return ""
        val latin = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        val hindi = TextRecognition.getClient(
            DevanagariTextRecognizerOptions.Builder().build(),
        )
        try {
            var best = ""
            var bestScore = -1
            for (deg in listOf(0, 90, 180, 270)) {
                val bitmap = if (deg == 0) original else rotate(original, deg.toFloat())
                try {
                    val image = InputImage.fromBitmap(bitmap, 0)
                    val latinText = runCatching {
                        Tasks.await(latin.process(image)).text
                    }.getOrDefault("")
                    val hindiText = runCatching {
                        Tasks.await(hindi.process(image)).text
                    }.getOrDefault("")
                    for (text in listOf(latinText, hindiText, mergeTexts(latinText, hindiText))) {
                        val score = scoreOcr(text)
                        if (score > bestScore) {
                            bestScore = score
                            best = text
                        }
                    }
                    if (deg == 0 && bestScore >= 30) {
                        break
                    }
                } finally {
                    if (bitmap !== original) {
                        bitmap.recycle()
                    }
                }
            }
            return best
        } finally {
            latin.close()
            hindi.close()
            original.recycle()
        }
    }

    private fun loadBitmap(path: String): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        var sample = 1
        val longest = max(bounds.outWidth, bounds.outHeight)
        while (longest / sample > 2400) {
            sample *= 2
        }
        return BitmapFactory.decodeFile(
            path,
            BitmapFactory.Options().apply { inSampleSize = sample },
        )
    }

    private fun rotate(source: Bitmap, degrees: Float): Bitmap {
        val matrix = Matrix().apply { postRotate(degrees) }
        return Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
    }

    private fun mergeTexts(first: String, second: String): String {
        val lines = LinkedHashSet<String>()
        for (line in "$first\n$second".split('\n')) {
            val trimmed = line.trim()
            if (trimmed.isNotEmpty()) {
                lines.add(trimmed)
            }
        }
        return lines.joinToString("\n")
    }

    private fun scoreOcr(text: String): Int {
        if (text.isBlank()) {
            return -1
        }
        val lower = text.lowercase()
        var score = text.length / 20
        if (Regex("aadhaar|aadhar|uidai|government|भारत|आधार").containsMatchIn(lower)) {
            score += 10
        }
        if (Regex("address|s/o|d/o|w/o|पता").containsMatchIn(lower)) {
            score += 8
        }
        if (Regex("(?<![0-9])[2-9]\\d{3}[\\s-]*\\d{4}[\\s-]*\\d{4}(?![0-9])").containsMatchIn(text)) {
            score += 16
        }
        if (Regex("\\b\\d{6}\\b").containsMatchIn(text)) {
            score += 4
        }
        return score
    }
}
