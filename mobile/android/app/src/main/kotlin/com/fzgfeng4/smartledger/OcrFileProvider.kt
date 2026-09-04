package com.fzgfeng4.smartledger

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/** 只暴露 OCR 相机临时目录，供外部相机应用写入应用私有缓存。 */
class OcrFileProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun getType(uri: Uri): String = "image/jpeg"

    override fun query(
        uri: Uri,
        projection: Array<String>?,
        selection: String?,
        selectionArgs: Array<String>?,
        sortOrder: String?,
    ): Cursor {
        val file = resolveFile(uri)
        val columns = projection ?: arrayOf(
            OpenableColumns.DISPLAY_NAME,
            OpenableColumns.SIZE,
        )
        val cursor = MatrixCursor(columns, 1)
        cursor.addRow(
            Array<Any?>(columns.size) { index ->
                when (columns[index]) {
                    OpenableColumns.DISPLAY_NAME -> file.name
                    OpenableColumns.SIZE -> file.length()
                    else -> null
                }
            },
        )
        return cursor
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val flags = when {
            mode.contains("w") || mode.contains("a") ->
                ParcelFileDescriptor.MODE_READ_WRITE
            else -> ParcelFileDescriptor.MODE_READ_ONLY
        }
        return ParcelFileDescriptor.open(resolveFile(uri), flags)
    }

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<String>?): Int {
        return if (resolveFile(uri).delete()) 1 else 0
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? {
        throw UnsupportedOperationException("OCR 临时文件 provider 不支持 insert")
    }

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<String>?,
    ): Int {
        throw UnsupportedOperationException("OCR 临时文件 provider 不支持 update")
    }

    private fun resolveFile(uri: Uri): File {
        val context = context ?: throw FileNotFoundException("OCR 临时文件目录不可用")
        if (uri.authority != authority(context)) {
            throw FileNotFoundException("OCR 临时文件 URI 不属于当前应用")
        }
        val name = uri.pathSegments.singleOrNull()
            ?: throw FileNotFoundException("OCR 临时文件 URI 无效")
        val root = File(context.cacheDir, OCR_DIRECTORY).canonicalFile
        val file = File(root, name).canonicalFile
        val rootPrefix = root.path + File.separator
        if (!file.path.startsWith(rootPrefix)) {
            throw FileNotFoundException("OCR 临时文件路径无效")
        }
        if (!file.isFile) {
            throw FileNotFoundException("OCR 临时图片不存在")
        }
        return file
    }

    companion object {
        private const val OCR_DIRECTORY = "ocr"

        fun authority(context: Context): String {
            return "${context.packageName}.ocr.files"
        }

        fun uriFor(context: Context, file: File): Uri {
            return Uri.Builder()
                .scheme("content")
                .authority(authority(context))
                .appendPath(file.name)
                .build()
        }
    }
}
