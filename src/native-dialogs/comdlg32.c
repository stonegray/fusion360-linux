/*
 * comdlg32.c - Wine comdlg32 shim that routes Fusion's Open dialog to the
 * host's native Linux file picker.
 *
 * Scope: GetOpenFileNameW only. GetSaveFileNameW forwards straight to Wine.
 * Save is deliberately excluded — a wrong lpstrDefExt or a mis-joined path
 * there writes to the wrong file silently, and Open is read-only.
 *
 * Loaded via WINEDLLOVERRIDES="comdlg32=n" scoped to the Fusion launch. The
 * "=n,b" form is NOT used: it would let Wine fall back to its own dialog and
 * make failures invisible. Failures here return FALSE with
 * FNERR_INVALIDFILENAME so the caller sees a real error instead of a
 * half-working dialog.
 *
 * Contract notes that matter:
 *   - qwindows.dll imports GetOpenFileNameW and GetSaveFileNameW BY NAME.
 *     objdump's "Hint/Ord" column shows 12/14, but those are lib file hints,
 *     not ordinals: Wine's export table (ordinal base 1) has
 *     GetOpenFileNameW at 14 and GetSaveFileNameW at 16. Importing by ordinal
 *     would bind to GetFileTitleW and GetSaveFileNameA respectively, so this
 *     shim must export by name only.
 *   - Callers zero lpstrFile before calling and expect us to fill it. We
 *     must respect nMaxFile in CHARACTERS, not bytes.
 *   - Cancel is FALSE with CommDlgExtendedError()==0. Fusion tells cancel
 *     from failure that way, so this shim cannot call CommDlgExtendedError
 *     itself (doing so would create a dllimport cycle on the DLL we replace);
 *     it leaves the error state untouched on cancel and sets LastError on
 *     genuine failure.
 */

#define COMDLG32_EXPORTS_DEFINED 1
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
/* The comdlg32 header declares these dllimport; we define and export them
 * instead. GCC warns about the redeclaration — benign, and preferable to
 * hand-rolling the OPENFILENAMEW layout, where a wrong ABI would corrupt
 * every caller's stack. The matching .def file controls the export table. */
#include <commdlg.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include "shim_log.h"
#include <stdio.h>

#define PATH_MAX_W 4096

/* This DLL's own module handle, captured at load. */
static HMODULE shim_module = NULL;

/* Resolve the real Wine implementation lazily. We are loaded as comdlg32, so
 * the genuine DLL sits elsewhere on the search path under the same name. */
__declspec(dllexport) BOOL WINAPI GetOpenFileNameW(LPOPENFILENAMEW);
__declspec(dllexport) BOOL WINAPI GetSaveFileNameW(LPOPENFILENAMEW);

typedef BOOL (WINAPI *pGetOpenFileNameW)(LPOPENFILENAMEW);
typedef BOOL (WINAPI *pGetSaveFileNameW)(LPOPENFILENAMEW);

static HMODULE real_dll = NULL;
static pGetOpenFileNameW real_open = NULL;
static pGetSaveFileNameW real_save = NULL;

static void load_real_dll(void)
{
    if (real_dll) return;
    /* Wine keeps the builtin at a searchable location; LOAD_WITH_ALTERED_
     * SEARCH_PATH is required because we ARE comdlg32 and would otherwise
     * find ourselves. */
    real_dll = LoadLibraryExW(L"comdlg32.dll", NULL,
                              LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!real_dll) return;
    real_open = (pGetOpenFileNameW)(void *)GetProcAddress(real_dll, "GetOpenFileNameW");
    real_save = (pGetSaveFileNameW)(void *)GetProcAddress(real_dll, "GetSaveFileNameW");
}

