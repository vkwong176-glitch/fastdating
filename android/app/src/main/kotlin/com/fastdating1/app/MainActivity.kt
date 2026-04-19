package com.fastdating1.app

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 允許系統截圖／螢幕錄影：清除視窗 FLAG_SECURE，並對視圖樹內所有 SurfaceView 呼叫 setSecure(false)。
 * 部分外掛／OEM（含部分小米 MIUI）會在子 Surface 保留 secure，僅 clearFlags 仍會黑畫面。
 */
class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.screen_capture",
        ).setMethodCallHandler { call, result ->
            if (call.method == "allowScreenshots") {
                allowScreenshots()
                scheduleAllowScreenshotsDelayed()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        allowScreenshots()
        window?.decorView?.post { allowScreenshots() }
        window?.decorView?.postDelayed({ allowScreenshots() }, 50)
    }

    override fun onStart() {
        super.onStart()
        allowScreenshots()
        scheduleAllowScreenshotsDelayed()
    }

    override fun onResume() {
        super.onResume()
        allowScreenshots()
        scheduleAllowScreenshotsDelayed()
    }

    override fun onPostResume() {
        super.onPostResume()
        allowScreenshots()
        scheduleAllowScreenshotsDelayed()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            allowScreenshots()
            scheduleAllowScreenshotsDelayed()
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        allowScreenshots()
        scheduleAllowScreenshotsDelayed()
    }

    private fun scheduleAllowScreenshotsDelayed() {
        mainHandler.post { allowScreenshots() }
        mainHandler.postDelayed({ allowScreenshots() }, 80)
        mainHandler.postDelayed({ allowScreenshots() }, 300)
        mainHandler.postDelayed({ allowScreenshots() }, 600)
        mainHandler.postDelayed({ allowScreenshots() }, 1200)
        mainHandler.postDelayed({ allowScreenshots() }, 2500)
        mainHandler.postDelayed({ allowScreenshots() }, 5000)
    }

    private fun allowScreenshots() {
        val w = window ?: return
        w.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val attrs = w.attributes
        val mask = WindowManager.LayoutParams.FLAG_SECURE
        if (attrs.flags and mask != 0) {
            attrs.flags = attrs.flags and mask.inv()
            w.attributes = attrs
        }
        clearSecureOnSurfaceViews(w.decorView)
    }

    private fun clearSecureOnSurfaceViews(view: View?) {
        if (view == null) return
        if (view is SurfaceView) {
            view.setSecure(false)
        }
        if (view is ViewGroup) {
            val n = view.childCount
            for (i in 0 until n) {
                clearSecureOnSurfaceViews(view.getChildAt(i))
            }
        }
    }
}
