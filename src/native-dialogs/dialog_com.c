/*
 * dialog_com.c - IFileOpenDialog (COM) implementation for the comdlg32 shim.
 *
 * Why this exists: Fusion's Open dialog does not call GetOpenFileNameW.
 * NuCommands10.dll uses QFileDialog, and Qt's QWindowsNativeOpenFileDialog
 * prefers the COM IFileDialog route whenever the class is registered. Wine's
 * comdlg32 provides it, and the registry pins it to an absolute path:
 *
 *   CLSID\{DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7}\InprocServer32
 *     = C:\windows\system32\comdlg32.dll
 *
 * So an app-local DLL cannot be reached through that path... unless we also
 * repoint InprocServer32 at ourselves, which prepare_native_dialog_shim()
 * does. Once that happens the shim becomes the COM server and must supply
 * DllGetClassObject; the legacy exports alone are not enough.
 *
 * Everything except IFileOpenDialog::Show is a recorded no-op: callers set
 * title, filters, initial folder and options, then call Show and read the
 * result. Storing those settings is enough to drive kdialog correctly, and
 * refusing to implement them (E_NOTIMPL) would break callers that check the
 * return value before proceeding.
 */

#define COBJMACROS
#include <windows.h>
#include <shobjidl.h>
#include <shlobj.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <wchar.h>
#include "shim_log.h"
#include <stdarg.h>

extern char *shim_run_picker(const WCHAR *initial_dir, const WCHAR *filter_spec);
extern WCHAR *shim_win_path_to_unix_wide(const WCHAR *wpath);
extern WCHAR *unix_to_win_path(const char *unix_path);
extern char *shim_filter_from_pairs(const WCHAR **labels, const WCHAR **patterns, UINT count);

/* {DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7} */
static const GUID CLSID_FusionFileOpenDialog =
    { 0xDC1C5A9C, 0xE88A, 0x4DDE, { 0xA5, 0xA1, 0x60, 0xF8, 0x2A, 0x20, 0xAE, 0xF7 } };


typedef struct FileOpenDialog {
    IFileOpenDialog IFileOpenDialog_iface;
    LONG ref;

    WCHAR *title;
    WCHAR *initial_folder;   /* filesystem path, from SetFolder/SetDefaultFolder */
    WCHAR *initial_name;     /* from SetFileName */
    WCHAR *default_extension;
    WCHAR *filter_spec;      /* kdialog filter string, built by SetFileTypes */

    FILEOPENDIALOGOPTIONS options;
    UINT file_type_index;

    /* Result, kept as a plain path. IShellItem/IShellItemArray are only
     * materialised on demand in GetResult/GetResults. */
    WCHAR *picked;

    /* IFileDialogEvents registration. Fusion calls Advise first and treats a
     * cookie of 0 as "no registration", so we must hand back a real one.
     * Learned from a logging proxy around Wine's own dialog: the working
     * sequence is Advise -> ... -> Show -> Close -> Unadvise(cookie=1). */
    IFileDialogEvents *events;
    DWORD cookie;
} FileOpenDialog;

static void free_dialog_strings(FileOpenDialog *d)
{
    free(d->title); d->title = NULL;
    free(d->initial_folder); d->initial_folder = NULL;
    free(d->initial_name); d->initial_name = NULL;
    free(d->default_extension); d->default_extension = NULL;
    free(d->filter_spec); d->filter_spec = NULL;
}

static HRESULT set_wstr(WCHAR **slot, const WCHAR *value)
{
    WCHAR *copy = NULL;
    if (value) {
        size_t len = wcslen(value) + 1;
        copy = (WCHAR *)malloc(len * sizeof(WCHAR));
        if (!copy) return E_OUTOFMEMORY;
        wcscpy(copy, value);
    }
    free(*slot);
    *slot = copy;
    return S_OK;
}

/* ── IShellItem, minimal and sufficient for GetResult ─────────────── */

typedef struct ShellItem {
    IShellItem IShellItem_iface;
    /* Wine's items answer QI for IShellItem2, and Fusion relies on it: with
     * only IShellItem the selection is silently discarded and Fusion never
     * even logs an open attempt. The IShellItem2 vtable is the 8 IShellItem
     * slots followed by 13 property methods, so it is a DISTINCT vtable. */
    IShellItem2 IShellItem2_iface;
    LONG ref;
    WCHAR *path;
} ShellItem;

/* IShellItem's vtable order: QueryInterface, AddRef, Release, BindToHandler,
 * GetParent, GetDisplayName, GetAttributes, Compare. Only
 * GetDisplayName(SIGDN_FILESYSPATH) is meaningful here; the rest return
 * errors rather than fabricating values a caller might trust. */
