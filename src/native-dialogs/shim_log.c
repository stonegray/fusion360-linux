/*
 * shim_log.c - structured logging for the comdlg32 dialog shim.
 *
 * Why this exists rather than scattered one-off probes: every failure mode
 * this shim has hit was silent. A bad path, a rejected HRESULT or a picker
 * that never ran all look identical from Fusion's side — the dialog appears
 * and the file simply does not open. Each diagnosis so far needed a hand-built
 * probe, a rebuild and a user test to see one value.
 *
 * Enable with FUSION_DIALOG_DEBUG=1. Writes to
 * Z:\tmp\fusion-dialog.log by default, or FUSION_DIALOG_LOG.
 *
 * Logging must never break the dialog: every call here is best-effort and
 * returns quietly if the file cannot be opened.
 */

#include "shim_log.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static FILE *logfile = NULL;
static int   checked = 0;
static int   enabled = 0;

static void shim_log_open(void)
{
    if (checked) return;
    checked = 1;

    const char *flag = getenv("FUSION_DIALOG_DEBUG");
    if (!flag || !*flag || strcmp(flag, "0") == 0) return;

    const char *path = getenv("FUSION_DIALOG_LOG");
    if (!path || !*path) path = "Z:\\tmp\\fusion-dialog.log";

    logfile = fopen(path, "a");
    enabled = (logfile != NULL);
}

int shim_log_enabled(void)
{
    shim_log_open();
    return enabled;
}

void shim_log(const char *level, const char *fmt, ...)
{
    shim_log_open();
    if (!enabled) return;

    va_list ap;
    va_start(ap, fmt);
    fprintf(logfile, "[%s] ", level);
    vfprintf(logfile, fmt, ap);
    fputc('\n', logfile);
    va_end(ap);
    fflush(logfile);   /* the process may be killed mid-dialog */
}

void shim_log_wide(const char *level, const char *label, const WCHAR *value)
{
    shim_log_open();
    if (!enabled) return;

    char utf8[2048];
    int n = WideCharToMultiByte(CP_UTF8, 0, value ? value : L"", -1,
                                utf8, (int)sizeof utf8, NULL, NULL);
    if (n <= 0) {
        fprintf(logfile, "[%s] %s=(<unconvertible>)\n", level, label);
    } else {
        fprintf(logfile, "[%s] %s=[%s]\n", level, label, utf8);
    }
    fflush(logfile);
}

void shim_log_hex(const char *level, const char *label, const void *data, size_t len)
{
    shim_log_open();
    if (!enabled) return;

    fprintf(logfile, "[%s] %s (%zu bytes):", level, label, len);
    const unsigned char *p = (const unsigned char *)data;
    for (size_t i = 0; i < len; i++) {
        fprintf(logfile, " %02x", p[i]);
        if ((i + 1) % 32 == 0) fprintf(logfile, "\n        ");
    }
    fputc('\n', logfile);
    fflush(logfile);
}
