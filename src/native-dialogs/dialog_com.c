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

extern char *shim_run_picker(const WCHAR *initial_dir, const WCHAR *filter_spec);
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

    /* Result, kept as a plain path. IShellItem/IShellItemArray are only
     * materialised on demand in GetResult/GetResults. */
    WCHAR *picked;
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
    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IShellItem)) {
        *out = iface;
        InterlockedIncrement(&((ShellItem *)iface)->ref);
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

static HRESULT WINAPI si_GetAttributes(IShellItem *iface, SFGAOF mask, SFGAOF *out)
{
    (void)iface;
    if (out) *out = 0;
    return E_NOTIMPL;
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

static IShellItem *shell_item_create(const WCHAR *path)
{
    ShellItem *item = (ShellItem *)calloc(1, sizeof(ShellItem));
    if (!item) return NULL;
    item->IShellItem_iface.lpVtbl = &ShellItemVtbl;
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
    if (FAILED(IShellItem_GetDisplayName(item, SIGDN_FILESYSPATH, &name)) || !name)
        return NULL;

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

    free(d->picked);
    d->picked = NULL;

    char *picked = shim_run_picker(d->initial_folder, d->filter_spec);
    if (!picked)
        return HRESULT_FROM_WIN32(ERROR_CANCELLED);

    /* kdialog returns a Unix path; report it back as a Windows path. */
    size_t need = strlen(picked) + 4;
    WCHAR *win = (WCHAR *)malloc(need * sizeof(WCHAR));
    if (!win) { free(picked); return E_OUTOFMEMORY; }

    int converted = MultiByteToWideChar(CP_UTF8, 0, picked, -1, win + 2, (int)need - 2);
    free(picked);
    if (converted <= 0) { free(win); return E_FAIL; }

    if (win[2] == L'/') {
        win[0] = L'Z';
        win[1] = L':';
        for (WCHAR *p = win + 2; *p; p++)
            if (*p == L'/') *p = L'\\';
    } else {
        /* Unexpected: kdialog returned something non-absolute. Move up. */
        memmove(win, win + 2, (size_t)converted * sizeof(WCHAR));
    }

    d->picked = win;
    return S_OK;
}

static HRESULT WINAPI fo_SetFileTypes(IFileOpenDialog *iface, UINT count, const COMDLG_FILTERSPEC *specs)
{
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
    (void)iface; (void)index;
    return S_OK;   /* kdialog shows all patterns; selection order is cosmetic */
}

static HRESULT WINAPI fo_GetFileTypeIndex(IFileOpenDialog *iface, UINT *index)
{
    (void)iface;
    if (!index) return E_POINTER;
    *index = 1;
    return S_OK;
}

static HRESULT WINAPI fo_Advise(IFileOpenDialog *iface, IFileDialogEvents *events, DWORD *cookie)
{
    (void)iface; (void)events;
    if (!cookie) return E_POINTER;
    *cookie = 0;
    return S_OK;
}

static HRESULT WINAPI fo_Unadvise(IFileOpenDialog *iface, DWORD cookie)
{
    (void)iface; (void)cookie;
    return S_OK;
}

static HRESULT WINAPI fo_SetOptions(IFileOpenDialog *iface, FILEOPENDIALOGOPTIONS options)
{
    ((FileOpenDialog *)iface)->options = options;
    return S_OK;
}

static HRESULT WINAPI fo_GetOptions(IFileOpenDialog *iface, FILEOPENDIALOGOPTIONS *options)
{
    if (!options) return E_POINTER;
    *options = ((FileOpenDialog *)iface)->options;
    return S_OK;
}

static HRESULT WINAPI fo_SetDefaultFolder(IFileOpenDialog *iface, IShellItem *folder)
{
    FileOpenDialog *d = (FileOpenDialog *)iface;
    WCHAR *path = path_from_shell_item(folder);
    if (!path) return E_INVALIDARG;
    free(d->initial_folder);
    d->initial_folder = path;
    return S_OK;
}

static HRESULT WINAPI fo_SetFolder(IFileOpenDialog *iface, IShellItem *folder)
{
    return fo_SetDefaultFolder(iface, folder);
}

static HRESULT WINAPI fo_GetFolder(IFileOpenDialog *iface, IShellItem **folder)
{
    if (!folder) return E_POINTER;
    *folder = NULL;
    return E_NOTIMPL;
}

static HRESULT WINAPI fo_GetCurrentSelection(IFileOpenDialog *iface, IShellItem **item)
{
    (void)iface;
    if (!item) return E_POINTER;
    *item = NULL;
    return E_NOTIMPL;
}

static HRESULT WINAPI fo_SetFileName(IFileOpenDialog *iface, LPCWSTR name)
{
    return set_wstr(&((FileOpenDialog *)iface)->initial_name, name);
}

static HRESULT WINAPI fo_GetFileName(IFileOpenDialog *iface, LPWSTR *name)
{
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
    FileOpenDialog *d = (FileOpenDialog *)iface;
    if (!item) return E_POINTER;
    *item = NULL;
    if (!d->picked) return E_UNEXPECTED;

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
    return set_wstr(&((FileOpenDialog *)iface)->default_extension, ext);
}

static HRESULT WINAPI fo_Close(IFileOpenDialog *iface, HRESULT result)
{
    (void)iface; (void)result;
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

static HRESULT WINAPI fo_GetResults(IFileOpenDialog *iface, IShellItemArray **items)
{
    (void)iface;
    if (!items) return E_POINTER;
    /* Single-selection only: this shim asks kdialog for one path. Returning
     * E_NOTIMPL would make multi-select callers fail; returning an
     * unimplemented array would be worse. Callers get a clear error. */
    *items = NULL;
    return E_NOTIMPL;
}

static HRESULT WINAPI fo_GetSelectedItems(IFileOpenDialog *iface, IShellItemArray **items)
{
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
    return class_object(clsid, riid, out);
}