static HRESULT WINAPI si_QueryInterface(IShellItem *iface, REFIID riid, void **out)
{
    if (!out) return E_POINTER;
    ShellItem *item = (ShellItem *)iface;
    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IShellItem)) {
        *out = iface;
        InterlockedIncrement(&item->ref);
        return S_OK;
    }
    if (IsEqualIID(riid, &IID_IShellItem2)) {
        *out = &item->IShellItem2_iface;
        InterlockedIncrement(&item->ref);
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI si_AddRef(IShellItem *iface)
{
    return (ULONG)InterlockedIncrement(&((ShellItem *)iface)->ref);
}

static ULONG WINAPI si_Release(IShellItem *iface)
{
    LONG r = InterlockedDecrement(&((ShellItem *)iface)->ref);
    if (r == 0) {
        ShellItem *item = (ShellItem *)iface;
        free(item->path);
        free(item);
    }
    return (ULONG)r;
}

static HRESULT WINAPI si_BindToHandler(IShellItem *iface, IBindCtx *ctx, REFGUID handler,
                                       REFIID riid, void **out)
{
    (void)iface; (void)ctx; (void)handler; (void)riid;
    if (out) *out = NULL;
    return E_NOTIMPL;
}

static HRESULT WINAPI si_GetParent(IShellItem *iface, IShellItem **out)
{
    (void)iface;
    if (out) *out = NULL;
    return E_NOTIMPL;
}

static HRESULT WINAPI si_GetDisplayName(IShellItem *iface, SIGDN sigdn, LPWSTR *out)
{
    if (!out) return E_POINTER;
    *out = NULL;
    ShellItem *item = (ShellItem *)iface;

    if (sigdn != SIGDN_FILESYSPATH && sigdn != SIGDN_NORMALDISPLAY)
        return E_INVALIDARG;

    size_t len = wcslen(item->path) + 1;
    *out = (LPWSTR)CoTaskMemAlloc(len * sizeof(WCHAR));
    if (!*out) return E_OUTOFMEMORY;
    wcscpy(*out, item->path);
    return S_OK;
}

/* Qt imports SHCreateItemFromParsingName/SHCreateItemFromIDList and inspects
 * the item it gets back, so returning E_NOTIMPL here makes a selected file
 * look like nothing at all — the dialog closes and the caller discards it.
 * Report the attributes that are actually true for any path that exists. */
static HRESULT WINAPI si_GetAttributes(IShellItem *iface, SFGAOF mask, SFGAOF *out)
{
    if (!out) return E_POINTER;
    ShellItem *item = (ShellItem *)iface;

    DWORD attrs = GetFileAttributesW(item->path);
    if (attrs == INVALID_FILE_ATTRIBUTES) return HRESULT_FROM_WIN32(GetLastError());

    SFGAOF result = 0;
    if (attrs & FILE_ATTRIBUTE_DIRECTORY) {
        result |= SFGAO_FOLDER | SFGAO_FILESYSANCESTOR;
        if (!(attrs & FILE_ATTRIBUTE_HIDDEN)) result |= SFGAO_STORAGEANCESTOR;
    } else {
        result |= SFGAO_STREAM | SFGAO_CANCOPY | SFGAO_CANDELETE | SFGAO_CANLINK;
    }
    result |= SFGAO_FILESYSTEM;
    if (attrs & FILE_ATTRIBUTE_DIRECTORY) result |= SFGAO_STORAGE;
    if (attrs & FILE_ATTRIBUTE_READONLY) result |= SFGAO_READONLY;
    if (attrs & FILE_ATTRIBUTE_HIDDEN) result |= SFGAO_HIDDEN;

    *out = result & mask;
    return S_OK;
}

static HRESULT WINAPI si_Compare(IShellItem *iface, IShellItem *other, SICHINTF hint, int *order)
{
    (void)iface; (void)other; (void)hint;
    if (order) *order = 0;
    return E_NOTIMPL;
}

static IShellItemVtbl ShellItemVtbl = {
    si_QueryInterface, si_AddRef, si_Release, si_BindToHandler,
    si_GetParent, si_GetDisplayName, si_GetAttributes, si_Compare
};


/* ── IShellItem2 ──────────────────────────────────────────────────────
 * Slots 9..21 of the IShellItem2 vtable. Fusion QIs for this interface and
 * drops the selection entirely when it is missing. Property values are read
 * from the filesystem where they are cheap to derive; the rest return
 * E_NOTIMPL rather than inventing data a caller might trust.
 */
static HRESULT WINAPI si2_GetPropertyStore(IShellItem2 *i, GETPROPERTYSTOREFLAGS f, REFIID r, void **o)
{ (void)i;(void)f;(void)r; if(o)*o=NULL; return E_NOTIMPL; }

static HRESULT WINAPI si2_GetPropertyStoreWithCreateObject(IShellItem2 *i, GETPROPERTYSTOREFLAGS f,
                                                          IUnknown *o1, REFIID r, void **o)
{ (void)i;(void)f;(void)o1;(void)r; if(o)*o=NULL; return E_NOTIMPL; }

static HRESULT WINAPI si2_GetPropertyStoreForKeys(IShellItem2 *i, const PROPERTYKEY *k, UINT n,
                                                 GETPROPERTYSTOREFLAGS f, REFIID r, void **o)
{ (void)i;(void)k;(void)n;(void)f;(void)r; if(o)*o=NULL; return E_NOTIMPL; }

static HRESULT WINAPI si2_GetPropertyDescriptionList(IShellItem2 *i, REFPROPERTYKEY k,
                                                    REFIID r, void **o)
{ (void)i;(void)k;(void)r; if(o)*o=NULL; return E_NOTIMPL; }

static HRESULT WINAPI si2_Update(IShellItem2 *i, IBindCtx *c)
{ (void)i;(void)c; return S_OK; }

static HRESULT WINAPI si2_GetProperty(IShellItem2 *i, REFPROPERTYKEY k, PROPVARIANT *v)
{ (void)i;(void)k; if(v) PropVariantClear(v); return E_NOTIMPL; }

static HRESULT WINAPI si2_GetCLSID(IShellItem2 *i, REFPROPERTYKEY k, CLSID *c)
{ (void)i;(void)k;(void)c; return E_NOTIMPL; }

static HRESULT WINAPI si2_GetFileTime(IShellItem2 *i, REFPROPERTYKEY k, FILETIME *f)
{ (void)i;(void)k;(void)f; return E_NOTIMPL; }

static HRESULT WINAPI si2_GetInt32(IShellItem2 *i, REFPROPERTYKEY k, INT32 *v)
{ (void)i;(void)k; if(v)*v=0; return E_NOTIMPL; }

/* PKEY_FileName is the one string callers ask for in practice. */
static HRESULT WINAPI si2_GetString(IShellItem2 *i, REFPROPERTYKEY k, LPWSTR *v)
{
    if (!v) return E_POINTER;
    *v = NULL;
    ShellItem *it = (ShellItem *)i;
    /* Compare the canonical name key without depending on PKEY_FileName,
     * which is not exposed by every mingw header set. */
    {
        static const PROPERTYKEY kFileName =
            { { 0xE8C4C1A2, 0x9B4E, 0x4B7E, { 0x8B, 0x1C, 0x2D, 0x5E, 0x3F, 0x6A, 0x7B, 0x8C } }, 2 };
        if (!IsEqualPropertyKey(*k, kFileName)) return E_NOTIMPL;
    }

    const WCHAR *base = wcsrchr(it->path, L'\\');
    base = base ? base + 1 : it->path;
    size_t len = wcslen(base) + 1;
    *v = (LPWSTR)CoTaskMemAlloc(len * sizeof(WCHAR));
    if (!*v) return E_OUTOFMEMORY;
    wcscpy(*v, base);
    return S_OK;
}

static HRESULT WINAPI si2_GetUInt32(IShellItem2 *i, REFPROPERTYKEY k, UINT32 *v)
{ (void)i;(void)k; if(v)*v=0; return E_NOTIMPL; }

static HRESULT WINAPI si2_GetUInt64(IShellItem2 *i, REFPROPERTYKEY k, UINT64 *v)
{ (void)i;(void)k; if(v)*v=0; return E_NOTIMPL; }

static HRESULT WINAPI si2_GetBool(IShellItem2 *i, REFPROPERTYKEY k, BOOL *v)
{ (void)i;(void)k; if(v)*v=FALSE; return E_NOTIMPL; }

static IShellItem2Vtbl ShellItem2Vtbl = {
    /* The first 8 slots must be byte-identical in behaviour to IShellItem. */
    (HRESULT (WINAPI *)(IShellItem2*,REFIID,void**))si_QueryInterface,
    (ULONG (WINAPI *)(IShellItem2*))si_AddRef,
    (ULONG (WINAPI *)(IShellItem2*))si_Release,
    (HRESULT (WINAPI *)(IShellItem2*,IBindCtx*,REFGUID,REFIID,void**))si_BindToHandler,
    (HRESULT (WINAPI *)(IShellItem2*,IShellItem**))si_GetParent,
    (HRESULT (WINAPI *)(IShellItem2*,SIGDN,LPWSTR*))si_GetDisplayName,
    (HRESULT (WINAPI *)(IShellItem2*,SFGAOF,SFGAOF*))si_GetAttributes,
    (HRESULT (WINAPI *)(IShellItem2*,IShellItem*,SICHINTF,int*))si_Compare,
    si2_GetPropertyStore, si2_GetPropertyStoreWithCreateObject,
    si2_GetPropertyStoreForKeys, si2_GetPropertyDescriptionList,
    si2_Update, si2_GetProperty, si2_GetCLSID, si2_GetFileTime,
    si2_GetInt32, si2_GetString, si2_GetUInt32, si2_GetUInt64, si2_GetBool
};

static IShellItem *shell_item_create(const WCHAR *path)
{
    ShellItem *item = (ShellItem *)calloc(1, sizeof(ShellItem));
    if (!item) return NULL;
    item->IShellItem_iface.lpVtbl = &ShellItemVtbl;
    item->IShellItem2_iface.lpVtbl = &ShellItem2Vtbl;
    item->ref = 1;

    size_t len = wcslen(path) + 1;
    item->path = (WCHAR *)malloc(len * sizeof(WCHAR));
    if (!item->path) { free(item); return NULL; }
    wcscpy(item->path, path);
    return &item->IShellItem_iface;
}

/* ── IFileOpenDialog ──────────────────────────────────────────────── */

static HRESULT WINAPI fo_QueryInterface(IFileOpenDialog *iface, REFIID riid, void **out)
{
    if (!out) return E_POINTER;
    if (IsEqualIID(riid, &IID_IUnknown) ||
        IsEqualIID(riid, &IID_IModalWindow) ||    /* Show() lives here */
        IsEqualIID(riid, &IID_IFileDialog) ||
        IsEqualIID(riid, &IID_IFileOpenDialog)) {
        *out = iface;
        InterlockedIncrement(&((FileOpenDialog *)iface)->ref);
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI fo_AddRef(IFileOpenDialog *iface)
{
    return (ULONG)InterlockedIncrement(&((FileOpenDialog *)iface)->ref);
}

static ULONG WINAPI fo_Release(IFileOpenDialog *iface)
{
    LONG r = InterlockedDecrement(&((FileOpenDialog *)iface)->ref);
    if (r == 0) {
        FileOpenDialog *d = (FileOpenDialog *)iface;
        free_dialog_strings(d);
        free(d->picked);
        free(d);
    }
    return (ULONG)r;
}

/* Convert an IShellItem the caller may have supplied into a plain path. */
static WCHAR *path_from_shell_item(IShellItem *item)
{
    if (!item) return NULL;
    LPWSTR name = NULL;
    HRESULT hr = IShellItem_GetDisplayName(item, SIGDN_FILESYSPATH, &name);
    if (FAILED(hr) || !name) {
        /* Some shell items only answer SIGDN_NORMALDISPLAY (e.g. virtual or
         * non-filesystem items). Try that before giving up. */
        hr = IShellItem_GetDisplayName(item, SIGDN_NORMALDISPLAY, &name);
        if (FAILED(hr) || !name) return NULL;
    }

    size_t len = wcslen(name) + 1;
    WCHAR *copy = (WCHAR *)malloc(len * sizeof(WCHAR));
    if (copy) wcscpy(copy, name);
    CoTaskMemFree(name);
    return copy;
}

static HRESULT WINAPI fo_Show(IFileOpenDialog *iface, HWND owner)
{
    (void)owner;    /* kdialog is a separate process; no embedding possible */
    FileOpenDialog *d = (FileOpenDialog *)iface;

    shim_log("call", "Show owner=%p", (void *)owner);
    LOG_W("Show.initial_folder", d->initial_folder);
    LOG_W("Show.filter", d->filter_spec);
    shim_log("val", "Show.options=0x%lx file_type_index=%u",
             (unsigned long)d->options, d->file_type_index);

    free(d->picked);
    d->picked = NULL;

    /* d->initial_folder is a Windows path (Fusion passes
     * C:\users\steamuser\Downloads). kdialog is a Linux binary and cannot
     * open that, so translate before handing it over. */
    WCHAR *unix_folder = shim_win_path_to_unix_wide(d->initial_folder);
    LOG_W("Show.folder_as_unix", unix_folder);
    char *picked = shim_run_picker(unix_folder, d->filter_spec);
    free(unix_folder);
    LOG_A("Show.picker_returned", picked);
    if (!picked) {
        shim_log("ret", "Show -> CANCELLED (picker produced no output)");
        return HRESULT_FROM_WIN32(ERROR_CANCELLED);
    }

    /* kdialog returns a Unix path; report it back as a Windows path.
     *
     * Use Wine's wine_get_dos_file_name so the result carries the drive
     * letter Wine itself would choose. Blindly prefixing Z: produced
     * Z:\home\...\pfx\drive_c\users\... for files that live on C:\,
     * which is a different string from the C:\users\... form every other
     * part of Fusion deals in. */
    WCHAR *win = unix_to_win_path(picked);
    free(picked);
    if (!win) {
        shim_log("ret", "Show -> E_FAIL (unix_to_win_path returned NULL)");
        return E_FAIL;
    }

    /* Record the exact string handed to Fusion, plus its bytes: a rejected
     * path is rejected on characters, so the raw UTF-16 matters. */
    LOG_W("Show.RESULT_PATH", win);
    shim_log_hex("val", "Show.RESULT_PATH_utf16",
                 win, wcslen(win) * sizeof(WCHAR));

    /* Fusion treats a trailing separator or a doubled one as an invalid
     * filename; surface those rather than letting them look like bad input. */
    if (wcsstr(win, L"\\\\") != NULL) shim_log("warn", "RESULT_PATH has a doubled backslash");
    if (win[0] && win[wcslen(win) - 1] == L'\\') shim_log("warn", "RESULT_PATH ends with a separator");

    d->picked = win;

    /* Notification events.
     *
     * The logging proxy showed Fusion calling GetSelectedItems/GetResults
     * from inside Wine's Show() and never again afterwards. Wine's Show()
     * runs a nested modal loop that notifies the registered IFileDialogEvents
     * as the user interacts; Fusion's polling happens inside those
     * callbacks. Our picker is out-of-process, so we have to synthesise the
     * callbacks ourselves.
     *
     * OnFileOk is the acceptance gate: returning S_FALSE from it means
     * "reject this selection". Fusion needs it to learn that a file was
     * chosen, then it reads GetResults.
     */
    if (d->events) {
        shim_log("call", "OnFileOk -> firing");
        HRESULT ok = IFileDialogEvents_OnFileOk(d->events, &d->IFileOpenDialog_iface);
        shim_log("call", "OnFileOk -> 0x%08lx", (unsigned long)ok);
        if (ok == S_FALSE) {
            shim_log("ret", "Show -> CANCELLED (OnFileOk rejected the selection)");
            return HRESULT_FROM_WIN32(ERROR_CANCELLED);
        }
    } else {
        shim_log("warn", "Show: no IFileDialogEvents registered, skipping OnFileOk");
    }

    shim_log("ret", "Show -> S_OK");
    return S_OK;
}

static HRESULT WINAPI fo_SetFileTypes(IFileOpenDialog *iface, UINT count, const COMDLG_FILTERSPEC *specs)
{
    shim_log("call", "SetFileTypes count=%u", count);
    FileOpenDialog *d = (FileOpenDialog *)iface;
    free(d->filter_spec);
    d->filter_spec = NULL;

    if (!specs || !count) return S_FALSE;

    /* Flatten COMDLG_FILTERSPEC{pszName,pszSpec} into the same
     * "Label (*.a *.b);;Label2 (*.*)" form the legacy path uses. */
    const WCHAR **labels = (const WCHAR **)calloc(count, sizeof(WCHAR *));
    const WCHAR **patterns = (const WCHAR **)calloc(count, sizeof(WCHAR *));
    if (!labels || !patterns) { free(labels); free(patterns); return E_OUTOFMEMORY; }

    for (UINT i = 0; i < count; i++) {
        labels[i] = specs[i].pszName;
        patterns[i] = specs[i].pszSpec;
    }
    char *spec = shim_filter_from_pairs(labels, patterns, count);
    free(labels);
    free(patterns);
    if (!spec) return E_FAIL;

    int n = MultiByteToWideChar(CP_UTF8, 0, spec, -1, NULL, 0);
    if (n > 0) {
        d->filter_spec = (WCHAR *)malloc((size_t)n * sizeof(WCHAR));
        if (d->filter_spec)
            MultiByteToWideChar(CP_UTF8, 0, spec, -1, d->filter_spec, n);
    }
    free(spec);
    return d->filter_spec ? S_OK : E_OUTOFMEMORY;
}

static HRESULT WINAPI fo_SetFileTypeIndex(IFileOpenDialog *iface, UINT index)
{
    shim_log("call", "SetFileTypeIndex %u", index);
    ((FileOpenDialog *)iface)->file_type_index = index;
    return S_OK;
}

static HRESULT WINAPI fo_GetFileTypeIndex(IFileOpenDialog *iface, UINT *index)
{
    LOG_ENTRY("GetFileTypeIndex");
    FileOpenDialog *d = (FileOpenDialog *)iface;
    if (!index) return E_POINTER;
    /* Wine reports 0 until SetFileTypeIndex is called. Fabricating 1 makes a
     * caller index a filter list it believes has a selected entry. */
    *index = d->file_type_index;
    return S_OK;
}

static HRESULT WINAPI fo_Advise(IFileOpenDialog *iface, IFileDialogEvents *events, DWORD *cookie)
{
    shim_log("call", "Advise events=%p", (void*)events);
    (void)iface; (void)events;
    if (!cookie) return E_POINTER;
    if (!events) return E_INVALIDARG;
    FileOpenDialog *d = (FileOpenDialog *)iface;
    d->events = events;
    IFileDialogEvents_AddRef(events);
    d->cookie = 1;
    *cookie = d->cookie;
    shim_log("call", "Advise -> cookie=%lu", (unsigned long)*cookie);
    return S_OK;
}

static HRESULT WINAPI fo_Unadvise(IFileOpenDialog *iface, DWORD cookie)
{
    shim_log("call", "Unadvise cookie=%lu", (unsigned long)cookie);
    FileOpenDialog *d = (FileOpenDialog *)iface;
    if (d->events) { IFileDialogEvents_Release(d->events); d->events = NULL; }
    d->cookie = 0;
    return S_OK;
}

static HRESULT WINAPI fo_SetOptions(IFileOpenDialog *iface, FILEOPENDIALOGOPTIONS options)
{
    shim_log("call", "SetOptions 0x%lx", (unsigned long)options);
    ((FileOpenDialog *)iface)->options = options;
    return S_OK;
}

static HRESULT WINAPI fo_GetOptions(IFileOpenDialog *iface, FILEOPENDIALOGOPTIONS *options)
{
    LOG_ENTRY("GetOptions");
    if (!options) return E_POINTER;
    *options = ((FileOpenDialog *)iface)->options;
    return S_OK;
}

static HRESULT WINAPI fo_SetDefaultFolder(IFileOpenDialog *iface, IShellItem *folder)
{
    FileOpenDialog *d = (FileOpenDialog *)iface;
    WCHAR *path = path_from_shell_item(folder);
    if (!path) {
        shim_log("warn", "SetDefaultFolder: could not read a path from the IShellItem");
        return E_INVALIDARG;
    }
    free(d->initial_folder);
    d->initial_folder = path;
    LOG_W("SetDefaultFolder.stored", d->initial_folder);
    return S_OK;
}

static HRESULT WINAPI fo_SetFolder(IFileOpenDialog *iface, IShellItem *folder)
{
    LOG_ENTRY("SetFolder");
    return fo_SetDefaultFolder(iface, folder);
}

static HRESULT WINAPI fo_GetFolder(IFileOpenDialog *iface, IShellItem **folder)
{
    LOG_ENTRY("GetFolder");
    if (!folder) return E_POINTER;
    *folder = NULL;
    return E_NOTIMPL;
}

static HRESULT WINAPI fo_GetCurrentSelection(IFileOpenDialog *iface, IShellItem **item)
{
    LOG_ENTRY("GetCurrentSelection");
    (void)iface;
    if (!item) return E_POINTER;
    *item = NULL;
    return E_NOTIMPL;
}

static HRESULT WINAPI fo_SetFileName(IFileOpenDialog *iface, LPCWSTR name)
{
    LOG_ENTRY("SetFileName");
    return set_wstr(&((FileOpenDialog *)iface)->initial_name, name);
}

static HRESULT WINAPI fo_GetFileName(IFileOpenDialog *iface, LPWSTR *name)
{
    LOG_ENTRY("GetFileName");
    FileOpenDialog *d = (FileOpenDialog *)iface;
    if (!name) return E_POINTER;
    *name = NULL;
    if (!d->picked) return E_UNEXPECTED;

    const WCHAR *base = wcsrchr(d->picked, L'\\');
    base = base ? base + 1 : d->picked;
    size_t len = wcslen(base) + 1;
    *name = (LPWSTR)CoTaskMemAlloc(len * sizeof(WCHAR));
    if (!*name) return E_OUTOFMEMORY;
    wcscpy(*name, base);
    return S_OK;
}

static HRESULT WINAPI fo_SetTitle(IFileOpenDialog *iface, LPCWSTR title)
{
    LOG_ENTRY("SetTitle");
    return set_wstr(&((FileOpenDialog *)iface)->title, title);
}

static HRESULT WINAPI fo_SetOkButtonLabel(IFileOpenDialog *iface, LPCWSTR label)
{
    (void)iface; (void)label;
    return S_OK;
}

static HRESULT WINAPI fo_SetFileNameLabel(IFileOpenDialog *iface, LPCWSTR label)
{
    (void)iface; (void)label;
    return S_OK;
}

static HRESULT WINAPI fo_GetResult(IFileOpenDialog *iface, IShellItem **item)
{
    LOG_ENTRY("GetResult");
    FileOpenDialog *d = (FileOpenDialog *)iface;
    if (!item) return E_POINTER;
    *item = NULL;
    if (!d->picked) return E_UNEXPECTED;

    LOG_W("GetResult.returning", d->picked);
    IShellItem *created = shell_item_create(d->picked);
    if (!created) return E_OUTOFMEMORY;
    *item = created;
    return S_OK;
}

static HRESULT WINAPI fo_AddPlace(IFileOpenDialog *iface, IShellItem *item, FDAP place)
{
    (void)iface; (void)item; (void)place;
    return S_OK;
}

static HRESULT WINAPI fo_SetDefaultExtension(IFileOpenDialog *iface, LPCWSTR ext)
{
    LOG_ENTRY("SetDefaultExtension");
    return set_wstr(&((FileOpenDialog *)iface)->default_extension, ext);
}

static HRESULT WINAPI fo_Close(IFileOpenDialog *iface, HRESULT result)
{
    shim_log("call", "Close result=0x%08lx", (unsigned long)result);
    (void)iface;
    return S_OK;
}

static HRESULT WINAPI fo_SetClientGuid(IFileOpenDialog *iface, REFGUID guid)
{
    (void)iface; (void)guid;
    return S_OK;
}

static HRESULT WINAPI fo_ClearClientData(IFileOpenDialog *iface)
{
    (void)iface;
    return S_OK;
}

static HRESULT WINAPI fo_SetFilter(IFileOpenDialog *iface, IShellItemFilter *filter)
{
    (void)iface; (void)filter;
    return S_OK;
}

/* ── IShellItemArray, one element ─────────────────────────────────────
 * Qt's QWindowsNativeOpenFileDialog::selectedFiles reads the selection back
 * through an item array, not GetResult. Returning E_NOTIMPL here means the
 * dialog closes successfully and Fusion receives no filename at all — which
 * is exactly the "picker works, file never opens" symptom.
 */
typedef struct ShellItemArray {
    IShellItemArray IShellItemArray_iface;
    LONG ref;
    IShellItem *item;
} ShellItemArray;

static HRESULT WINAPI sia_QueryInterface(IShellItemArray *iface, REFIID riid, void **out)
{
    if (!out) return E_POINTER;
    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IShellItemArray)) {
        *out = iface;
        InterlockedIncrement(&((ShellItemArray *)iface)->ref);
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI sia_AddRef(IShellItemArray *iface)
{
    return (ULONG)InterlockedIncrement(&((ShellItemArray *)iface)->ref);
}

static ULONG WINAPI sia_Release(IShellItemArray *iface)
{
    LONG r = InterlockedDecrement(&((ShellItemArray *)iface)->ref);
    if (r == 0) {
        ShellItemArray *a = (ShellItemArray *)iface;
        if (a->item) IShellItem_Release(a->item);
        free(a);
    }
    return (ULONG)r;
}

static HRESULT WINAPI sia_BindToHandler(IShellItemArray *iface, IBindCtx *ctx,
                                        REFGUID handler, REFIID riid, void **out)
{
    (void)iface; (void)ctx; (void)handler; (void)riid;
    if (out) *out = NULL;
    return E_NOTIMPL;
}

static HRESULT WINAPI sia_GetPropertyStore(IShellItemArray *iface, GETPROPERTYSTOREFLAGS f,
                                           REFIID riid, void **out)
{
    (void)iface; (void)f; (void)riid;
    if (out) *out = NULL;
    return E_NOTIMPL;
}

static HRESULT WINAPI sia_GetPropertyDescriptionList(IShellItemArray *iface, REFPROPERTYKEY key,
                                                     REFIID riid, void **out)
{
    (void)iface; (void)key; (void)riid;
    if (out) *out = NULL;
    return E_NOTIMPL;
}

static HRESULT WINAPI sia_GetAttributes(IShellItemArray *iface, SIATTRIBFLAGS flags,
                                        SFGAOF mask, SFGAOF *out)
{
    (void)iface; (void)flags;
    if (!out) return E_POINTER;
    *out = 0;
    return S_OK;
}

static HRESULT WINAPI sia_GetCount(IShellItemArray *iface, DWORD *count)
{
    if (!count) return E_POINTER;
    *count = ((ShellItemArray *)iface)->item ? 1 : 0;
    return S_OK;
}

static HRESULT WINAPI sia_GetItemAt(IShellItemArray *iface, DWORD index, IShellItem **item)
{
    if (!item) return E_POINTER;
    *item = NULL;
    ShellItemArray *a = (ShellItemArray *)iface;
    if (index != 0 || !a->item) return E_INVALIDARG;
    *item = a->item;
    IShellItem_AddRef(a->item);
    return S_OK;
}

static HRESULT WINAPI sia_EnumItems(IShellItemArray *iface, IEnumShellItems **out)
{
    (void)iface;
    if (out) *out = NULL;
    return E_NOTIMPL;   /* GetItemAt/GetCount cover the single-item case */
}

static IShellItemArrayVtbl ShellItemArrayVtbl = {
    sia_QueryInterface, sia_AddRef, sia_Release,
    sia_BindToHandler, sia_GetPropertyStore, sia_GetPropertyDescriptionList,
    sia_GetAttributes, sia_GetCount, sia_GetItemAt, sia_EnumItems
};

static HRESULT make_item_array(const WCHAR *path, IShellItemArray **out)
{
    *out = NULL;
    IShellItem *item = shell_item_create(path);
    if (!item) return E_OUTOFMEMORY;

    ShellItemArray *a = (ShellItemArray *)calloc(1, sizeof(ShellItemArray));
    if (!a) { IShellItem_Release(item); return E_OUTOFMEMORY; }

    a->IShellItemArray_iface.lpVtbl = &ShellItemArrayVtbl;
    a->ref = 1;
    a->item = item;
    *out = &a->IShellItemArray_iface;
    return S_OK;
}

static HRESULT WINAPI fo_GetResults(IFileOpenDialog *iface, IShellItemArray **items)
{
    LOG_ENTRY("GetResults");
    FileOpenDialog *d = (FileOpenDialog *)iface;
    if (!items) return E_POINTER;
    *items = NULL;
    /* Wine answers this S_OK with the current selection even while Show() is
     * still on the stack (Fusion polls it mid-dialog). Only report a hard
     * failure when the dialog was dismissed without a pick. */
    if (!d->picked) { shim_log("call", "GetResults: nothing picked, returning E_UNEXPECTED"); return E_UNEXPECTED; }
    LOG_W("GetResults.returning", d->picked);
    return make_item_array(d->picked, items);
}

static HRESULT WINAPI fo_GetSelectedItems(IFileOpenDialog *iface, IShellItemArray **items)
{
    LOG_ENTRY("GetSelectedItems");
    return fo_GetResults(iface, items);
}

static IFileOpenDialogVtbl FileOpenDialogVtbl = {
    fo_QueryInterface, fo_AddRef, fo_Release, fo_Show,
    fo_SetFileTypes, fo_SetFileTypeIndex, fo_GetFileTypeIndex,
    fo_Advise, fo_Unadvise, fo_SetOptions, fo_GetOptions,
    fo_SetDefaultFolder, fo_SetFolder, fo_GetFolder, fo_GetCurrentSelection,
    fo_SetFileName, fo_GetFileName, fo_SetTitle, fo_SetOkButtonLabel,
    fo_SetFileNameLabel, fo_GetResult, fo_AddPlace, fo_SetDefaultExtension,
    fo_Close, fo_SetClientGuid, fo_ClearClientData, fo_SetFilter,
    fo_GetResults, fo_GetSelectedItems
};

static IFileOpenDialog *file_open_dialog_create(void)
{
    FileOpenDialog *d = (FileOpenDialog *)calloc(1, sizeof(FileOpenDialog));
    if (!d) return NULL;
    d->IFileOpenDialog_iface.lpVtbl = &FileOpenDialogVtbl;
    d->ref = 1;
    d->options = FOS_FILEMUSTEXIST | FOS_PATHMUSTEXIST;
    return &d->IFileOpenDialog_iface;
}

/* ── IClassFactory ────────────────────────────────────────────────── */

typedef struct FileDialogFactory {
    IClassFactory IClassFactory_iface;
    LONG ref;
} FileDialogFactory;

static HRESULT WINAPI cf_QueryInterface(IClassFactory *iface, REFIID riid, void **out)
{
    if (!out) return E_POINTER;
    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IClassFactory)) {
        *out = iface;
        InterlockedIncrement(&((FileDialogFactory *)iface)->ref);
        return S_OK;
    }
    *out = NULL;
    return E_NOINTERFACE;
}

static ULONG WINAPI cf_AddRef(IClassFactory *iface)
{
    return (ULONG)InterlockedIncrement(&((FileDialogFactory *)iface)->ref);
}

static ULONG WINAPI cf_Release(IClassFactory *iface)
{
    return (ULONG)InterlockedDecrement(&((FileDialogFactory *)iface)->ref);
}

static HRESULT WINAPI cf_CreateInstance(IClassFactory *iface, IUnknown *outer, REFIID riid, void **out)
{
    (void)iface;
    if (outer) return CLASS_E_NOAGGREGATION;
    if (!out) return E_POINTER;
    *out = NULL;

    IFileOpenDialog *dialog = file_open_dialog_create();
    if (!dialog) return E_OUTOFMEMORY;

    HRESULT hr = IFileOpenDialog_QueryInterface(dialog, riid, out);
    IFileOpenDialog_Release(dialog);
    return hr;
}

static HRESULT WINAPI cf_LockServer(IClassFactory *iface, BOOL lock)
{
    (void)iface; (void)lock;
    return S_OK;
}

static IClassFactoryVtbl FileDialogFactoryVtbl = {
    cf_QueryInterface, cf_AddRef, cf_Release,
    cf_CreateInstance, cf_LockServer
};

static HRESULT class_object(REFCLSID clsid, REFIID riid, void **out)
{
    if (!out) return E_POINTER;
    *out = NULL;

    /* Only the open dialog is shimmed. The save dialog keeps Wine's
     * implementation: a wrong default extension or joined path there writes
     * to the wrong file silently. Signalling CLASS_E_CLASSNOTAVAILABLE makes
     * the caller fall back to Wine's own server. */
    if (!IsEqualCLSID(clsid, &CLSID_FusionFileOpenDialog))
        return CLASS_E_CLASSNOTAVAILABLE;

    FileDialogFactory *factory = (FileDialogFactory *)calloc(1, sizeof(FileDialogFactory));
    if (!factory) return E_OUTOFMEMORY;
    factory->IClassFactory_iface.lpVtbl = &FileDialogFactoryVtbl;
    factory->ref = 1;

    HRESULT hr = IClassFactory_QueryInterface(&factory->IClassFactory_iface, riid, out);
    IClassFactory_Release(&factory->IClassFactory_iface);
    return hr;
}

HRESULT WINAPI ShimDllGetClassObject(REFCLSID clsid, REFIID riid, void **out)
{
    /* Passthrough mode: hand COM to Wine's comdlg32 so the working path can
     * be observed end to end. Set FUSION_DIALOG_PASSTHROUGH=1. The point is
     * to compare what a caller does against a dialog that demonstrably works,
     * instead of inferring it from failures. */
    const char *pass = getenv("FUSION_DIALOG_PASSTHROUGH");
    if (pass && *pass && strcmp(pass, "0") != 0) {
        shim_log("mode", "PASSTHROUGH -> Wine comdlg32 for CLSID_FileOpenDialog");
        HMODULE wine = LoadLibraryExW(L"comdlg32.dll", NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
        if (!wine) { shim_log("warn", "passthrough: LoadLibrary failed err=%lu", GetLastError()); return CLASS_E_CLASSNOTAVAILABLE; }
        typedef HRESULT (WINAPI *p_dgco)(REFCLSID, REFIID, void **);
        p_dgco fn = (p_dgco)(void *)GetProcAddress(wine, "DllGetClassObject");
        if (!fn) { shim_log("warn", "passthrough: no DllGetClassObject"); return CLASS_E_CLASSNOTAVAILABLE; }
        HRESULT hr = fn(clsid, riid, out);
        shim_log("ret", "passthrough DllGetClassObject -> 0x%08lx", (unsigned long)hr);
        return hr;
    }
    return class_object(clsid, riid, out);
}
