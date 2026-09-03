package com.example.dabirkhane

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {

        private const val CHANNEL =
            "dabirkhane/scanner"

        private const val SCAN_RESULT_ACTION =
            "ir.haghshenas.dabirkhane.action.SCAN_RESULT"
    }

    private var scannerReceiver: BroadcastReceiver? = null

    private var flutterChannel: MethodChannel? = null

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(
            flutterEngine
        )

        flutterChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        registerScannerReceiver()
    }

    private fun registerScannerReceiver() {

        if (scannerReceiver != null) {
            return
        }

        scannerReceiver =
            object : BroadcastReceiver() {

                override fun onReceive(
                    context: Context?,
                    intent: Intent?
                ) {

                    if (intent == null) {
                        return
                    }

                    val success =
                        intent.getBooleanExtra(
                            "success",
                            false
                        )

                    val cancelled =
                        intent.getBooleanExtra(
                            "cancelled",
                            false
                        )

                    val recordId =
                        intent.getStringExtra(
                            "record_id"
                        )

                    val filePath =
                        intent.getStringExtra(
                            "file_path"
                        )

                    val mimeType =
                        intent.getStringExtra(
                            "mime_type"
                        )

                    flutterChannel?.invokeMethod(
                        "scanResult",
                        mapOf(
                            "success" to success,
                            "cancelled" to cancelled,
                            "record_id" to recordId,
                            "file_path" to filePath,
                            "mime_type" to mimeType,
                        )
                    )
                }
            }

        val filter =
            IntentFilter(
                SCAN_RESULT_ACTION
            )

        if (Build.VERSION.SDK_INT >= 33) {

            registerReceiver(
                scannerReceiver,
                filter,
                Context.RECEIVER_EXPORTED
            )

        } else {

            @Suppress("DEPRECATION")
            registerReceiver(
                scannerReceiver,
                filter
            )
        }
    }

    override fun onDestroy() {

        scannerReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }

        scannerReceiver = null
        flutterChannel = null

        super.onDestroy()
    }
}