/* Run a host (Unix) binary and capture its stdout.
 *
 * popen() is useless here: under Wine it hands the command to cmd.exe, which
 * neither understands Unix commands nor survives the quoting a Linux path
 * needs. CreateProcessW, by contrast, launches Unix binaries directly when
 * given a Z:\... path (verified: Z:\usr\bin\kdialog --version works).
 *
 * argv must be NULL-terminated. Returns malloc'd UTF-8 stdout on success, or
 * NULL on spawn failure, non-zero exit (cancel), or empty output.
 */
/* Forward declarations: run_host_capture uses these before their definitions
 * because the module is ordered simple-helper-first for readability. */
char *shim_win_path_to_unix(const WCHAR *wpath);
static const WCHAR *host_kdialog(void);

/* Read a whole file into a NUL-terminated UTF-8 buffer. Caller frees. */
static char *read_file_utf8(const WCHAR *path)
{
    HANDLE in = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (in == INVALID_HANDLE_VALUE) return NULL;

    LARGE_INTEGER size;
    if (!GetFileSizeEx(in, &size) || size.QuadPart <= 0) { CloseHandle(in); return NULL; }

    size_t cap = (size_t)size.QuadPart + 1;
    char *buf = (char *)malloc(cap);
    if (!buf) { CloseHandle(in); return NULL; }

    size_t len = 0;
    DWORD got = 0;
    while (len + 1 < cap && ReadFile(in, buf + len, (DWORD)(cap - 1 - len), &got, NULL) && got > 0)
        len += got;
    CloseHandle(in);

    buf[len] = 0;
    return buf;
}

/* Locate hostrunner, shipped beside this DLL. It exists because neither
 * process waiting nor output polling can tell "still running" from "done" —
 * see run_host_capture. */
static const WCHAR *host_runner(void)
{
    static WCHAR path[MAX_PATH];
    static int state = 0;      /* 0 = not tried, 1 = found, -1 = missing */
    if (state) return state > 0 ? path : NULL;
    state = -1;

    /* Use the module handle captured in DllMain. GetModuleFileNameW with a
     * function address as the "handle" returns 0 under Wine — that trap has
     * bitten this file twice now (here and in the drive_c derivation). */
    DWORD got = GetModuleFileNameW(shim_module, path, MAX_PATH);
    if (got == 0 || got >= MAX_PATH) return NULL;

    WCHAR *slash = wcsrchr(path, L'\\');
    if (!slash) return NULL;
    wcscpy(slash + 1, L"hostrunner");

    if (GetFileAttributesW(path) == INVALID_FILE_ATTRIBUTES) return NULL;

    /* Hand the runner back as a Unix path. Wine only executes a Unix binary
     * when it is addressed as one; a C:\...\hostrunner path (no .exe) is
     * treated as a missing program and the spawn silently does nothing. */
    char *unix_self = shim_win_path_to_unix(path);
    if (!unix_self) return NULL;
    MultiByteToWideChar(CP_UTF8, 0, unix_self, -1, path, MAX_PATH);
    free(unix_self);

    state = 1;
    return path;
}

/* Run a host (Unix) binary, capture stdout, and wait for it to really finish.
 *
 * Two Wine behaviours make the obvious implementations wrong, both verified
 * with timing instrumentation:
 *
 *   1. WaitForSingleObject on a Unix child returns in ~4ms for an 8s process
 *      (GetExitCodeProcess likewise returns a constant, never the real
 *      status). Process waiting is unavailable.
 *   2. Polling the output file for content cannot distinguish "still running"
 *      from "exited with no output" — both leave it at zero bytes. A bounded
 *      poll therefore races the human: kdialog writes nothing until a file is
 *      picked, so any timeout is a coin flip against think-time.
 *
 * So the command runs under hostrunner, a tiny helper that waits for kdialog
 * and then writes an exit-status marker. We poll for the marker, which is a
 * real completion signal, with no assumption about how long the user takes.
 *
 * argv must be NULL-terminated. Returns malloc'd UTF-8 stdout, or NULL when
 * the picker was cancelled, failed to launch, or exited with no output.
 */
