package sg.edu.nus.nus_presentation_capture

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL

class UploadWorker(context: Context, parameters: WorkerParameters) :
    CoroutineWorker(context, parameters) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val sessionId = inputData.getString(KEY_SESSION_ID) ?: return@withContext Result.failure()
        val source = File(inputData.getString(KEY_SOURCE_PATH) ?: return@withContext Result.failure())
        val expectedSize = inputData.getLong(KEY_FILE_SIZE, -1)
        val partSize = inputData.getLong(KEY_PART_SIZE, -1)
        val totalParts = inputData.getInt(KEY_TOTAL_PARTS, -1)
        val template = inputData.getString(KEY_PART_URL_TEMPLATE) ?: return@withContext Result.failure()
        val partsUrl = inputData.getString(KEY_PARTS_URL) ?: return@withContext Result.failure()
        val finalizeUrl = inputData.getString(KEY_FINALIZE_URL) ?: return@withContext Result.failure()
        val finalizeBody = inputData.getString(KEY_FINALIZE_BODY) ?: return@withContext Result.failure()
        val headers = jsonMap(inputData.getString(KEY_HEADERS_JSON) ?: "{}")
        if (!source.isFile || source.length() != expectedSize || partSize <= 0 || totalParts <= 0) {
            emit(sessionId, "worker", 0, "Source video is missing or changed")
            return@withContext Result.failure()
        }

        setForeground(createForegroundInfo(0, totalParts))
        try {
            val completed = completedParts(partsUrl, headers)
            for (partNumber in 0 until totalParts) {
                if (isStopped) return@withContext Result.retry()
                if (partNumber !in completed) {
                    val offset = partNumber * partSize
                    val length = minOf(partSize, expectedSize - offset)
                    uploadPart(
                        source,
                        offset,
                        length,
                        template.replace("__PART__", partNumber.toString()),
                        headers,
                    )
                    emit(sessionId, partNumber.toString(), 201, "")
                }
                setProgress(
                    workDataOf(
                        "completedParts" to partNumber + 1,
                        "totalParts" to totalParts,
                    ),
                )
                setForeground(createForegroundInfo(partNumber + 1, totalParts))
            }
            postJson(finalizeUrl, finalizeBody, headers)
            emit(sessionId, "finalize", 200, "")
            Result.success()
        } catch (error: Exception) {
            UploadEventStore.append(
                applicationContext,
                JSONObject()
                    .put("type", "workerRetry")
                    .put("taskId", "$sessionId#worker")
                    .put("statusCode", 0)
                    .put("error", error.message ?: error.javaClass.simpleName),
            )
            if (runAttemptCount >= 14) Result.failure() else Result.retry()
        }
    }

    private fun completedParts(url: String, headers: Map<String, String>): Set<Int> {
        val connection = open(url, "GET", headers)
        return try {
            requireSuccess(connection)
            val payload = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
            val values = payload.getJSONArray("completedParts")
            buildSet {
                for (index in 0 until values.length()) add(values.getInt(index))
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun uploadPart(
        source: File,
        offset: Long,
        length: Long,
        url: String,
        headers: Map<String, String>,
    ) {
        val connection = open(url, "PUT", headers)
        connection.setRequestProperty("Content-Type", "application/octet-stream")
        connection.setFixedLengthStreamingMode(length)
        connection.doOutput = true
        try {
            RandomAccessFile(source, "r").use { input ->
                input.seek(offset)
                connection.outputStream.buffered().use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var remaining = length
                    while (remaining > 0) {
                        val count = input.read(
                            buffer,
                            0,
                            minOf(buffer.size.toLong(), remaining).toInt(),
                        )
                        if (count < 0) error("Unexpected end of video file")
                        output.write(buffer, 0, count)
                        remaining -= count
                    }
                }
            }
            requireSuccess(connection)
        } finally {
            connection.disconnect()
        }
    }

    private fun postJson(url: String, body: String, headers: Map<String, String>) {
        val bytes = body.toByteArray(Charsets.UTF_8)
        val connection = open(url, "POST", headers)
        connection.setRequestProperty("Content-Type", "application/json")
        connection.setFixedLengthStreamingMode(bytes.size)
        connection.doOutput = true
        try {
            connection.outputStream.use { it.write(bytes) }
            requireSuccess(connection)
        } finally {
            connection.disconnect()
        }
    }

    private fun open(url: String, method: String, headers: Map<String, String>): HttpURLConnection {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.requestMethod = method
        connection.connectTimeout = 20_000
        connection.readTimeout = 60_000
        connection.useCaches = false
        for ((key, value) in headers) connection.setRequestProperty(key, value)
        return connection
    }

    private fun requireSuccess(connection: HttpURLConnection) {
        val status = connection.responseCode
        if (status !in 200..299) {
            val detail = connection.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
            error("HTTP $status ${detail.take(300)}")
        }
    }

    private fun emit(sessionId: String, suffix: String, statusCode: Int, error: String) {
        UploadEventStore.append(
            applicationContext,
            JSONObject()
                .put("type", "completed")
                .put("taskId", "$sessionId#$suffix")
                .put("statusCode", statusCode)
                .put("error", error),
        )
    }

    private fun createForegroundInfo(completed: Int, total: Int): ForegroundInfo {
        val manager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Video uploads", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentTitle("Uploading presentation video")
            .setContentText("Part $completed of $total")
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setProgress(total, completed, total <= 0)
            .build()
        return ForegroundInfo(
            NOTIFICATION_ID,
            notification,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
        )
    }

    private fun jsonMap(json: String): Map<String, String> {
        val objectValue = JSONObject(json)
        return buildMap {
            for (key in objectValue.keys()) put(key, objectValue.getString(key))
        }
    }

    companion object {
        const val KEY_SESSION_ID = "sessionId"
        const val KEY_SOURCE_PATH = "sourcePath"
        const val KEY_FILE_SIZE = "fileSize"
        const val KEY_PART_SIZE = "partSize"
        const val KEY_TOTAL_PARTS = "totalParts"
        const val KEY_PART_URL_TEMPLATE = "partUrlTemplate"
        const val KEY_PARTS_URL = "partsUrl"
        const val KEY_FINALIZE_URL = "finalizeUrl"
        const val KEY_FINALIZE_BODY = "finalizeBody"
        const val KEY_HEADERS_JSON = "headersJson"
        const val ALL_UPLOADS_TAG = "presentation-uploads"
        private const val CHANNEL_ID = "presentation_uploads"
        private const val NOTIFICATION_ID = 7102

        fun workName(sessionId: String) = "presentation-upload-$sessionId"
        fun sessionTag(sessionId: String) = "upload-session:$sessionId"
    }
}
