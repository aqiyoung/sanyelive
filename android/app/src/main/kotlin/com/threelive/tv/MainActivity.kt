package com.threelive.tv

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
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

import com.threelive.tv.pip.PipPlayerManager

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
    private val pipChannelName = "com.threelive.iptv/pip"
    private val mediaSessionChannelName = "com.threelive.iptv/media_session"
    private val TAG = "SanyeliveMain"

    // v0.3.10.22: MediaSession — 让系统 PiP 控件/锁屏控件真正工作
    private var mediaSession: MediaSession? = null
    private var currentPlaybackState = PlaybackState.STATE_NONE
    private var currentChannelId: String? = null
    private val REQUEST_PERMISSIONS = 1001

    // v0.3.10.22: PiP 原生视频播放器
    private val pipPlayer = PipPlayerManager(this)
    private val pipPlayerChannelName = "com.threelive.iptv/pip_player"

    // v0.3.10.22: 在 Flutter 引擎启动前就请求存储权限 —
    // 某些 TV 盒子 ROM 会在 app 不请求权限时直接杀进程.
    override fun onCreate(savedInstanceState: Bundle?) {
        installNativeCrashHandler()
        requestStoragePermissions()
        super.onCreate(savedInstanceState)
    }

    // v0.3.10.22: 用户按 Home 键 → 立即进入 PiP
    override fun onUserLeaveHint() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                enterPictureInPictureMode()
            } catch (e: Exception) {
                Log.e(TAG, "onUserLeaveHint: ${e.message}")
            }
        }
        super.onUserLeaveHint()
    }

    private val pipKeepaliveHandler = Handler(Looper.getMainLooper())
    private var pipKeepaliveRunning = false

    // v0.3.10.22: PiP 模式下周期性刷新 Flutter 视图, 防止视频暂停
    private val pipKeepaliveRunnable = object : Runnable {
        override fun run() {
            if (!pipKeepaliveRunning) return
            flutterEngine?.let { engine ->
                // 强制 Flutter 引擎继续处理帧
                engine.renderer.createSurfaceTexture()
            }
            window?.decorView?.invalidate()
            pipKeepaliveHandler.postDelayed(this, 100)
        }
    }

    // v0.3.10.22: PiP 模式下启动/停止 keepalive
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: android.content.res.Configuration?
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (isInPictureInPictureMode) {
            // 进入 PiP: 启动 keepalive
            pipKeepaliveRunning = true
            pipKeepaliveHandler.post(pipKeepaliveRunnable)
            Log.d(TAG, "onPictureInPictureModeChanged: entered PiP, keepalive started")
        } else {
            // 退出 PiP: 停止 keepalive
            pipKeepaliveRunning = false
            pipKeepaliveHandler.removeCallbacks(pipKeepaliveRunnable)
            Log.d(TAG, "onPictureInPictureModeChanged: exited PiP, keepalive stopped")
        }
        if (!isInPictureInPictureMode) {
            // 用户关闭了小窗 (点了叉) — 通知 Flutter 端停止播放
            try {
                val messenger = flutterEngine?.dartExecutor?.binaryMessenger
                if (messenger != null) {
                    val channel = MethodChannel(messenger, pipChannelName)
                    channel.invokeMethod("pipClosed", null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "onPictureInPictureModeChanged: notify pipClosed failed: ${e.message}")
            }
        }
    }

    override fun onDestroy() {
        // v0.3.10.22: 释放 MediaSession
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            mediaSession?.release()
            mediaSession = null
        }
        // v0.3.10.22: 停止 PiP 原生播放器, 清理 SurfaceView
        pipPlayer.stop()
        super.onDestroy()
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

    // v0.3.10.22: MediaSession callback (由 Dart 端通过 MethodChannel 触发)
    private var _mediaSessionCallback: MediaSession.Callback? = null

    /// 初始化 MediaSession
    private fun initMediaSession() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return
        try {
            val callback = object : MediaSession.Callback() {
                override fun onPlay() {
                    Log.d(TAG, "MediaSession: onPlay")
                    runOnUiThread {
                        sendPlayerCommand("play")
                    }
                }
                override fun onPause() {
                    Log.d(TAG, "MediaSession: onPause")
                    runOnUiThread {
                        sendPlayerCommand("pause")
                    }
                }
                override fun onSkipToPrevious() {
                    Log.d(TAG, "MediaSession: onSkipToPrevious")
                    runOnUiThread {
                        sendPlayerCommand("previous")
                    }
                }
                override fun onSkipToNext() {
                    Log.d(TAG, "MediaSession: onSkipToNext")
                    runOnUiThread {
                        sendPlayerCommand("next")
                    }
                }
            }
            _mediaSessionCallback = callback
            mediaSession = MediaSession(this, "SanyeliveMediaSession").apply {
                setFlags(
                    MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS
                )
                setCallback(callback)
                isActive = true
            }
        } catch (e: Exception) {
            Log.e(TAG, "initMediaSession failed: ${e.message}")
        }
    }

    /// 发送播放控制命令到 Flutter (通过 pip channel 转发)
    private fun sendPlayerCommand(command: String) {
        try {
            val messenger = flutterEngine?.dartExecutor?.binaryMessenger
            if (messenger == null) {
                Log.e(TAG, "sendPlayerCommand $command failed: binaryMessenger is null")
                return
            }
            val channel = MethodChannel(messenger, pipChannelName)
            channel.invokeMethod(command, null)
        } catch (e: Exception) {
            Log.e(TAG, "sendPlayerCommand $command failed: ${e.message}")
        }
    }

    /// 更新播放状态 (Dart 端调用)
    private fun updatePlaybackState(playing: Boolean, channelId: String?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return
        try {
            currentChannelId = channelId
            currentPlaybackState = if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED
            val stateBuilder = PlaybackState.Builder()
                .setActions(
                    PlaybackState.ACTION_PLAY or
                    PlaybackState.ACTION_PAUSE or
                    PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                    PlaybackState.ACTION_SKIP_TO_NEXT
                )
                .setState(currentPlaybackState, 0, 1.0f)
            mediaSession?.setPlaybackState(stateBuilder.build())
        } catch (e: Exception) {
            Log.e(TAG, "updatePlaybackState failed: ${e.message}")
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

        // v0.3.10.22: MediaSession — 让系统 PiP 控件真正工作
        initMediaSession()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaSessionChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "play" -> {
                        _mediaSessionCallback?.onPlay()
                        result.success(true)
                    }
                    "pause" -> {
                        _mediaSessionCallback?.onPause()
                        result.success(true)
                    }
                    "previous" -> {
                        _mediaSessionCallback?.onSkipToPrevious()
                        result.success(true)
                    }
                    "next" -> {
                        _mediaSessionCallback?.onSkipToNext()
                        result.success(true)
                    }
                    "updateState" -> {
                        // Dart 端更新播放状态
                        val playing = call.argument<Boolean>("playing") ?: false
                        val channelId = call.argument<String>("channelId")
                        updatePlaybackState(playing, channelId)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // v0.3.10.18: PiP (画中画) 控制通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pipChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enterPip" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            try {
                                val ret = enterPictureInPictureMode()
                                result.success(ret)
                            } catch (e: Exception) {
                                Log.e(TAG, "enterPip failed: ${e.message}")
                                result.error("PIP_ERROR", e.message, null)
                            }
                        } else {
                            result.error("PIP_ERROR", "Android 8.0+ required", null)
                        }
                    }
                    "isInPip" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            result.success(isInPictureInPictureMode())
                        } else {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // v0.3.10.22: PiP 原生视频播放器控制通道
        // Dart 端传入当前播放的 URL, 原生 SurfaceView 接管渲染
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pipPlayerChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startPipPlayer" -> {
                        val url = call.argument<String>("url")
                        if (url == null) {
                            result.error("ARG_ERROR", "url is required", null)
                            return@setMethodCallHandler
                        }
                        pipPlayer.start(url)
                        result.success(true)
                    }
                    "stopPipPlayer" -> {
                        pipPlayer.stop()
                        result.success(true)
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
