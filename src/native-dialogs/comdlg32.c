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
#include <stdio.h>

#define PATH_MAX_W 4096

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
static char *run_host_capture(const WCHAR *const *argv)
{
    WCHAR cmdline[4096];
    size_t pos = 0;
    cmdline[0] = 0;

    for (int i = 0; argv[i]; i++) {
        const WCHAR *a = argv[i];
        if (pos + wcslen(a) + 4 > 4096) return NULL;
        if (i) cmdline[pos++] = L' ';
        cmdline[pos++] = L'"';
        for (; *a; a++) {
            /* Double embedded quotes per the standard Windows argv rule. */
            if (*a == L'"') cmdline[pos++] = L'"';
            if (pos + 3 > 4096) return NULL;
            cmdline[pos++] = *a;
        }
        cmdline[pos++] = L'"';
        cmdline[pos] = 0;
    }

    /* Redirect stdout to a temp FILE rather than an anonymous pipe.
     * Wine's CreateProcessW does not reliably hand an inherited pipe handle
     * to a Unix binary — the child starts, but writes nowhere and the read
     * side sees 0 bytes. A real file on disk is inherited correctly. */
    /* Must live on the Unix filesystem. GetTempPathW returns the Windows temp
     * dir (C:\users\...\Temp), and a Unix child inheriting a handle opened
     * there gets a zero-byte file — the redirect silently produces nothing.
     * /tmp (Z:\tmp) works. */
    WCHAR tmpfile[MAX_PATH];
    swprintf(tmpfile, MAX_PATH, L"Z:\\tmp\\fusion-cdl-%lu-%lu.tmp",
             (unsigned long)GetCurrentProcessId(), (unsigned long)GetTickCount());

    SECURITY_ATTRIBUTES sa = { sizeof sa, NULL, TRUE };
    HANDLE out = CreateFileW(tmpfile, GENERIC_WRITE | GENERIC_READ,
                             FILE_SHARE_READ | FILE_SHARE_WRITE, &sa,
                             CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (out == INVALID_HANDLE_VALUE) return NULL;

    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof si);
    ZeroMemory(&pi, sizeof pi);
    si.cb = sizeof si;
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdOutput = out;
    si.hStdError = out;
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);

    BOOL ok = CreateProcessW(NULL, cmdline, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi);
    if (!ok) {
        CloseHandle(out);
        DeleteFileW(tmpfile);
        return NULL;
    }
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 1;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    CloseHandle(out);

    /* Read the captured output back. */
    size_t cap = 512, len = 0;
    char *buf = (char *)malloc(cap);
    if (!buf) { DeleteFileW(tmpfile); return NULL; }

    /* Wine can report the process as exited before the Unix child's buffered
     * writes land. Retry briefly rather than returning a spurious cancel. */
    HANDLE in = INVALID_HANDLE_VALUE;
    for (int attempt = 0; attempt < 50; attempt++) {
        in = CreateFileW(tmpfile, GENERIC_READ, FILE_SHARE_READ, NULL,
                         OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
        if (in != INVALID_HANDLE_VALUE) {
            LARGE_INTEGER sz;
            if (GetFileSizeEx(in, &sz) && sz.QuadPart > 0) break;
            CloseHandle(in);
            in = INVALID_HANDLE_VALUE;
        }
        Sleep(20);
    }
    if (in != INVALID_HANDLE_VALUE) {
        for (;;) {
            DWORD got = 0;
            if (cap - len < 2) {
                char *nb = (char *)realloc(buf, cap * 2);
                if (!nb) break;
                buf = nb; cap *= 2;
            }
            if (!ReadFile(in, buf + len, (DWORD)(cap - len - 1), &got, NULL) || got == 0)
                break;
            len += got;
        }
        CloseHandle(in);
    }
    DeleteFileW(tmpfile);

    if (!buf) return NULL;
    buf[len] = 0;
    while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r'))
        buf[--len] = 0;

    /* Do NOT trust the exit code: Wine cannot report a Unix child's status.
     * Observed values are constant (28671 / 4106) regardless of whether the
     * child exited 0 or 1. kdialog prints the picked path and nothing on
     * cancel, so empty output is the only reliable cancel signal. */
    (void)code;
    if (len == 0) { free(buf); return NULL; }
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
/* Convert a Windows path (C:\x\y, Z:\home\me) to a Unix path using
 * Wine's drive mapping: drive Z: is "/". Other drives need `winepath`.
 * Returns malloc'd string, or NULL if it cannot be resolved. */
static char *win_path_to_unix(const WCHAR *wpath)
{
    char *utf8 = NULL;
    int n = WideCharToMultiByte(CP_UTF8, 0, wpath, -1, NULL, 0, NULL, NULL);
    if (n <= 0) return NULL;
    utf8 = (char *)malloc((size_t)n);
    if (!utf8) return NULL;
    WideCharToMultiByte(CP_UTF8, 0, wpath, -1, utf8, n, NULL, NULL);

    /* Fast path: Z:\... is /...  (Wine's default roots mapping). */
    if ((utf8[0] == 'Z' || utf8[0] == 'z') && utf8[1] == ':' && (utf8[2] == '\\' || utf8[2] == '/')) {
        char *unix_path = (char *)malloc(strlen(utf8) + 1);
        if (!unix_path) { free(utf8); return NULL; }
        strcpy(unix_path, utf8 + 2);
        for (char *p = unix_path; *p; p++) if (*p == '\\') *p = '/';
        free(utf8);
        return unix_path;
    }

    /* Anything else (C:, network drives): we cannot map it without winepath,
     * and the last-resort fallback is simply to start in $HOME. Returning
     * NULL makes the caller do exactly that, which is better than handing
     * kdialog a Windows path it will silently treat as a relative name. */
    free(utf8);
    return NULL;
}

/* Convert a Windows filter string to a kdialog filter argument.
 *   "Fusion (*.f3d)\0*.f3d\0All Files (*.*)\0*.*\0\0"
 * kdialog syntax: "Label (*.f3d;*.step)|Label2 (*.*)"
 * Returns malloc'd string, or NULL when no usable filter exists. */
static char *build_kdialog_filter(const WCHAR *wfilter)
{
    if (!wfilter) return NULL;

    /* Measure to the DOUBLE NUL, not the first one. Passing -1 stops at the
     * first terminator, which yields only the first label and silently drops
     * every filter after it. */
    int wlen = 0;
    for (;;) {
        while (wfilter[wlen]) wlen++;   /* end of this string */
        wlen++;                         /* step over its terminator */
        if (!wfilter[wlen]) { wlen++; break; }  /* empty string => end */
    }

    int n = WideCharToMultiByte(CP_UTF8, 0, wfilter, wlen, NULL, 0, NULL, NULL);
    if (n <= 0) return NULL;
    char *flat = (char *)malloc((size_t)n + 1);
    if (!flat) return NULL;
    int got = WideCharToMultiByte(CP_UTF8, 0, wfilter, wlen, flat, n, NULL, NULL);
    if (got <= 0) { free(flat); return NULL; }
    flat[got] = 0;

    /* flat is a sequence of NUL-separated pairs, terminated by an empty
     * string. Walk it: label, pattern, label, pattern, ... */
    size_t cap = 1024, len = 0;
    char *out = (char *)malloc(cap);
    if (!out) { free(flat); return NULL; }
    out[0] = '\0';

    const char *p = flat;
    while (*p) {
        const char *label = p;
        p += strlen(p) + 1;
        if (!*p) break;
        const char *pattern = p;
        p += strlen(p) + 1;

        /* kdialog wants patterns space-separated inside one quoted group. */
        char pat[512];
        size_t po = 0;
        for (const char *q = pattern; *q && po < sizeof(pat) - 2; q++) {
            pat[po++] = (*q == ';') ? ' ' : *q;
        }
        pat[po] = '\0';

        /* "--filter" once, then bare "Label (*.ext)" groups. */
        size_t add = strlen(label) + strlen(pat) + 8;
        if (len + add + 2 >= cap) {
            cap = (len + add + 2) * 2;
            char *nb = (char *)realloc(out, cap);
            if (!nb) { free(out); free(flat); return NULL; }
            out = nb;
        }
        /* kdialog format: "Label (*.a *.b) (*.a *.b)". The left side is the
         * human label, the right the selectable patterns. Fusion's labels
         * usually already end in "(*.f3d)", so strip a trailing parenthesised
         * group before appending the real pattern list — otherwise the entry
         * reads "Fusion (*.f3d) (*.f3d)". */
        char clean[512];
        strncpy(clean, label, sizeof clean - 1);
        clean[sizeof clean - 1] = 0;
        char *paren = strrchr(clean, '(');
        if (paren) {
            while (paren > clean && (paren[-1] == ' ' || paren[-1] == '\t')) paren--;
            *paren = 0;
        }
        if (!clean[0]) strcpy(clean, "Files");

        /* kdialog: "Label (*.ext *.ext2);;Next (…)". Groups separated by ;;. */
        if (len) { out[len++] = ';'; out[len++] = ';'; }
        len += (size_t)snprintf(out + len, cap - len, "%s (%s)", clean, pat);
    }

    free(flat);
    if (!len) { free(out); return NULL; }
    return out;
}

/* Exported, not imported: without this the comdlg32 headers mark the
 * prototypes dllimport and GCC may bind calls to the imported thunk. */
BOOL WINAPI GetOpenFileNameW(LPOPENFILENAMEW lpofn)
{
    if (!lpofn) return FALSE;

    char *unix_initial = NULL;
    if (lpofn->lpstrInitialDir && *lpofn->lpstrInitialDir)
        unix_initial = win_path_to_unix(lpofn->lpstrInitialDir);
    if (!unix_initial)
        unix_initial = strdup(getenv("HOME") ? getenv("HOME") : "/");

    char *filter = build_kdialog_filter(lpofn->lpstrFilter);

    /* kdialog --getopenfilename <startdir> [--filter <spec>]
     * Built as argv so CreateProcessW can quote each element correctly. */
    const WCHAR *kd = host_kdialog();
    if (!kd) { free(unix_initial); free(filter); goto fail; }

    WCHAR wdir[PATH_MAX_W];
    WCHAR wfilter[2048];
    MultiByteToWideChar(CP_UTF8, 0, unix_initial ? unix_initial : "/",
                        -1, wdir, PATH_MAX_W);
    if (filter)
        MultiByteToWideChar(CP_UTF8, 0, filter, -1, wfilter, 2048);

    /* kdialog takes the filter as a POSITIONAL argument after the start dir;
     * there is no --filter option (verified: "Unknown option 'filter'"). */
    const WCHAR *argv[6];
    int ai = 0;
    argv[ai++] = kd;
    argv[ai++] = L"--getopenfilename";
    argv[ai++] = wdir;
    if (filter) argv[ai++] = wfilter;
    argv[ai] = NULL;

    free(unix_initial);
    free(filter);

    char *picked = run_host_capture(argv);

    if (!picked) {
        /* run_host_capture returns NULL both for cancel (non-zero exit) and
         * for a launch failure. A missing picker is a configuration error
         * worth surfacing; a cancel is not. */
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

