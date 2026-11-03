/*
 * fusion-toolwindow-fixer.c
 *
 * Background daemon that finds Fusion 360's unmanaged popup windows
 * (WS_POPUP without WS_EX_APPWINDOW, owned by a parent) and adds
 * WS_EX_APPWINDOW to their extended style.  This forces Wine's X11
 * driver to make them *managed* instead of override-redirect, so the
 * compositor stacks them correctly and they can drop behind other
 * application windows.
 *
 * Fusion creates many sub-windows as WS_POPUP — docked panels (browser,
 * data panel), toolbar areas, status bars — that Wine X11 would
 * normally make override-redirect, causing them to float above every
 * other window ("always on top" z-order bug).  Adding WS_EX_APPWINDOW
 * makes them regular managed windows the compositor understands.
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
#define IDLE_SLEEP_MS     5000   /* pause between scans (ms)          */
/* FIXME: Read from FUSION_LOG_DIR env var at runtime for consistency with  */
/* the rest of the stack. Currently hardcoded — Wine translates Unix paths. */
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
    LONG style = GetWindowLongPtrW(hwnd, GWL_STYLE);
    LONG_PTR ex  = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);

    /* WS_POPUP is what triggers Wine X11's override-redirect behaviour.   */
    if (!(style & WS_POPUP)) return FALSE;

    /* Must have an owner — owned popups are child panels / toolwindows.   */
    if (!GetWindow(hwnd, GW_OWNER)) return FALSE;

    /* Already done — skip so we don't keep calling SetWindowLong.      */
    if (ex & WS_EX_APPWINDOW) return FALSE;

    /* ── Accept if it's a recognized "panel" style ──────────────────
     * Toolwindow style (WS_EX_TOOLWINDOW) — the original fix target.
     * Also catch plain popups that are NOT dialogs: no caption bar,
     * no dialog frame, no modal frame.  This picks up docked panels
     * Fusion creates as bare WS_POPUP without WS_EX_TOOLWINDOW.      */
    if (!(ex & WS_EX_TOOLWINDOW))
    {
        /* Dialog exclusion — windows with a frame or caption are managed
         * by Wine X11 already.  Fixing them would break file dialogs.  */
        if (style & (WS_CAPTION | WS_DLGFRAME))   return FALSE;
        if (ex   & WS_EX_DLGMODALFRAME)            return FALSE;
        /* Exclude windows with a visible menu bar — these are real apps. */
        if (style & WS_SYSMENU)                    return FALSE;
    }

    /* Skip invisible windows — hidden helper windows promoted to        */
    /* managed would create phantom white boxes.                          */
    if (!IsWindowVisible(hwnd)) return FALSE;

    /* Skip zero-size / 1-pixel windows — Fusion creates tiny helpers.    */
    RECT r;
    GetWindowRect(hwnd, &r);
    if (r.right - r.left <= 1 && r.bottom - r.top <= 1) return FALSE;

    return TRUE;
}

static void fix_window(HWND hwnd)
{
    LONG_PTR ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    LONG_PTR new_ex = ex | WS_EX_APPWINDOW;

    /* Save current position in case the WM misplaces the window
     * during the unmanaged->managed transition on HiDPI.             */
    RECT pos;
    GetWindowRect(hwnd, &pos);

    SetWindowLongPtrW(hwnd, GWL_EXSTYLE, new_ex);

    /* Transition to managed + restore position in one call.          */
    SetWindowPos(hwnd, NULL, pos.left, pos.top,
                 pos.right - pos.left, pos.bottom - pos.top,
                 SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);

    {
        WCHAR buf[256];
        int len = GetWindowTextW(hwnd, buf, sizeof(buf)/sizeof(buf[0]));
        if (len > 0) buf[len] = 0;
        log_msg(L"  fixed: hwnd=%p ex=0x%lx pos=(%d,%d) title=\"%s\"\n",
                (void*)hwnd, (unsigned long)new_ex,
                pos.left, pos.top, buf);
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
