// v0.3.10.24: Native signal handler — 在 JNI/Flutter 引擎初始化之前就注册,
// 捕获 SIGSEGV/SIGABRT 写到 /sdcard/Download/native_crash.txt,
// 用户不用 adb 也能看到崩溃原因.

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <time.h>
#include <android/log.h>

#define TAG "NativeCrash"

static void crash_handler(int sig, siginfo_t *info, void *context) {
    // 写到 /sdcard/Download/ (Android 9 以下无需权限)
    FILE *f = fopen("/sdcard/Download/native_crash.txt", "w");
    if (!f) {
        // fallback: app 内部存储
        f = fopen("/data/data/com.threelive.tv/files/native_crash.txt", "w");
    }
    if (f) {
        time_t now = time(NULL);
        struct tm *t = localtime(&now);
        char timebuf[64];
        strftime(timebuf, sizeof(timebuf), "%Y-%m-%d %H:%M:%S", t);

        fprintf(f, "=== Native Crash ===\n");
        fprintf(f, "Time: %s\n", timebuf);
        fprintf(f, "Signal: %d (%s)\n", sig,
                sig == SIGSEGV ? "SIGSEGV" :
                sig == SIGABRT ? "SIGABRT" :
                sig == SIGBUS  ? "SIGBUS"  : "UNKNOWN");
        fprintf(f, "Fault addr: %p\n", info->si_addr);
        fprintf(f, "PID: %d, TID: %d\n", getpid(), gettid());

        // 尝试写 backtrace (需要 execinfo.h, 有些 NDK 版本没有)
        #ifdef __GLIBC__
        #include <execinfo.h>
        void *bt[32];
        int n = backtrace(bt, 32);
        char **syms = backtrace_symbols(bt, n);
        if (syms) {
            fprintf(f, "\nBacktrace (%d frames):\n", n);
            for (int i = 0; i < n; i++) {
                fprintf(f, "  #%d %s\n", i, syms[i]);
            }
            free(syms);
        }
        #endif

        fprintf(f, "\n--- END ---\n");
        fclose(f);
    }

    __android_log_print(ANDROID_LOG_ERROR, TAG,
        "FATAL signal %d at %p, crash log written", sig, info->si_addr);

    // 恢复默认 handler 并重新触发, 让系统走正常 crash 流程
    signal(sig, SIG_DFL);
    raise(sig);
}

__attribute__((constructor))
static void init_crash_handler(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = crash_handler;
    sa.sa_flags = SA_SIGINFO;
    sigemptyset(&sa.sa_mask);

    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGABRT, &sa, NULL);
    sigaction(SIGBUS,  &sa, NULL);
    sigaction(SIGFPE,  &sa, NULL);
    sigaction(SIGILL,  &sa, NULL);

    __android_log_print(ANDROID_LOG_INFO, TAG,
        "Crash handler installed (constructor)");
}
