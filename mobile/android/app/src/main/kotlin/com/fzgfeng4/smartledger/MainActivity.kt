package com.fzgfeng4.smartledger

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import java.util.UUID

class MainActivity : FlutterActivity() {
    private var pendingPickerResult: MethodChannel.Result? = null
    private var pendingOcrPicker: PendingOcrPicker? = null
    private var pendingOcrRecognition: PendingOcrRecognition? = null
    private var cameraPermissionRequested = false

    private data class NativeOcrInput(
        val requestId: String,
        val sourceType: String,
        val locator: String? = null,
        val displayName: String? = null,
        val originalImagePolicy: String = "discard_after_processing",
    )

    private data class PendingOcrPicker(
        val input: NativeOcrInput,
        val result: MethodChannel.Result,
        var cameraFile: File? = null,
    )

    private data class PendingOcrRecognition(
        val input: NativeOcrInput,
        val result: MethodChannel.Result,
        val recognizer: TextRecognizer,
        val cleanupFile: File?,
        val forceCleanup: Boolean,
    )

    private data class PreparedImage(
        val uri: Uri,
        val cleanupFile: File?,
        val forceCleanup: Boolean,
    )

    private class ImageInputException(message: String) : Exception(message)

    private class CsvInputTooLargeException : Exception()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FILE_PICKER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickCsv" -> launchCsvPicker(result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            OCR_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickAndRecognize" -> launchOcrPicker(call.arguments, result)
                "recognize" -> recognizeOcr(call.arguments, result)
                "cancel" -> cancelOcr(result)
                "openAppSettings" -> openAppSettings(result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == OCR_PICK_REQUEST_CODE) {
            handleOcrPickerResult(resultCode, data)
            return
        }
        if (requestCode != PICK_CSV_REQUEST_CODE) {
            return
        }

