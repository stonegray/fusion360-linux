#ifndef SHIM_LOG_H
#define SHIM_LOG_H

#include <windows.h>
#include <stdarg.h>

/* Structured logging for the dialog shim. Off unless FUSION_DIALOG_DEBUG is
 * set, so shipped behaviour is unchanged. See shim_log.c. */

void shim_log(const char *level, const char *fmt, ...);
void shim_log_wide(const char *level, const char *label, const WCHAR *value);
void shim_log_hex(const char *level, const char *label, const void *data, size_t len);
int  shim_log_enabled(void);

#define LOG_ENTRY(name) shim_log("call", "%s", name)
#define LOG_HR(name, hr) shim_log("ret",  "%s -> 0x%08lx", name, (unsigned long)(hr))
#define LOG_W(label, value) shim_log_wide("val", label, value)
#define LOG_A(label, value) shim_log("val",  "%s=[%s]", label, (value) ? (value) : "(null)")

#endif