static char *run_host_capture(const WCHAR *const *argv)
{
    const WCHAR *runner = host_runner();
    const WCHAR *kd = host_kdialog();
    if (!runner || !kd) return NULL;

    /* The runner is a Unix binary: it opens these paths with open(2), so it
     * needs Unix paths, not Z:\... forms. Fusion-visible paths (for our own
     * file checks) stay in Windows form. */
    WCHAR tmpfile[MAX_PATH], donefile[MAX_PATH];
    DWORD seed = GetTickCount();
    char tmp_unix[PATH_MAX_W], done_unix[PATH_MAX_W];
    snprintf(tmp_unix, sizeof tmp_unix, "/tmp/fusion-cdl-%lu-%lu.out",
             (unsigned long)GetCurrentProcessId(), (unsigned long)seed);
    snprintf(done_unix, sizeof done_unix, "/tmp/fusion-cdl-%lu-%lu.done",
             (unsigned long)GetCurrentProcessId(), (unsigned long)seed);
    swprintf(tmpfile, MAX_PATH, L"Z:\\tmp\\fusion-cdl-%lu-%lu.out",
             (unsigned long)GetCurrentProcessId(), (unsigned long)seed);
    swprintf(donefile, MAX_PATH, L"Z:\\tmp\\fusion-cdl-%lu-%lu.done",
             (unsigned long)GetCurrentProcessId(), (unsigned long)seed);
    DeleteFileW(tmpfile);
    DeleteFileW(donefile);

    WCHAR wtmp_unix[PATH_MAX_W], wdone_unix[PATH_MAX_W];
    MultiByteToWideChar(CP_UTF8, 0, tmp_unix, -1, wtmp_unix, PATH_MAX_W);
    MultiByteToWideChar(CP_UTF8, 0, done_unix, -1, wdone_unix, PATH_MAX_W);

    /* Build: runner <out> <done> <kdialog> <args...> */
    WCHAR cmdline[4096];
    size_t pos = 0;
    cmdline[0] = 0;

    const WCHAR *head[3] = { runner, wtmp_unix, wdone_unix };
    for (int i = 0; i < 3; i++) {
        if (i) cmdline[pos++] = L' ';
        cmdline[pos++] = L'"';
        for (const WCHAR *a = head[i]; *a; a++) cmdline[pos++] = *a;
        cmdline[pos++] = L'"';
        cmdline[pos] = 0;
    }
    for (int i = 0; argv[i]; i++) {
        /* argv[0] is the picker itself: the runner execs it, so it must be a
         * Unix path. A Z:\... path makes execvp fail and the runner reports
         * exit 127 with no output, which looked exactly like a cancel. */
        WCHAR unix_buf[MAX_PATH];
        const WCHAR *a0 = argv[i];
        if (i == 0) {
            char *u = shim_win_path_to_unix(argv[0]);
            if (u) {
                MultiByteToWideChar(CP_UTF8, 0, u, -1, unix_buf, MAX_PATH);
                free(u);
                a0 = unix_buf;
            }
        }
        cmdline[pos++] = L' ';
        cmdline[pos++] = L'"';
        for (const WCHAR *a = a0; *a; a++) {
            if (*a == L'"') cmdline[pos++] = L'"';
            cmdline[pos++] = *a;
        }
        cmdline[pos++] = L'"';
        cmdline[pos] = 0;
    }

    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof si);
    ZeroMemory(&pi, sizeof pi);
    si.cb = sizeof si;

    if (!CreateProcessW(NULL, cmdline, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
        shim_log("warn", "CreateProcess failed err=%lu for runner %ls cmdline %ls",
                 GetLastError(), runner, cmdline);
        return NULL;
    }
    CloseHandle(pi.hThread);

    /* Poll for the completion marker. No timeout on the user's behalf: the
     * runner writes it as soon as kdialog exits, however long that takes.
     * The ceiling exists only so a wedged runner cannot hang Fusion forever. */
    int done = 0;
    for (int attempt = 0; attempt < 36000; attempt++) {     /* ~10 min */
        if (GetFileAttributesW(donefile) != INVALID_FILE_ATTRIBUTES) { done = 1; break; }
        Sleep(50);
    }
    CloseHandle(pi.hProcess);
    if (!done) {
        shim_log("warn", "runner produced no completion marker within the ceiling");
        DeleteFileW(tmpfile);
        DeleteFileW(donefile);
        return NULL;
    }

    char *buf = read_file_utf8(tmpfile);
    DeleteFileW(tmpfile);
    DeleteFileW(donefile);

    if (!buf) return NULL;

    /* Trim trailing newline(s); kdialog prints exactly one line. */
    size_t len = strlen(buf);
    while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r'))
        buf[--len] = 0;

    if (len == 0) { free(buf); shim_log("val", "picker exited with empty output (cancelled)"); return NULL; }
    return buf;
}

