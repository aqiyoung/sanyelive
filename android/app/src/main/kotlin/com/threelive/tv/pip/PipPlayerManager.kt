package com.threelive.tv.pip

import android.content.Context
import android.graphics.PixelFormat
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.util.Log
import android.view.Gravity
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.WindowManager

/// v0.3.10.22: PiP 原生视频播放器 — 渲染到独立 SurfaceView
/// SurfaceView 由 WindowManager 全局管理, 不依赖 Activity
class PipPlayerManager(private val appContext: Context) {

    private var mediaPlayer: MediaPlayer? = null
    private var surfaceView: SurfaceView? = null
    private val windowManager: WindowManager =
        appContext.applicationContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var isPlaying = false
    private var currentUrl: String? = null

    companion object {
        private const val TAG = "PipPlayerManager"

        // 单例, 防止 Activity 重建时丢失状态
        @Volatile
        private var instance: PipPlayerManager? = null

        fun getInstance(context: Context): PipPlayerManager {
            return instance ?: synchronized(this) {
                instance ?: PipPlayerManager(context.applicationContext).also { instance = it }
            }
        }
    }

    /// 开始 PiP 播放
    fun start(url: String) {
        Log.d(TAG, "start: $url")
        if (isPlaying && currentUrl == url) return
        stop() // 先清理旧的

        currentUrl = url

        try {
            // 创建 SurfaceView
            surfaceView = SurfaceView(appContext).apply {
                setBackgroundColor(android.graphics.Color.BLACK)
                holder.setFormat(PixelFormat.OPAQUE)
                holder.addCallback(object : SurfaceHolder.Callback {
                    override fun surfaceCreated(holder: SurfaceHolder) {
                        Log.d(TAG, "surfaceCreated")
                        initPlayer(url, holder)
                    }

                    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
                        Log.d(TAG, "surfaceChanged: ${width}x${height}")
                    }

                    override fun surfaceDestroyed(holder: SurfaceHolder) {
                        Log.d(TAG, "surfaceDestroyed")
                    }
                })
            }

            // 添加到 WindowManager (TYPE_APPLICATION_OVERLAY)
            val params = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                    PixelFormat.OPAQUE
                )
            } else {
                WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.TYPE_PHONE,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                    PixelFormat.OPAQUE
                )
            }.apply {
                gravity = Gravity.TOP or Gravity.START
            }

            windowManager.addView(surfaceView, params)
            isPlaying = true
            Log.d(TAG, "PipPlayer started successfully")
        } catch (e: Exception) {
            Log.e(TAG, "start failed: ${e.message}")
            isPlaying = false
        }
    }

    /// 初始化 MediaPlayer
    private fun initPlayer(url: String, holder: SurfaceHolder) {
        try {
            mediaPlayer = MediaPlayer().apply {
                // 设置音频属性, 请求永久音频焦点, 防止进入 PiP 时暂停
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                            .build()
                    )
                } else {
                    @Suppress("DEPRECATION")
                    setAudioStreamType(AudioManager.STREAM_MUSIC)
                }

                setDataSource(url)
                setSurface(holder.surface)
                setScreenOnWhilePlaying(true)
                setOnPreparedListener { mp ->
                    Log.d(TAG, "MediaPlayer prepared, starting playback")
                    mp.start()
                }
                setOnErrorListener { _, what, extra ->
                    Log.e(TAG, "MediaPlayer error: what=$what, extra=$extra")
                    true
                }
                setOnCompletionListener {
                    Log.d(TAG, "MediaPlayer completed")
                }
                prepareAsync()
            }

            // 请求音频焦点 (防止 PiP 进入时系统回收音频焦点导致暂停)
            val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioManager.requestAudioFocus(
                    AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                        .setAudioAttributes(
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_MEDIA)
                                .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                                .build()
                        )
                        .setAcceptsDelayedFocusGain(true)
                        .setOnAudioFocusChangeListener { focusChange ->
                            Log.d(TAG, "audioFocusChange: $focusChange")
                            when (focusChange) {
                                AudioManager.AUDIOFOCUS_LOSS -> {
                                    // 永久丢失焦点, 继续播放 (直播场景不需要暂停)
                                }
                                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                                    // 暂时丢失, 不暂停
                                }
                                AudioManager.AUDIOFOCUS_GAIN -> {
                                    // 重新获得焦点
                                    mediaPlayer?.start()
                                }
                            }
                        }
                        .build()
                )
            } else {
                @Suppress("DEPRECATION")
                audioManager.requestAudioFocus(
                    { },
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "initPlayer failed: ${e.message}")
        }
    }

    /// 停止 PiP 播放
    fun stop() {
        Log.d(TAG, "stop")
        isPlaying = false

        // 释放音频焦点
        try {
            val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioManager.abandonAudioFocusRequest(
                    AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN).build()
                )
            } else {
                @Suppress("DEPRECATION")
                audioManager.abandonAudioFocus(null)
            }
        } catch (e: Exception) {
            Log.d(TAG, "stop: abandonAudioFocus error: ${e.message}")
        }

        try {
            mediaPlayer?.stop()
        } catch (e: Exception) { Log.d(TAG, "stop: mediaPlayer.stop error: ${e.message}") }
        try {
            mediaPlayer?.release()
        } catch (e: Exception) { Log.d(TAG, "stop: mediaPlayer.release error: ${e.message}") }
        mediaPlayer = null

        try {
            surfaceView?.holder?.surface?.release()
        } catch (e: Exception) { Log.d(TAG, "stop: surface.release error: ${e.message}") }

        try {
            if (surfaceView != null) {
                windowManager.removeView(surfaceView)
                Log.d(TAG, "stop: SurfaceView removed from WindowManager")
            }
        } catch (e: Exception) {
            Log.e(TAG, "stop: removeView failed: ${e.message}")
        }
        surfaceView = null
        currentUrl = null
    }

    /// 是否正在播放
    fun isPlaying(): Boolean = isPlaying
}
