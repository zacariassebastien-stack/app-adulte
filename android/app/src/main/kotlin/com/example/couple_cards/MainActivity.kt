package com.example.couple_cards

import android.content.Intent
import android.content.pm.PackageManager
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun getRenderMode(): RenderMode = RenderMode.texture

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "couple_cards/media_capabilities")
            .setMethodCallHandler { call, result ->
                if (call.method != "captureCapabilities") {
                    result.notImplemented()
                } else {
                    val hasCamera = packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
                    val capabilities = mutableListOf<String>()
                    if (hasCamera && Intent(MediaStore.ACTION_IMAGE_CAPTURE).resolveActivity(packageManager) != null) {
                        capabilities.add("PHOTO_CAPTURE")
                    }
                    if (hasCamera && Intent(MediaStore.ACTION_VIDEO_CAPTURE).resolveActivity(packageManager) != null) {
                        capabilities.add("RECORDED_VIDEO")
                    }
                    result.success(capabilities)
                }
            }
    }
}