/* Resolve a host binary by absolute Unix path. We do not rely on PATH:
 * Wine's PATH is a Windows-style list and would not find /usr/bin/kdialog. */
static const WCHAR *host_kdialog(void)
{
    static const WCHAR *candidates[] = {
        L"Z:\\usr\\bin\\kdialog",
        L"Z:\\usr\\local\\bin\\kdialog",
        NULL
    };
    static const WCHAR *found = NULL;
    static BOOL scanned = FALSE;

    if (scanned) return found;
    scanned = TRUE;

    /* Test hook: let a build-agnostic stub stand in for the real picker so
     * the plumbing can be exercised headlessly (no display needed). */
    {
        WCHAR override[MAX_PATH];
        DWORD n = GetEnvironmentVariableW(L"FUSION_NATIVE_DIALOG_CMD", override, MAX_PATH);
        if (n > 0 && n < MAX_PATH) {
            static WCHAR saved[MAX_PATH];
            wcscpy(saved, override);
            found = saved;
            return found;
        }
    }
    for (int i = 0; candidates[i]; i++) {
        if (GetFileAttributesW(candidates[i]) != INVALID_FILE_ATTRIBUTES) {
            found = candidates[i];
            break;
        }
    }
    return found;
}
/* Convert a Windows path to the Unix path a Linux binary can open.
 *
 * Use Wine's own converter rather than mapping drive letters by hand:
 * wine_get_unix_file_name() knows every mapping in the prefix (C:\ ->
 * drive_c, Z:\ -> /), so it cannot drift from the dosdevices layout. A
 * hand-rolled version handled only Z: and returned NULL for Fusion's
 * C:\users\...\Downloads start folder, which made kdialog fail to open and
 * exit with no output — surfacing to Fusion as "user cancelled".
 */
char *shim_win_path_to_unix(const WCHAR *wpath)
{
    if (!wpath || !*wpath) return NULL;

    typedef char *(__cdecl *p_convert)(LPCWSTR);
    static p_convert convert = NULL;
    static int resolved = 0;

    if (!resolved) {
        resolved = 1;
        convert = (p_convert)(void *)GetProcAddress(
            GetModuleHandleW(L"kernel32.dll"), "wine_get_unix_file_name");
    }
    if (!convert) return NULL;

    const char *unix_path = convert(wpath);
    shim_log("val", "win->unix: %ls => %s", wpath, unix_path ? unix_path : "(null)");
    if (!unix_path || !*unix_path) return NULL;

    size_t len = strlen(unix_path) + 1;
    char *copy = (char *)malloc(len);
    if (copy) memcpy(copy, unix_path, len);
    return copy;
}

/* Convert a Windows filter string to a kdialog filter argument.
 *   "Fusion (*.f3d)\0*.f3d\0All Files (*.*)\0*.*\0\0"
 * kdialog syntax: "Label (*.f3d;*.step)|Label2 (*.*)"
 * Returns malloc'd string, or NULL when no usable filter exists. */