        val result = pendingPickerResult ?: return
        pendingPickerResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }

        val uri = data.data ?: run {
            result.success(null)
            return
        }
        try {
            val bytes = readCsvBytes(uri)
            result.success(
                mapOf(
                    "fileName" to displayName(uri),
                    "bytes" to bytes,
                ),
            )
        } catch (_: CsvInputTooLargeException) {
            result.error(
                "FILE_TOO_LARGE",
                "CSV 文件超过 10 MB 大小上限，请拆分账单后重试。",
                null,
            )
        } catch (error: Exception) {
            result.error(
                "READ_FAILED",
                error.message ?: "读取所选文件失败",
                null,
            )
        }
    }

    private fun launchCsvPicker(result: MethodChannel.Result) {
        if (pendingPickerResult != null) {
            result.error("PICKER_BUSY", "文件选择器正在打开", null)
            return
        }

        pendingPickerResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "text/csv",
                    "text/comma-separated-values",
                    "application/vnd.ms-excel",
                    "text/plain",
                ),
            )
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, PICK_CSV_REQUEST_CODE)
        } catch (error: Exception) {
            pendingPickerResult = null
            result.error(
                "PICKER_UNAVAILABLE",
                error.message ?: "无法打开文件选择器",
                null,
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != OCR_CAMERA_PERMISSION_REQUEST_CODE) {
            return
        }

        val pending = pendingOcrPicker ?: return
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            launchCameraPicker(pending)
            return
        }

        pendingOcrPicker = null
        deleteCameraFile(pending.cameraFile)
        pending.result.success(
            permissionDeniedPayload(
                input = pending.input,
                permanentlyDenied = !shouldShowRequestPermissionRationale(
                    Manifest.permission.CAMERA,
                ),
            ),
        )
    }

    override fun onDestroy() {
        val pendingPicker = pendingOcrPicker
        if (pendingPicker != null) {
            pendingOcrPicker = null
            deleteCameraFile(pendingPicker.cameraFile)
            pendingPicker.result.success(cancelledPayload(pendingPicker.input))
        }

        val pendingRecognition = pendingOcrRecognition
        if (pendingRecognition != null) {
            pendingOcrRecognition = null
            pendingRecognition.recognizer.close()
            cleanupRecognitionFile(
                pendingRecognition.cleanupFile,
                pendingRecognition.input,
                pendingRecognition.forceCleanup,
            )
            pendingRecognition.result.success(cancelledPayload(pendingRecognition.input))
        }
        super.onDestroy()
    }

    private fun launchOcrPicker(arguments: Any?, result: MethodChannel.Result) {
        val values = arguments as? Map<*, *>
        val requestId = (values?.get("request_id") as? String)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: "ocr-invalid-request"
        val sourceType = normalizeSourceType(values?.get("source_type") as? String)
        val input = NativeOcrInput(
            requestId = requestId,
            sourceType = sourceType,
            originalImagePolicy =
                (values?.get("original_image_policy") as? String)
                    ?.trim()
                    ?.ifEmpty { "discard_after_processing" }
                    ?: "discard_after_processing",
        )

        if (sourceType != "camera" && sourceType != "gallery") {
            result.success(
                failurePayload(
                    input = input,
                    status = "failed",
                    code = "invalid_input",
                    message = "图片选择来源必须是相机或相册。",
                    retryable = false,
                ),
            )
            return
        }
        if (pendingOcrPicker != null || pendingOcrRecognition != null) {
            result.success(
                failurePayload(
                    input = input,
                    status = "failed",
                    code = "provider_unavailable",
                    message = "已有 OCR 请求正在处理。",
                    retryable = true,
                ),
            )
            return
        }

        val pending = PendingOcrPicker(input = input, result = result)
        pendingOcrPicker = pending
        if (sourceType == "camera" &&
            checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED
        ) {
            if (cameraPermissionRequested &&
                !shouldShowRequestPermissionRationale(Manifest.permission.CAMERA)
            ) {
                pendingOcrPicker = null
                result.success(permissionDeniedPayload(input, permanentlyDenied = true))
                return
            }
            try {
                cameraPermissionRequested = true
                requestPermissions(
                    arrayOf(Manifest.permission.CAMERA),
                    OCR_CAMERA_PERMISSION_REQUEST_CODE,
                )
            } catch (error: Exception) {
                logOcrFailure("request_camera_permission", error)
                pendingOcrPicker = null
                result.success(
                    failurePayload(
                        input = input,
                        status = "permission_denied",
                        code = "permission_denied",
                        message = "无法请求相机权限，请稍后重试。",
                        retryable = false,
                    ),
                )
            }
            return
        }

        if (sourceType == "camera") {
            launchCameraPicker(pending)
        } else {
            launchGalleryPicker(pending)
        }
    }

    private fun launchGalleryPicker(pending: PendingOcrPicker) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, OCR_PICK_REQUEST_CODE)
        } catch (error: Exception) {
            logOcrFailure("open_gallery_picker", error)
            if (pendingOcrPicker === pending) {
                pendingOcrPicker = null
                pending.result.success(
                    failurePayload(
                        input = pending.input,
                        status = "failed",
                        code = "provider_unavailable",
                        message = "无法打开相册选择器，请稍后重试。",
                        retryable = true,
                    ),
                )
            }
        }
    }

    private fun launchCameraPicker(pending: PendingOcrPicker) {
        val cameraFile = try {
            createCameraFile()
        } catch (error: Exception) {
            logOcrFailure("create_camera_file", error)
            if (pendingOcrPicker === pending) {
                pendingOcrPicker = null
                pending.result.success(
                    failurePayload(
                        input = pending.input,
                        status = "failed",
                        code = "provider_unavailable",
                        message = "无法准备相机临时文件，请稍后重试。",
                        retryable = true,
                    ),
                )
            }
            return
        }

        pending.cameraFile = cameraFile
        val uri = OcrFileProvider.uriFor(this, cameraFile)
        val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
            putExtra(MediaStore.EXTRA_OUTPUT, uri)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            clipData = ClipData.newRawUri("ocr_capture", uri)
        }
        try {
            startActivityForResult(intent, OCR_PICK_REQUEST_CODE)
        } catch (error: Exception) {
            logOcrFailure("open_camera", error)
            if (pendingOcrPicker === pending) {
                pendingOcrPicker = null
                deleteCameraFile(cameraFile)
                pending.result.success(
                    failurePayload(
                        input = pending.input,
                        status = "failed",
                        code = "provider_unavailable",
                        message = "无法打开相机，请检查相机权限后重试。",
                        retryable = true,
                    ),
                )
            } else {
                deleteCameraFile(cameraFile)
            }
        }
    }

    private fun createCameraFile(): File {
        val directory = File(cacheDir, "ocr")
        if (!directory.isDirectory && !directory.mkdirs()) {
            throw IllegalStateException("无法创建 OCR 临时目录")
        }
        return File(directory, "capture_${UUID.randomUUID()}.jpg").also {
            if (!it.createNewFile()) {
                throw IllegalStateException("无法创建 OCR 临时图片")
            }
        }
    }

    private fun handleOcrPickerResult(resultCode: Int, data: Intent?) {
        val pending = pendingOcrPicker ?: return
        pendingOcrPicker = null
        if (resultCode != Activity.RESULT_OK) {
            deleteCameraFile(pending.cameraFile)
            pending.result.success(cancelledPayload(pending.input))
            return
        }

        if (pending.input.sourceType == "camera") {
            val file = pending.cameraFile
            if (file == null || !file.isFile || file.length() <= 0L) {
                deleteCameraFile(file)
                pending.result.success(
                    failurePayload(
                        input = pending.input,
                        status = "failed",
                        code = "invalid_input",
                        message = "相机没有生成可读取的图片。",
                        retryable = true,
                    ),
                )
                return
            }
            val input = pending.input.copy(
                locator = OcrFileProvider.uriFor(this, file).toString(),
                displayName = file.name,
            )
            startRecognition(input, pending.result, file)
            return
        }

        val uri = data?.data
        if (uri == null) {
            pending.result.success(
                failurePayload(
                    input = pending.input,
                    status = "failed",
                    code = "invalid_input",
                    message = "没有收到所选图片。",
                    retryable = false,
                ),
            )
            return
        }
        val input = pending.input.copy(
            locator = uri.toString(),
            displayName = displayName(uri, "图片"),
        )
        startRecognition(input, pending.result, null)
    }

    private fun recognizeOcr(arguments: Any?, result: MethodChannel.Result) {
        val values = arguments as? Map<*, *>
        val source = values?.get("source") as? Map<*, *>
        val input = NativeOcrInput(
            requestId =
                (values?.get("request_id") as? String)
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
                    ?: "ocr-invalid-request",
            sourceType = normalizeSourceType(source?.get("type") as? String),
            locator = (source?.get("ephemeral_locator") as? String)?.trim(),
            displayName = (source?.get("display_name") as? String)?.trim(),
            originalImagePolicy =
                (values?.get("original_image_policy") as? String)
                    ?.trim()
                    ?.ifEmpty { "discard_after_processing" }
                    ?: "discard_after_processing",
        )
        startRecognition(input, result, null)
    }

    private fun startRecognition(
        input: NativeOcrInput,
        result: MethodChannel.Result,
        cleanupFile: File?,
    ) {
        if (pendingOcrPicker != null || pendingOcrRecognition != null) {
            cleanupOwnedFile(cleanupFile, input)
            result.success(
                failurePayload(
                    input = input,
                    status = "failed",
                    code = "provider_unavailable",
                    message = "已有 OCR 请求正在处理。",
                    retryable = true,
                ),
            )
            return
        }

        val locator = input.locator?.trim()
        if (locator.isNullOrEmpty()) {
            cleanupOwnedFile(cleanupFile, input)
            result.success(
                failurePayload(
                    input = input,
                    status = "failed",
                    code = "invalid_input",
                    message = "没有可读取的图片定位信息。",
                    retryable = false,
                ),
            )
            return
        }

        var preparedImage: PreparedImage? = null
        val image = try {
            preparedImage = prepareImage(locator, cleanupFile)
            InputImage.fromFilePath(this, preparedImage!!.uri)
        } catch (error: Exception) {
            val prepared = preparedImage
            if (prepared == null) {
                cleanupOwnedFile(cleanupFile, input)
            } else {
                cleanupPreparedImage(prepared, input)
            }
            result.success(
                failurePayload(
                    input = input,
                    status = "failed",
                    code = "invalid_input",
                    message = if (error is ImageInputException) {
                        error.message ?: "图片不存在或无法读取。"
                    } else {
                        logOcrFailure("prepare_image", error)
                        "图片不存在或无法读取，请重新选择清晰图片。"
                    },
                    retryable = false,
                ),
            )
            return
        }

        val recognizer = try {
            TextRecognition.getClient(
                ChineseTextRecognizerOptions.Builder().build(),
            )
        } catch (error: Exception) {
            logOcrFailure("initialize_recognizer", error)
            cleanupPreparedImage(preparedImage!!, input)
            result.success(
                failurePayload(
                    input = input,
                    status = "failed",
                    code = "provider_unavailable",
                    message = "本地 OCR 模型暂时不可用，请稍后重试。",
                    retryable = true,
                ),
            )
            return
        }

        val request = PendingOcrRecognition(
            input = input,
            result = result,
            recognizer = recognizer,
            cleanupFile = preparedImage!!.cleanupFile,
            forceCleanup = preparedImage!!.forceCleanup,
        )
        pendingOcrRecognition = request
        try {
            recognizer.process(image)
                .addOnSuccessListener { visionText ->
                    completeRecognition(request, visionPayload(input, visionText))
                }
                .addOnFailureListener { error ->
                    completeRecognition(
                        request,
                        failurePayload(
                            input = input,
                            status = "failed",
                            code = "recognition_failed",
                            message = recognitionFailureMessage(error),
                            retryable = true,
                        ),
                    )
                }
        } catch (error: Exception) {
            completeRecognition(
                request,
                failurePayload(
                    input = input,
                    status = "failed",
                    code = "recognition_failed",
                    message = recognitionFailureMessage(error),
                    retryable = true,
                ),
            )
        }
    }

    private fun completeRecognition(
        request: PendingOcrRecognition,
        payload: Map<String, Any?>,
    ) {
        if (pendingOcrRecognition !== request) {
            return
        }
        pendingOcrRecognition = null
        request.recognizer.close()
        cleanupRecognitionFile(request.cleanupFile, request.input, request.forceCleanup)
        request.result.success(payload)
    }

    private fun cancelOcr(result: MethodChannel.Result) {
        val picker = pendingOcrPicker
        if (picker != null) {
            pendingOcrPicker = null
            try {
                finishActivity(OCR_PICK_REQUEST_CODE)
            } catch (_: Exception) {
                // 外部选择器可能已经自行结束。
            }
            deleteCameraFile(picker.cameraFile)
            picker.result.success(cancelledPayload(picker.input))
            result.success(true)
            return
        }

        val recognition = pendingOcrRecognition
        if (recognition != null) {
            pendingOcrRecognition = null
            recognition.recognizer.close()
            cleanupRecognitionFile(
                recognition.cleanupFile,
                recognition.input,
                recognition.forceCleanup,
            )
            recognition.result.success(cancelledPayload(recognition.input))
            result.success(true)
            return
        }
        result.success(false)
    }

    private fun visionPayload(input: NativeOcrInput, visionText: Text): Map<String, Any?> {
        val lineConfidences = mutableListOf<Double>()
        val blocks = visionText.textBlocks.mapIndexed { blockIndex, block ->
            val blockLineConfidences = mutableListOf<Double>()
            val lines = block.lines.mapIndexed { lineIndex, line ->
                val confidence = safeConfidence(line.confidence)
                lineConfidences += confidence
                blockLineConfidences += confidence
                mapOf<String, Any?>(
                    "text" to line.text,
                    "confidence" to mapOf<String, Any?>("value" to confidence),
                    "line_index" to lineIndex,
                )
            }
            val blockConfidence = if (lines.isEmpty()) {
                0.0
            } else {
                blockLineConfidences.average()
            }
            mapOf<String, Any?>(
                "block_index" to blockIndex,
                "confidence" to mapOf<String, Any?>("value" to blockConfidence),
                "lines" to lines,
            )
        }

        val recognizedText = visionText.text
        val overallConfidence = lineConfidences.takeIf { it.isNotEmpty() }?.average()
        val hasText = recognizedText.trim().isNotEmpty()
        val status = when {
            !hasText -> "empty_text"
            overallConfidence != null && overallConfidence < LOW_CONFIDENCE_THRESHOLD ->
                "low_confidence"
            else -> "success"
        }
        val issues = mutableListOf<Map<String, Any?>>()
        if (!hasText) {
            issues += candidateIssue(
                code = "empty_text",
                severity = "warning",
                message = "图片中没有识别到可用文本。",
            )
        } else if (status == "low_confidence") {
            issues += candidateIssue(
                code = "low_confidence",
                severity = "warning",
                message = "识别置信度较低，请核对原始图片。",
            )
        }

        return mapOf(
            "request_id" to input.requestId,
            "source" to sourcePayload(input),
            "status" to status,
            "recognized_text" to recognizedText,
            "blocks" to blocks,
            "confidence" to overallConfidence?.let { mapOf("value" to it) },
            "candidate_issues" to issues,
            "failure_reason" to null,
            "completed_at" to null,
        )
    }

    private fun candidateIssue(
        code: String,
        severity: String,
        message: String,
    ): Map<String, Any?> {
        return mapOf(
            "code" to code,
            "severity" to severity,
            "message" to message,
            "fragment" to null,
            "block_index" to null,
            "line_index" to null,
            "candidates" to emptyList<String>(),
        )
    }

    private fun failurePayload(
        input: NativeOcrInput,
        status: String,
        code: String,
        message: String,
        retryable: Boolean,
    ): Map<String, Any?> {
        return mapOf(
            "request_id" to input.requestId,
            "source" to sourcePayload(input),
            "status" to status,
            "recognized_text" to "",
            "blocks" to emptyList<Any?>(),
            "confidence" to null,
            "candidate_issues" to emptyList<Any?>(),
            "failure_reason" to mapOf(
                "code" to code,
                "message" to message,
                "retryable" to retryable,
            ),
            "completed_at" to null,
        )
    }

    private fun permissionDeniedPayload(
        input: NativeOcrInput,
        permanentlyDenied: Boolean,
    ): Map<String, Any?> {
        return failurePayload(
            input = input,
            status = "permission_denied",
            code = "permission_denied",
            message = if (permanentlyDenied) {
                "相机权限已被关闭，请打开系统设置允许相机权限后重试。"
            } else {
                "未获得相机权限，请允许后重试。"
            },
            retryable = false,
        )
    }

    private fun cancelledPayload(input: NativeOcrInput): Map<String, Any?> {
        return failurePayload(
            input = input,
            status = "cancelled",
            code = "cancelled",
            message = "用户取消了图片选择或 OCR 识别。",
            retryable = false,
        )
    }

    private fun sourcePayload(input: NativeOcrInput): Map<String, Any?> {
        return mapOf(
            "type" to input.sourceType,
            "ephemeral_locator" to input.locator,
            "display_name" to input.displayName,
            "captured_at" to null,
        )
    }

    private fun toImageUri(locator: String): Uri {
        val parsed = Uri.parse(locator)
        return if (parsed.scheme.isNullOrEmpty()) Uri.fromFile(File(locator)) else parsed
    }

    private fun normalizeSourceType(value: String?): String {
        return when (value?.trim()?.lowercase(Locale.ROOT)) {
            "camera" -> "camera"
            "gallery" -> "gallery"
            "file" -> "file"
            "uri" -> "uri"
            else -> "unknown"
        }
    }

    private fun safeConfidence(value: Float): Double {
        return if (value.isFinite()) value.toDouble().coerceIn(0.0, 1.0) else 0.0
    }

    private fun cleanupOwnedFile(file: File?, input: NativeOcrInput) {
        if (file != null && input.originalImagePolicy != "caller_managed") {
            deleteCameraFile(file)
        }
    }

    private fun cleanupPreparedImage(image: PreparedImage, input: NativeOcrInput) {
        cleanupRecognitionFile(image.cleanupFile, input, image.forceCleanup)
    }

    private fun cleanupRecognitionFile(
        file: File?,
        input: NativeOcrInput,
        forceCleanup: Boolean,
    ) {
        if (file != null &&
            (forceCleanup || input.originalImagePolicy != "caller_managed")
        ) {
            deleteCameraFile(file)
        }
    }

    private fun readCsvBytes(uri: Uri): ByteArray {
        val declaredSize = querySize(uri)
        if (declaredSize > MAX_CSV_BYTES) {
            throw CsvInputTooLargeException()
        }
        val initialSize = if (declaredSize in 0..MAX_CSV_BYTES) {
            declaredSize.toInt()
        } else {
            8192
        }
        val output = ByteArrayOutputStream(initialSize)
        val input = contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("无法读取所选文件")
        input.use { stream ->
            val buffer = ByteArray(8192)
            var total = 0L
            while (true) {
                val read = stream.read(buffer)
                if (read < 0) {
                    break
                }
                total += read
                if (total > MAX_CSV_BYTES) {
                    throw CsvInputTooLargeException()
                }
                output.write(buffer, 0, read)
            }
        }
        return output.toByteArray()
    }

    private fun prepareImage(locator: String, cameraFile: File?): PreparedImage {
        val uri = toImageUri(locator)
        if (cameraFile != null) {
            validateImage(uri)
            return PreparedImage(uri, cameraFile, forceCleanup = false)
        }

        val copiedFile = createOcrTempFile("selected")
        try {
            copyImageToFile(uri, copiedFile)
            val copiedUri = Uri.fromFile(copiedFile)
            validateImage(copiedUri)
            return PreparedImage(copiedUri, copiedFile, forceCleanup = true)
        } catch (error: Exception) {
            deleteCameraFile(copiedFile)
            if (error is ImageInputException) {
                throw error
            }
            logOcrFailure("copy_image", error)
            throw ImageInputException("图片不存在或无法读取。")
        }
    }

    private fun recognitionFailureMessage(error: Throwable): String {
        logOcrFailure("recognition", error)
        val detail = error.message?.lowercase(Locale.ROOT).orEmpty()
        return when {
            detail.contains("model") || detail.contains("module") ->
                "本地 OCR 模型暂时不可用，请稍后重试。"
            detail.contains("image") || detail.contains("bitmap") ->
                "图片无法解析，请重新选择清晰图片后重试。"
            else -> "本地 OCR 识别失败，请更换清晰图片后重试。"
        }
    }

    private fun logOcrFailure(stage: String, error: Throwable) {
        Log.e(OCR_LOG_TAG, "OCR $stage failed: ${error::class.java.name}", error)
    }

    private fun copyImageToFile(uri: Uri, target: File) {
        val declaredSize = querySize(uri)
        if (declaredSize > MAX_OCR_IMAGE_BYTES) {
            throw ImageInputException("图片超过 15 MB 大小上限，请选择较小的图片。")
        }
        val input = contentResolver.openInputStream(uri)
            ?: throw ImageInputException("图片不存在或无法读取。")
        input.use { stream ->
            FileOutputStream(target).use { output ->
                val buffer = ByteArray(8192)
                var total = 0L
                while (true) {
                    val read = stream.read(buffer)
                    if (read < 0) {
                        break
                    }
                    total += read
                    if (total > MAX_OCR_IMAGE_BYTES) {
                        throw ImageInputException("图片超过 15 MB 大小上限，请选择较小的图片。")
                    }
                    output.write(buffer, 0, read)
                }
                if (total <= 0L) {
                    throw ImageInputException("图片不存在或无法读取。")
                }
            }
        }
    }

    private fun validateImage(uri: Uri) {
        val size = querySize(uri)
        if (size > MAX_OCR_IMAGE_BYTES) {
            throw ImageInputException("图片超过 15 MB 大小上限，请选择较小的图片。")
        }
        val options = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        val input = contentResolver.openInputStream(uri)
            ?: throw ImageInputException("图片不存在或无法读取。")
        input.use { stream ->
            BitmapFactory.decodeStream(stream, null, options)
        }
        val width = options.outWidth
        val height = options.outHeight
        if (width <= 0 || height <= 0) {
            throw ImageInputException("图片格式无效或无法读取。")
        }
        val pixels = width.toLong() * height.toLong()
        if (width > MAX_OCR_IMAGE_DIMENSION ||
            height > MAX_OCR_IMAGE_DIMENSION ||
            pixels > MAX_OCR_IMAGE_PIXELS
        ) {
            throw ImageInputException("图片尺寸过大，请选择清晰但尺寸较小的图片。")
        }
    }

    private fun createOcrTempFile(prefix: String): File {
        val directory = File(cacheDir, "ocr")
        if (!directory.isDirectory && !directory.mkdirs()) {
            throw IllegalStateException("无法创建 OCR 临时目录")
        }
        return File(directory, "${prefix}_${UUID.randomUUID()}.img").also {
            if (!it.createNewFile()) {
                throw IllegalStateException("无法创建 OCR 临时图片")
            }
        }
    }

    private fun querySize(uri: Uri): Long {
        if (uri.scheme == "file") {
            return File(uri.path ?: return -1L).length()
        }
        return try {
            val cursor = contentResolver.query(
                uri,
                arrayOf(OpenableColumns.SIZE),
                null,
                null,
                null,
            )
            cursor.use {
                if (it != null && it.moveToFirst()) {
                    val index = it.getColumnIndex(OpenableColumns.SIZE)
                    if (index >= 0 && !it.isNull(index)) {
                        return it.getLong(index)
                    }
                }
                -1L
            }
        } catch (_: Exception) {
            -1L
        }
    }

    private fun openAppSettings(result: MethodChannel.Result) {
        try {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                },
            )
            result.success(true)
        } catch (_: Exception) {
            result.success(false)
        }
    }

    private fun deleteCameraFile(file: File?) {
        if (file?.exists() == true) {
            file.delete()
        }
    }

    private fun displayName(uri: Uri, fallback: String = "账单.csv"): String {
        val projection = arrayOf(OpenableColumns.DISPLAY_NAME)
        val cursor: Cursor? = contentResolver.query(uri, projection, null, null, null)
        cursor.use {
            if (it != null && it.moveToFirst()) {
                val index = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) {
                    val name = it.getString(index)?.trim()
                    if (!name.isNullOrEmpty()) {
                        return name
                    }
                }
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/')?.ifBlank { null }
            ?: fallback
    }

    companion object {
        private const val OCR_LOG_TAG = "SmartLedgerOCR"
        private const val FILE_PICKER_CHANNEL = "smartledger/import_file"
        private const val OCR_CHANNEL = "smartledger/ocr"
        private const val PICK_CSV_REQUEST_CODE = 4107
        private const val OCR_PICK_REQUEST_CODE = 4108
        private const val OCR_CAMERA_PERMISSION_REQUEST_CODE = 4109
        private const val LOW_CONFIDENCE_THRESHOLD = 0.7
        private const val MAX_CSV_BYTES = 10L * 1024L * 1024L
        private const val MAX_OCR_IMAGE_BYTES = 15L * 1024L * 1024L
        private const val MAX_OCR_IMAGE_DIMENSION = 12000
        private const val MAX_OCR_IMAGE_PIXELS = 40_000_000L
    }
}
