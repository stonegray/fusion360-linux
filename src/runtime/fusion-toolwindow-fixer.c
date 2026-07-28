/*
 * fusion-toolwindow-fixer.c
 *
 * Background daemon that finds Fusion 360's docked toolwindow popups
 * (WS_POPUP | WS_EX_TOOLWINDOW) and adds WS_EX_APPWINDOW to their
 * extended style.  This forces Wine's X11 driver to mark them as
 * *managed* instead of override-redirect, so the compositor stacks
 * them with their owner window and they can drop behind other apps.
 *
 * Without this fix those popups become override-redirect X11 windows
 * that the compositor keeps above every other application window
 * ("always on top" z-order bug).
 *
 * Compile with:
 *   x86_64-w64-mingw32-gcc -Os -s -o fusion-toolwindow-fixer.exe \
 *       fusion-toolwindow-fixer.c -luser32
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <stdarg.h>

/* ------------------------------------------------------------------ */
/* Constants                                                          */
/* ------------------------------------------------------------------ */
#define IDLE_SLEEP_MS     2000   /* pause between scans (ms)          */
#define LOG_FILE          L"/tmp/fusion-toolwindow-fixer.log"

/* ------------------------------------------------------------------ */
/* Logging                                                            */
/* ------------------------------------------------------------------ */
static FILE *log_fp = NULL;

static void log_init(void)
{
    log_fp = _wfopen(LOG_FILE, L"a, ccs=UTF-8");
}

static void log_msg(const WCHAR *fmt, ...)
{
    if (!log_fp) return;
    va_list args;
    va_start(args, fmt);
    vfwprintf(log_fp, fmt, args);
    fflush(log_fp);
    va_end(args);
}

/* ------------------------------------------------------------------ */
/* Helpers                                                            */
/* ------------------------------------------------------------------ */
static DWORD g_target_pid = 0;

static DWORD find_fusion_pid(void)
{
    HANDLE snap;
    PROCESSENTRY32W pe;
    DWORD pid = 0;

    snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return 0;

    pe.dwSize = sizeof(pe);
    if (Process32FirstW(snap, &pe))
    {
        do {
            WCHAR buf[64];
            DWORD i;
            for (i = 0; pe.szExeFile[i] && i < 63; i++)
                buf[i] = towupper(pe.szExeFile[i]);
            buf[i] = 0;

            if (wcsstr(buf, L"FUSION360.EXE"))
            {
                pid = pe.th32ProcessID;
                break;
            }
        } while (Process32NextW(snap, &pe));
    }
    CloseHandle(snap);
    return pid;
}

static BOOL is_fusion_window(HWND hwnd)
{
    DWORD pid;
    GetWindowThreadProcessId(hwnd, &pid);
    return (pid == g_target_pid && pid != 0);
}

static BOOL needs_fix(HWND hwnd)
{
    LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);

    if (!(ex & WS_EX_TOOLWINDOW)) return FALSE;
    if (!GetWindow(hwnd, GW_OWNER)) return FALSE;
    if (ex & WS_EX_APPWINDOW) return FALSE;

    return TRUE;
}

static void fix_window(HWND hwnd)
{
    LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    LONG_PTR new_ex = ex | WS_EX_APPWINDOW;

    SetWindowLongPtrW(hwnd, GWL_EXSTYLE, new_ex);

    /* Force Wine to re-evaluate the managed state via WindowPosChanging. */
    SetWindowPos(hwnd, NULL, 0, 0, 0, 0,
                 SWP_NOSIZE | SWP_NOMOVE | SWP_NOZORDER |
                 SWP_NOACTIVATE | SWP_FRAMECHANGED);

    {
        WCHAR buf[256];
        int len = GetWindowTextW(hwnd, buf, sizeof(buf)/sizeof(buf[0]));
        if (len > 0) buf[len] = 0;
        log_msg(L"  fixed: hwnd=%p ex=0x%lx title=\"%s\"\n",
                (void*)hwnd, (unsigned long)new_ex, buf);
    }
}

/* ------------------------------------------------------------------ */
/* Callback for EnumWindows                                           */
/* ------------------------------------------------------------------ */
static BOOL CALLBACK enum_proc(HWND hwnd, LPARAM lparam)
{
    int *fixed_count = (int *)lparam;

    if (!is_fusion_window(hwnd))       return TRUE;
    if (!needs_fix(hwnd))              return TRUE;

    fix_window(hwnd);
    (*fixed_count)++;
    return TRUE;
}

/* ------------------------------------------------------------------ */
/* Main loop                                                          */
/* ------------------------------------------------------------------ */
int WINAPI WinMain(HINSTANCE inst, HINSTANCE prev, LPSTR cmdline, int show)
{
    int pass = 0;

    log_init();
    log_msg(L"fusion-toolwindow-fixer.exe started\n");

    while (1)
    {
        g_target_pid = find_fusion_pid();
        if (!g_target_pid)
        {
            Sleep(5000);
            continue;
        }

        pass++;
        {
            int fixed = 0;
            EnumWindows(enum_proc, (LPARAM)&fixed);
            if (fixed > 0)
                log_msg(L"  pass %d: fixed %d window(s)\n", pass, fixed);
        }

        Sleep(IDLE_SLEEP_MS);
    }

    if (log_fp) fclose(log_fp);
    return 0;
}