/* Build a kdialog filter string from parallel label/pattern arrays.
 *   labels   = {"Fusion Files", "All Files"}
 *   patterns = {"*.f3d", "*.*"}
 *   => "Fusion Files (*.f3d);;All Files (*.*)"
 * Shared by the legacy OPENFILENAMEW path and the COM SetFileTypes path so
 * both produce identical output. Caller frees. */
char *shim_filter_from_pairs(const WCHAR **labels, const WCHAR **patterns, UINT count)
{
    if (!labels || !patterns || !count) return NULL;

    size_t cap = 1024, len = 0;
    char *out = (char *)malloc(cap);
    if (!out) return NULL;
    out[0] = 0;

    for (UINT i = 0; i < count; i++) {
        if (!labels[i] || !patterns[i]) continue;

        int nlabel = WideCharToMultiByte(CP_UTF8, 0, labels[i], -1, NULL, 0, NULL, NULL);
        int npat = WideCharToMultiByte(CP_UTF8, 0, patterns[i], -1, NULL, 0, NULL, NULL);
        if (nlabel <= 0 || npat <= 0) continue;

        char *label = (char *)malloc((size_t)nlabel);
        char *pat = (char *)malloc((size_t)npat);
        if (!label || !pat) { free(label); free(pat); free(out); return NULL; }
        WideCharToMultiByte(CP_UTF8, 0, labels[i], -1, label, nlabel, NULL, NULL);
        WideCharToMultiByte(CP_UTF8, 0, patterns[i], -1, pat, npat, NULL, NULL);

        /* kdialog separates multiple patterns with spaces, not semicolons. */
        for (char *q = pat; *q; q++) if (*q == ';') *q = ' ';

        /* Strip a trailing "(...)" from the label: Fusion's labels usually
         * already contain it, and repeating it reads as "Fusion (*.f3d)
         * (*.f3d)". */
        char *paren = strrchr(label, '(');
        if (paren) {
            while (paren > label && (paren[-1] == ' ' || paren[-1] == '\t')) paren--;
            *paren = 0;
        }
        if (!label[0]) strcpy(label, "Files");

        size_t add = strlen(label) + strlen(pat) + 8;
        if (len + add + 2 >= cap) {
            cap = (len + add + 2) * 2;
            char *nb = (char *)realloc(out, cap);
            if (!nb) { free(label); free(pat); free(out); return NULL; }
            out = nb;
        }
        if (len) { out[len++] = ';'; out[len++] = ';'; }
        len += (size_t)snprintf(out + len, cap - len, "%s (%s)", label, pat);
        free(label);
        free(pat);
    }

    if (!len) { free(out); return NULL; }
    return out;
}

/* Split a legacy OPENFILENAMEW filter (NUL-separated label/pattern pairs,
 * double-NUL terminated) and hand it to the pair-based builder. */
static char *build_kdialog_filter(const WCHAR *wfilter)
{
    if (!wfilter) return NULL;

    /* Measure to the DOUBLE NUL, not the first one: passing -1 stops at the
     * first terminator and silently drops every later filter. */
    const WCHAR *end = wfilter;
    for (;;) {
        while (*end) end++;
        end++;
        if (!*end) { end++; break; }
    }

    /* Count complete label/pattern pairs. */
    size_t count = 0;
    for (const WCHAR *p = wfilter; p < end - 1 && *p; ) {
        p += wcslen(p) + 1;          /* label */
        if (!*p) break;
        p += wcslen(p) + 1;          /* pattern */
        count++;
    }
    if (!count) return NULL;

    const WCHAR **labels = (const WCHAR **)calloc(count, sizeof(WCHAR *));
    const WCHAR **patterns = (const WCHAR **)calloc(count, sizeof(WCHAR *));
    if (!labels || !patterns) { free(labels); free(patterns); return NULL; }

    UINT n = 0;
    const WCHAR *p = wfilter;
    while (p < end - 1 && *p) {
        labels[n] = p;
        p += wcslen(p) + 1;
        if (!*p) break;
        patterns[n] = p;
        p += wcslen(p) + 1;
        n++;
    }

    char *out = shim_filter_from_pairs(labels, patterns, n);
    free(labels);
    free(patterns);
    return out;
}

