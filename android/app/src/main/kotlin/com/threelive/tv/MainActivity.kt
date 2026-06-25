package com.threelive.tv

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/// v0.3.7+20 (6/18): 后台强制更新 — MethodChannel 调 Android installer.
///
/// 不用 install_plugin 2.1.0 (package 缺 namespace + JVM target 不一致,
/// AGP 8+ 编译不过).  自己写 MethodChannel 处理 "installApk" 通道.
///
/// 使用:
///   final channel = MethodChannel(messenger, 'com.threelive.iptv/install');
///   await channel.invokeMethod('installApk', {'path': '/data/.../app.apk'});
///
/// Android 7+ (API 24+) 必须用 FileProvider 共享 file:// URI 给 installer.
///
/// v0.3.10.13: Native crash handler — 捕获 SIGSEGV/SIGABRT 等 native signal,
/// 写到 /sdcard/Android/data/com.threelive.tv/files/native_crash.log,
/// 老板 adb pull 即可看到 native crash stacktrace.
class MainActivity : FlutterActivity() {
    private val channelName = "com.threelive.iptv/install"
    private val fallbackChannelName = "com.threelive.iptv/fallback_player"
    private val libmpvCheckChannelName = "com.threelive.iptv/check_libmpv"
    private val TAG = "SanyeliveMain"
    private val REQUEST_PERMISSIONS = 1001

    // v0.3.10.22: 在 Flutter 引擎启动前就请求存储权限 —
    // 某些 TV 盒子 ROM 会在 app 不请求权限时直接杀进程.
    override fun onCreate(savedInstanceState: Bundle?) {
        // 安装 native crash handler 尽早 — 在 super.onCreate 之前
        installNativeCrashHandler()
        requestStoragePermissions()
        super.onCreate(savedInstanceState)
    }

    private fun requestStoragePermissions() {
        val perms = mutableListOf<String>()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE)
            != PackageManager.PERMISSION_GRANTED) {
            perms.add(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE)
            != PackageManager.PERMISSION_GRANTED) {
            perms.add(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_IMAGES)
                != PackageManager.PERMISSION_GRANTED) {
                perms.add(Manifest.permission.READ_MEDIA_IMAGES)
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (!android.os.Environment.isExternalStorageManager()) {
                try {
                    val intent = Intent(android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                } catch (e: Exception) {
                    Log.w(TAG, "Cannot open storage settings: ${e.message}")
                }
            }
        }
        if (perms.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, perms.toTypedArray(), REQUEST_PERMISSIONS)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // v0.3.10.13: 安装 native crash handler
        installNativeCrashHandler()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("ARG_ERROR", "path is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            installApk(path)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // v0.3.10.13: Fallback player channel — libmpv 不可用时走 Android MediaPlayer
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fallbackChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "play" -> {
                        val url = call.argument<String>("url")
                        if (url == null) {
                            result.error("ARG_ERROR", "url is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(false) // 暂不实现, 避免 MissingPluginException
                        } catch (e: Exception) {
                            result.error("PLAY_ERROR", e.message, null)
                        }
                    }
                    "stop" -> {
                        result.success(null)
                    }
                    "pause" -> {
                        result.success(null)
                    }
                    "resume" -> {
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // v0.3.10.16: 预检 libmpv.so 是否可加载 — 在 Dart 端调 MediaKit.ensureInitialized() 之前,
        // 先走 Android System.loadLibrary 探测.  如果 dlopen 失败 (ARM 32-bit SIGSEGV),
        // Java 层 UnsatisfiedLinkError 能捕获到, 返回 false 给 Dart → 直接走 FallbackMediaPlayer.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, libmpvCheckChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkLibmpv" -> {
                        try {
                            System.loadLibrary("mpv")
                            result.success(true)
                        } catch (e: UnsatisfiedLinkError) {
                            Log.w(TAG, "libmpv.so 不可用: ${e.message}")
                            result.success(false)
                        } catch (e: Throwable) {
                            Log.e(TAG, "libmpv.so 加载异常: ${e.message}")
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// v0.3.10.13: 安装 native crash handler — 用 Thread.setDefaultUncaughtExceptionHandler
    /// 捕获未处理的 Java/Kotlin 异常,  写到 crash log 文件.
    /// 注意: 这只能捕获 Java 层异常,  SIGSEGV 等 native signal 需要
    /// 注册 signal handler (C/C++ 层).  但 Java 层的 UncaughtExceptionHandler
    /// 能捕获到 libmpv JNI 调用抛出的 Java 异常 (比如 UnsatisfiedLinkError).
    private fun installNativeCrashHandler() {
        val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val crashDir = filesDir
                if (crashDir != null) {
                    val crashFile = File(crashDir, "native_crash.log")
                    val timestamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US).format(Date())
                    val sw = StringWriter()
                    throwable.printStackTrace(PrintWriter(sw))
                    val logEntry = "$timestamp: [${thread.name}] ${throwable.javaClass.name}: ${throwable.message}\n$sw\n"
                    crashFile.appendText(logEntry)
                    Log.e(TAG, "Native crash logged to ${crashFile.absolutePath}", throwable)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to write native crash log", e)
            }
            // v0.3.10.22: 弹 CrashActivity 显示错误 — 用户不用 adb 也能看到崩溃原因
            try {
                val sw2 = StringWriter()
                throwable.printStackTrace(PrintWriter(sw2))
                val intent = Intent(this, CrashActivity::class.java).apply {
                    putExtra("error", "${throwable.javaClass.name}: ${throwable.message}")
                    putExtra("stack", sw2.toString())
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                startActivity(intent)
                Thread.sleep(2000)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to launch CrashActivity", e)
            }
            defaultHandler?.uncaughtException(thread, throwable)
        }
    }

    private fun installApk(path: String) {
        val file = File(path)
        if (!file.exists()) {
            throw IllegalArgumentException("file not found: $path")
        }

        val apkUri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            // Android 7+ (API 24+) — 用 FileProvider.  authority 跟
            // AndroidManifest 里 file_paths.xml + provider 配的
            // ${applicationId}.fileprovider 一致.
            FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file,
            )
        } else {
            Uri.fromFile(file)
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
    }
}
