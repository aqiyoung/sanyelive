package com.threelive.tv

import android.app.Activity
import android.os.Bundle
import android.widget.ScrollView
import android.widget.TextView
import android.graphics.Color

/**
 * v0.3.10.22: 崩溃信息展示页 — UncaughtExceptionHandler 捕获异常后
 * 启动此 Activity, 在屏幕上直接显示错误堆栈. 用户不用 adb 也不用
 * 看 sdcard 就能看到崩溃原因.
 */
class CrashActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val errorText = intent.getStringExtra("error") ?: "Unknown error"
        val stackText = intent.getStringExtra("stack") ?: ""

        val scrollView = ScrollView(this).apply {
            setBackgroundColor(Color.parseColor("#FFEBEE"))
            setPadding(32, 32, 32, 32)
        }

        val textView = TextView(this).apply {
            text = buildString {
                appendLine("=== 三页直播 崩溃报告 ===")
                appendLine()
                appendLine("错误: $errorText")
                appendLine()
                appendLine("--- 堆栈 ---")
                appendLine(stackText)
                appendLine()
                appendLine("请截图发给开发者")
            }
            setTextColor(Color.parseColor("#D32F2F"))
            textSize = 14f
            setPadding(16, 16, 16, 16)
        }

        scrollView.addView(textView)
        setContentView(scrollView)
    }
}