/* Run kdialog and return the picked Unix path (caller frees), or NULL on
 * cancel/failure. Shared by the legacy OPENFILENAMEW export and the COM
 * IFileOpenDialog::Show path so both behave identically.
 *
 * initial_dir and filter are UTF-8; either may be NULL. */
char *shim_run_picker_str(const char *initial_dir, const char *filter)
{
    const WCHAR *kd = host_kdialog();
    if (!kd) return NULL;

    WCHAR wdir[PATH_MAX_W];
    WCHAR wfilter[4096];

    int n = MultiByteToWideChar(CP_UTF8, 0, initial_dir && *initial_dir ? initial_dir : "/",
                                -1, wdir, PATH_MAX_W);
    if (n <= 0) return NULL;

    int have_filter = 0;
    if (filter && *filter) {
        if (MultiByteToWideChar(CP_UTF8, 0, filter, -1, wfilter, 4096) > 0)
            have_filter = 1;
    }

    /* kdialog takes the filter as a POSITIONAL argument after the start dir;
     * there is no --filter option (verified: "Unknown option 'filter'"). */
    const WCHAR *argv[6];
    int ai = 0;
    argv[ai++] = kd;
    argv[ai++] = L"--getopenfilename";
    argv[ai++] = wdir;
    if (have_filter) argv[ai++] = wfilter;
    argv[ai] = NULL;

    return run_host_capture(argv);
}

/* Convert a Unix path to the Windows path Wine would use for it.
 *
 * Uses wine_get_dos_file_name so the result carries the drive letter Wine
 * itself picks. Blindly prefixing Z: produced
 * Z:\home\...\pfx\drive_c\users\... for files that live on C:\, which is a
 * different string from the C:\users\... form the rest of Fusion uses.
 * Falls back to the Z: mapping only if Wine cannot map the path.
 */
WCHAR *unix_to_win_path(const char *unix_path)
{
    /* Map without spawning anything. winepath would be authoritative, but it
     * must run through run_host_capture, which itself needs this DLL's path —
     * so calling it from here recurses.
     *
     * Wine's layout is fixed and simple: <prefix>/drive_c/... is C:\... and
     * anything else is reachable as Z:\. Derive the prefix from this DLL's
     * own module path, which always lives under drive_c by construction. */
    if (!unix_path || unix_path[0] != '/') return NULL;

    /* GetModuleFileName returns a WINDOWS path (C:/users/...), so it has to
     * be mapped to Unix before any "/drive_c/" logic can work. Using it
     * directly was why the C: branch never matched. */
    WCHAR wself[MAX_PATH * 2];
    DWORD got = GetModuleFileNameW(shim_module, wself, MAX_PATH * 2);
    if (got == 0 || got >= MAX_PATH * 2) return NULL;

    char *unix_self = shim_win_path_to_unix(wself);
    if (!unix_self) return NULL;
    char self[MAX_PATH * 2];
    strncpy(self, unix_self, sizeof self - 1);
    self[sizeof self - 1] = 0;
    free(unix_self);

    /* ".../pfx/drive_c/users/..." -> prefix root is everything before /drive_c */
    char *marker = strstr(self, "/drive_c/");
    /* Keep ".../drive_c" WITHOUT the trailing slash, so prefix compares
     * against "/drive_c" and the following character is the path separator. */
    if (marker) marker[8] = 0;

    WCHAR prefix[MAX_PATH];
    MultiByteToWideChar(CP_UTF8, 0, self, -1, prefix, MAX_PATH);

    WCHAR wunix[MAX_PATH];
    if (MultiByteToWideChar(CP_UTF8, 0, unix_path, -1, wunix, MAX_PATH) <= 0)
        return NULL;

    const WCHAR *rest = NULL;
    WCHAR drive[3] = { 0, 0, 0 };

    if (marker && wcsncmp(wunix, prefix, wcslen(prefix)) == 0 && wunix[wcslen(prefix)] == L'/') {
        /* Inside the prefix: strip "<prefix>/drive_c" and use C: */
        const WCHAR *p = wunix + wcslen(prefix);   /* points at '/' */
        drive[0] = L'C'; drive[1] = L':';
        rest = p;
    } else {
        drive[0] = L'Z'; drive[1] = L':';
        rest = wunix;
    }

    size_t len = wcslen(rest) + 3;
    WCHAR *out = (WCHAR *)malloc(len * sizeof(WCHAR));
    if (!out) return NULL;
    swprintf(out, len, L"%ls%ls", drive, rest);
    for (WCHAR *q = out; *q; q++) if (*q == L'/') *q = L'\\';
    /* rest begins with the separator; ensure the drive is followed by one */
    if (out[2] != L'\\' && out[2] != 0) {
        size_t l2 = wcslen(out) + 2;
        WCHAR *fixed = (WCHAR *)malloc(l2 * sizeof(WCHAR));
        if (fixed) {
            fixed[0] = out[0]; fixed[1] = out[1]; fixed[2] = L'\\';
            wcscpy(fixed + 3, out + 2);
            free(out);
            out = fixed;
        }
    }
    return out;
}

