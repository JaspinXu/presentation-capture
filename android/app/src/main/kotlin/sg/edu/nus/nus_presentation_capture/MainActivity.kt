package sg.edu.nus.nus_presentation_capture

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.StatFs
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val channelName = "sg.edu.nus.presentation_capture/background_upload"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startUploadSession" -> result.success(startUploadSession(call.arguments))
                    "pendingEvents" -> result.success(UploadEventStore.drain(applicationContext))
                    "activeTaskIds" -> activeTaskIds(result)
                    "freeDiskBytes" -> result.success(StatFs(filesDir.path).availableBytes)
                    "scheduleUpload" -> result.success(false)
                    else -> result.notImplemented()
                }
            }
    }

    private fun startUploadSession(rawArguments: Any?): Boolean {
        val arguments = rawArguments as? Map<*, *> ?: return false
        val sessionId = arguments["sessionId"] as? String ?: return false
        val sourcePath = arguments["sourcePath"] as? String ?: return false
        val fileSize = (arguments["fileSize"] as? Number)?.toLong() ?: return false
        val partSize = (arguments["partSize"] as? Number)?.toLong() ?: return false
        val totalParts = (arguments["totalParts"] as? Number)?.toInt() ?: return false
        val partUrlTemplate = arguments["partUrlTemplate"] as? String ?: return false
        val partsUrl = arguments["partsUrl"] as? String ?: return false
        val finalizeUrl = arguments["finalizeUrl"] as? String ?: return false
        val finalizeBody = arguments["finalizeBody"] as? String ?: return false
        val headers = (arguments["headers"] as? Map<*, *>)
            ?.entries
            ?.associate { it.key.toString() to it.value.toString() }
            ?: emptyMap()
        val source = java.io.File(sourcePath)
        if (!source.isFile || source.length() != fileSize || partSize <= 0 || totalParts <= 0) {
            return false
        }

        val allowsCellular = arguments["allowsCellular"] as? Boolean ?: true
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST,
            )
        }
        val request = OneTimeWorkRequestBuilder<UploadWorker>()
            .setInputData(
                workDataOf(
                    UploadWorker.KEY_SESSION_ID to sessionId,
                    UploadWorker.KEY_SOURCE_PATH to sourcePath,
                    UploadWorker.KEY_FILE_SIZE to fileSize,
                    UploadWorker.KEY_PART_SIZE to partSize,
                    UploadWorker.KEY_TOTAL_PARTS to totalParts,
                    UploadWorker.KEY_PART_URL_TEMPLATE to partUrlTemplate,
                    UploadWorker.KEY_PARTS_URL to partsUrl,
                    UploadWorker.KEY_FINALIZE_URL to finalizeUrl,
                    UploadWorker.KEY_FINALIZE_BODY to finalizeBody,
                    UploadWorker.KEY_HEADERS_JSON to JSONObject(headers).toString(),
                ),
            )
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(
                        if (allowsCellular) NetworkType.CONNECTED else NetworkType.UNMETERED,
                    )
                    .build(),
            )
            .addTag(UploadWorker.ALL_UPLOADS_TAG)
            .addTag(UploadWorker.sessionTag(sessionId))
            .build()
        val resetFailed = arguments["resetFailed"] as? Boolean ?: false
        WorkManager.getInstance(applicationContext).enqueueUniqueWork(
            UploadWorker.workName(sessionId),
            if (resetFailed) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP,
            request,
        )
        return true
    }

    private fun activeTaskIds(result: MethodChannel.Result) {
        val future = WorkManager.getInstance(applicationContext)
            .getWorkInfosByTag(UploadWorker.ALL_UPLOADS_TAG)
        Thread {
            try {
                val ids = future.get()
                    .filter { !it.state.isFinished }
                    .mapNotNull { info ->
                        info.tags.firstOrNull { it.startsWith("upload-session:") }
                    }
                    .map { it.removePrefix("upload-session:") }
                runOnUiThread { result.success(ids) }
            } catch (error: Exception) {
                runOnUiThread { result.error("work_manager", error.message, null) }
            }
        }.start()
    }

    companion object {
        private const val NOTIFICATION_PERMISSION_REQUEST = 7103
    }
}