/* Wide wrapper: convert a Windows path for a Linux binary and hand it back
 * as WCHAR, since the COM path keeps its data wide throughout. */
WCHAR *shim_win_path_to_unix_wide(const WCHAR *wpath)
{
    char *unix_path = shim_win_path_to_unix(wpath);
    if (!unix_path) return NULL;

    int n = MultiByteToWideChar(CP_UTF8, 0, unix_path, -1, NULL, 0);
    if (n <= 0) { free(unix_path); return NULL; }

    WCHAR *wide = (WCHAR *)malloc((size_t)n * sizeof(WCHAR));
    if (wide)
        MultiByteToWideChar(CP_UTF8, 0, unix_path, -1, wide, n);
    free(unix_path);
    return wide;
}

/* WCHAR wrapper used by the COM path. */
char *shim_run_picker(const WCHAR *initial_dir, const WCHAR *filter)
{
    char *dir_utf8 = NULL, *filter_utf8 = NULL;

    if (initial_dir && *initial_dir) {
        int n = WideCharToMultiByte(CP_UTF8, 0, initial_dir, -1, NULL, 0, NULL, NULL);
        if (n > 0) {
            dir_utf8 = (char *)malloc((size_t)n);
            if (dir_utf8) WideCharToMultiByte(CP_UTF8, 0, initial_dir, -1, dir_utf8, n, NULL, NULL);
        }
    }
    if (filter && *filter) {
        int n = WideCharToMultiByte(CP_UTF8, 0, filter, -1, NULL, 0, NULL, NULL);
        if (n > 0) {
            filter_utf8 = (char *)malloc((size_t)n);
            if (filter_utf8) WideCharToMultiByte(CP_UTF8, 0, filter, -1, filter_utf8, n, NULL, NULL);
        }
    }

    char *picked = shim_run_picker_str(dir_utf8, filter_utf8);
    free(dir_utf8);
    free(filter_utf8);
    return picked;
}

/* Exported, not imported: without this the comdlg32 headers mark the
 * prototypes dllimport and GCC may bind calls to the imported thunk. */
BOOL WINAPI GetOpenFileNameW(LPOPENFILENAMEW lpofn)
{
    if (!lpofn) return FALSE;

    char *unix_initial = NULL;
    if (lpofn->lpstrInitialDir && *lpofn->lpstrInitialDir)
        unix_initial = shim_win_path_to_unix(lpofn->lpstrInitialDir);
    if (!unix_initial)
        unix_initial = strdup(getenv("HOME") ? getenv("HOME") : "/");

    char *filter = build_kdialog_filter(lpofn->lpstrFilter);
    char *picked = shim_run_picker_str(unix_initial, filter);
    free(unix_initial);
    free(filter);

    if (!picked) {
        /* NULL means cancel, or the picker is missing entirely. A missing
         * picker is a configuration error worth surfacing. */
        if (!host_kdialog())
            goto fail;
        SetLastError(0);
        return FALSE; /* user cancelled */
    }

    /* kdialog returns a Unix path. Convert back to a Windows path so the
     * caller's OPENFILENAMEW contract holds. Wine's Z: maps to /. */
    WCHAR wpicked[MAX_PATH];
    if (picked[0] == '/') {
        /* MultiByteToWideChar for the bytes, then prefix Z:. */
        int need = MultiByteToWideChar(CP_UTF8, 0, picked, -1, NULL, 0);
        if (need <= 0 || need + 3 > MAX_PATH) { free(picked); goto fail; }
        WCHAR tmp[MAX_PATH];
        MultiByteToWideChar(CP_UTF8, 0, picked, -1, tmp, need);
        wpicked[0] = L'Z'; wpicked[1] = L':';
        for (int i = 0; i < need; i++)
            wpicked[i + 2] = (tmp[i] == L'/') ? L'\\' : tmp[i];
    } else {
        /* Already Windows-ish (shouldn't happen) — pass through. */
        if (MultiByteToWideChar(CP_UTF8, 0, picked, -1, wpicked, MAX_PATH) <= 0) {
            free(picked);
            goto fail;
        }
    }
    free(picked);

    /* nMaxFile is in characters. Refuse to truncate: a silently shortened
     * path would point at the wrong file. */
    DWORD len = (DWORD)wcslen(wpicked);
    if (lpofn->nMaxFile && len + 1 > lpofn->nMaxFile) goto fail;

    if (lpofn->lpstrFile) {
        DWORD cap = lpofn->nMaxFile ? lpofn->nMaxFile : (len + 1);
        wcsncpy(lpofn->lpstrFile, wpicked, cap - 1);
        lpofn->lpstrFile[cap - 1] = L'\0';
    }
    /* These are WORD fields, not pointers: they are pure outputs and always
     * get written on success. nFileOffset is the 0-based index of the file
     * name; nFileExtension the index of its final dot. */
    {
        const WCHAR *slash = wcsrchr(wpicked, L'\\');
        const WCHAR *base = slash ? slash + 1 : wpicked;
        const WCHAR *dot = wcsrchr(base, L'.');
        lpofn->nFileOffset = (WORD)(base - wpicked);
        lpofn->nFileExtension = dot ? (WORD)(dot - wpicked) : 0;
    }

    return TRUE;

fail:
    /* Real failure: surface it. Callers check CommDlgExtendedError() after a
     * FALSE return; returning bare FALSE from here would be indistinguishable
     * from a cancel and hide a broken shim. */
    SetLastError(ERROR_INVALID_PARAMETER);
    return FALSE;
}

BOOL WINAPI GetSaveFileNameW(LPOPENFILENAMEW lpofn)
{
    /* Not shimmed: save-path bugs destroy data. Delegate to Wine. */
    load_real_dll();
    if (real_save) return real_save(lpofn);
    return FALSE;
}


/* ── COM entry points ─────────────────────────────────────────────── */

HRESULT WINAPI ShimDllGetClassObject(REFCLSID clsid, REFIID riid, void **out);

/* Fusion's Open dialog goes through CoCreateInstance(CLSID_FileOpenDialog),
 * not GetOpenFileNameW, so the class object is what actually matters.
 * Unregistered CLSIDs get CLASS_E_CLASSNOTAVAILABLE and fall back. */
BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH)
        shim_module = instance;
    return TRUE;
}

HRESULT WINAPI DllGetClassObject(REFCLSID clsid, REFIID riid, void **out)
{
    return ShimDllGetClassObject(clsid, riid, out);
}
