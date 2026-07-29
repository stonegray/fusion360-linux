#!/usr/bin/env python3
import os
import shlex
import shutil
import subprocess
import sys
import tkinter as tk
from tkinter import filedialog, messagebox

config_file = sys.argv[1]
user_interface_mode = sys.argv[2] if len(sys.argv) > 2 else "hold"

CONFIG_KEYS = [
    "PROTON",
    "STEAM_COMPAT_DATA_PATH",
    "STEAM_COMPAT_CLIENT_INSTALL_PATH",
    "FUSION_ROOT",
    "BROWSER",
    "BROWSER_LISTENER",
    "CALLBACK_HANDLER",
    "CHROME",
    "FUSION_OVERLAY_KILLER",
    "FUSION_WINE_RESTART_SCRIPT",
    "FUSION_WINE_DPI",
    "FUSION_WINE_SCALE_PERCENT",
    "FUSION_WINE_DPI_FALLBACK",
    "FUSION_WINE_SCALE_FALLBACK_PERCENT",
    "FUSION_PROTON_USE_WINED3D",
    "FUSION_PROTON_USE_XALIA",
    "FUSION_DXVK_ASYNC",
    "FUSION_NO_AT_BRIDGE",
    "FUSION_FIX_BCP47LANGS",
    "FUSION_WEBVIEW_NO_SANDBOX",
    "FUSION_WEBVIEW_DISABLE_GPU",
    "FUSION_USE_INTEL_VK_ICD",
    "FUSION_STAGING_WRITECOPY",
    "FUSION_HEAP_DELAY_FREE",
    "FUSION_ENABLE_OVERLAY_KILLER",
    "FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT",
]

RESTART_REQUIRED_KEYS = {
    "PROTON",
    "STEAM_COMPAT_DATA_PATH",
    "STEAM_COMPAT_CLIENT_INSTALL_PATH",
    "FUSION_WINE_SCALE_PERCENT",
    "FUSION_WINE_SCALE_FALLBACK_PERCENT",
    "FUSION_WINE_DPI",
    "FUSION_WINE_DPI_FALLBACK",
    "FUSION_PROTON_USE_WINED3D",
    "FUSION_PROTON_USE_XALIA",
    "FUSION_DXVK_ASYNC",
    "FUSION_NO_AT_BRIDGE",
    "FUSION_FIX_BCP47LANGS",
    "FUSION_WEBVIEW_NO_SANDBOX",
    "FUSION_WEBVIEW_DISABLE_GPU",
    "FUSION_USE_INTEL_VK_ICD",
    "FUSION_STAGING_WRITECOPY",
    "FUSION_HEAP_DELAY_FREE",
}


def getenv(name, default=""):
    return os.environ.get(name, default)


def read_gsettings_number(schema_name, key_name):
    if shutil.which("gsettings") is None:
        return None

    result = subprocess.run(
        ["gsettings", "get", schema_name, key_name],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )

    for token in result.stdout.replace("'", " ").split():
        cleaned_token = token.strip()
        if cleaned_token.replace(".", "", 1).isdigit():
            return float(cleaned_token)

    return None


def percent_to_dpi(percent):
    return int((96 * int(percent) / 100) + 0.5)


def dpi_to_percent(dpi):
    return int((int(dpi) * 100 / 96) + 0.5)


def detected_cinnamon_scale_percent():
    text_scale = read_gsettings_number("org.cinnamon.desktop.interface", "text-scaling-factor")
    window_scale = read_gsettings_number("org.cinnamon.desktop.interface", "scaling-factor")

    if text_scale and text_scale > 0 and text_scale != 1:
        return int((text_scale * 100) + 0.5)

    if window_scale and window_scale > 1:
        return int((window_scale * 100) + 0.5)

    return None


def read_kde_forced_dpi():
    """Read KDE Plasma forced font DPI from kdeglobals."""
    kconfig = shutil.which("kreadconfig5")
    if kconfig is None:
        return None
    try:
        result = subprocess.run(
            [kconfig, "--file", os.path.expanduser("~/.config/kdeglobals"),
             "--group", "General", "--key", "forceFontDPI"],
            check=False, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True
        )
        dpi_str = result.stdout.strip()
        if dpi_str.isdigit() and int(dpi_str) > 0:
            return int(dpi_str)
    except Exception:
        pass
    return None


def detected_kde_scale_percent():
    """Convert KDE forced DPI to scale percent."""
    dpi = read_kde_forced_dpi()
    if dpi and dpi > 0:
        return dpi_to_percent(dpi)
    return None


def read_xft_dpi():
    """Read Xft.dpi from xrdb (set by KDE font DPI, .Xresources, etc.)."""
    xrdb = shutil.which("xrdb")
    if xrdb is None:
        return None
    try:
        result = subprocess.run(
            [xrdb, "-query"],
            check=False, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True
        )
        for line in result.stdout.splitlines():
            if line.startswith("Xft.dpi:"):
                dpi_str = line.split(":", 1)[1].strip()
                if dpi_str.isdigit() and int(dpi_str) > 0:
                    return int(dpi_str)
    except Exception:
        pass
    return None


def detected_xft_scale_percent():
    """Convert Xft.dpi to scale percent."""
    dpi = read_xft_dpi()
    if dpi and dpi > 0:
        return dpi_to_percent(dpi)
    return None


def initial_scale_percent():
    scale_percent = getenv("FUSION_WINE_SCALE_PERCENT", "auto")
    legacy_dpi = getenv("FUSION_WINE_DPI", "auto")
    fallback_scale_percent = getenv("FUSION_WINE_SCALE_FALLBACK_PERCENT", "150")
    legacy_fallback_dpi = getenv("FUSION_WINE_DPI_FALLBACK", "144")

    if scale_percent.isdigit():
        return int(scale_percent)

    if legacy_dpi.isdigit():
        return dpi_to_percent(legacy_dpi)

    detected_scale = detected_cinnamon_scale_percent()
    if not detected_scale:
        detected_scale = detected_kde_scale_percent()
    if not detected_scale:
        detected_scale = detected_xft_scale_percent()
    if detected_scale:
        return detected_scale

    if legacy_fallback_dpi.isdigit():
        return dpi_to_percent(legacy_fallback_dpi)

    return 150


paths = {
    "PROTON": getenv("PROTON"),
    "STEAM_COMPAT_DATA_PATH": getenv("STEAM_COMPAT_DATA_PATH"),
    "STEAM_COMPAT_CLIENT_INSTALL_PATH": getenv("STEAM_COMPAT_CLIENT_INSTALL_PATH"),
    "FUSION_ROOT": getenv("FUSION_ROOT"),
    "BROWSER": getenv("BROWSER"),
    "BROWSER_LISTENER": getenv("BROWSER_LISTENER"),
    "CALLBACK_HANDLER": getenv("CALLBACK_HANDLER"),
    "CHROME": getenv("CHROME"),
    "FUSION_OVERLAY_KILLER": getenv("FUSION_OVERLAY_KILLER"),
    "FUSION_WINE_RESTART_SCRIPT": getenv("FUSION_WINE_RESTART_SCRIPT"),
    "FUSION_WINE_DPI": getenv("FUSION_WINE_DPI", "auto"),
    "FUSION_WINE_SCALE_PERCENT": getenv("FUSION_WINE_SCALE_PERCENT", "auto"),
    "FUSION_WINE_DPI_FALLBACK": getenv("FUSION_WINE_DPI_FALLBACK", "144"),
    "FUSION_WINE_SCALE_FALLBACK_PERCENT": getenv("FUSION_WINE_SCALE_FALLBACK_PERCENT", "150"),
    "FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT": getenv("FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT", "25"),
}

flags = {
    "FUSION_PROTON_USE_WINED3D": getenv("FUSION_PROTON_USE_WINED3D", "0"),
    "FUSION_PROTON_USE_XALIA": getenv("FUSION_PROTON_USE_XALIA", "0"),
    "FUSION_DXVK_ASYNC": getenv("FUSION_DXVK_ASYNC", "1"),
    "FUSION_NO_AT_BRIDGE": getenv("FUSION_NO_AT_BRIDGE", "1"),
    "FUSION_FIX_BCP47LANGS": getenv("FUSION_FIX_BCP47LANGS", "1"),
    "FUSION_WEBVIEW_NO_SANDBOX": getenv("FUSION_WEBVIEW_NO_SANDBOX", "0"),
    "FUSION_WEBVIEW_DISABLE_GPU": getenv("FUSION_WEBVIEW_DISABLE_GPU", "0"),
    "FUSION_USE_INTEL_VK_ICD": getenv("FUSION_USE_INTEL_VK_ICD", "1"),
    "FUSION_STAGING_WRITECOPY": getenv("FUSION_STAGING_WRITECOPY", "0"),
    "FUSION_HEAP_DELAY_FREE": getenv("FUSION_HEAP_DELAY_FREE", "0"),
    "FUSION_ENABLE_OVERLAY_KILLER": getenv("FUSION_ENABLE_OVERLAY_KILLER", "1"),
}

path_rows = [
    ("Proton executable", "PROTON", "file"),
    ("Proton prefix", "STEAM_COMPAT_DATA_PATH", "dir"),
    ("Steam install directory", "STEAM_COMPAT_CLIENT_INSTALL_PATH", "dir"),
    ("Fusion production directory", "FUSION_ROOT", "dir"),
    ("Browser bridge script", "BROWSER", "file"),
    ("Browser listener script", "BROWSER_LISTENER", "file"),
    ("Callback handler script", "CALLBACK_HANDLER", "file"),
    ("Chrome executable", "CHROME", "file"),
    ("Grey overlay killer script", "FUSION_OVERLAY_KILLER", "file"),
    ("Wine restart script", "FUSION_WINE_RESTART_SCRIPT", "file"),
]

flag_rows = [
    ("Force WineD3D", "FUSION_PROTON_USE_WINED3D"),
    ("Disable Xalia", "FUSION_PROTON_USE_XALIA"),
    ("Enable DXVK async", "FUSION_DXVK_ASYNC"),
    ("Set NO_AT_BRIDGE", "FUSION_NO_AT_BRIDGE"),
    ("Apply bcp47langs override", "FUSION_FIX_BCP47LANGS"),
    ("WebView2 no-sandbox", "FUSION_WEBVIEW_NO_SANDBOX"),
    ("WebView2 disable GPU", "FUSION_WEBVIEW_DISABLE_GPU"),
    ("Force Intel Vulkan ICD", "FUSION_USE_INTEL_VK_ICD"),
    ("Enable STAGING_WRITECOPY", "FUSION_STAGING_WRITECOPY"),
    ("Enable PROTON_HEAP_DELAY_FREE", "FUSION_HEAP_DELAY_FREE"),
    ("Start grey overlay killer", "FUSION_ENABLE_OVERLAY_KILLER"),
]


def as_bool(value):
    return str(value).lower() in ("1", "yes", "true", "on", "enabled")


def normalized_flag_value(value):
    return "1" if as_bool(value) else "0"


saved_values = {}
for _, key, _ in path_rows:
    saved_values[key] = paths.get(key, "")
saved_values["FUSION_WINE_SCALE_PERCENT"] = paths["FUSION_WINE_SCALE_PERCENT"]
saved_values["FUSION_WINE_SCALE_FALLBACK_PERCENT"] = paths["FUSION_WINE_SCALE_FALLBACK_PERCENT"]
saved_values["FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT"] = paths["FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT"]
saved_values["FUSION_WINE_DPI"] = paths["FUSION_WINE_DPI"]
saved_values["FUSION_WINE_DPI_FALLBACK"] = paths["FUSION_WINE_DPI_FALLBACK"]
for key, value in flags.items():
    saved_values[key] = normalized_flag_value(value)

root = tk.Tk()
root.title("Fusion 360 launcher setup")
root.minsize(1080, 460)

entries = {}
flag_vars = {}
warning_labels = {}
revert_buttons = {}
status_warning_var = tk.StringVar()

main = tk.Frame(root, padx=12, pady=12)
main.pack(fill="both", expand=True)

tk.Label(main, text="Paths", font=("TkDefaultFont", 11, "bold")).grid(row=0, column=0, sticky="w", pady=(0, 8))
tk.Label(main, text="Current / saved value").grid(row=0, column=1, sticky="w", pady=(0, 8))
tk.Label(main, text="Changed").grid(row=0, column=3, sticky="w", pady=(0, 8))


def current_value_for_key(key):
    if key == "FUSION_WINE_SCALE_PERCENT":
        return "auto" if auto_scale_var.get() else str(scale_value_var.get())

    if key in entries:
        return entries[key].get().strip()

    if key in flag_vars:
        return "1" if flag_vars[key].get() else "0"

    if key == "FUSION_WINE_DPI":
        return "auto"

    if key == "FUSION_WINE_DPI_FALLBACK":
        fallback_scale = entries.get("FUSION_WINE_SCALE_FALLBACK_PERCENT")
        if fallback_scale is not None and fallback_scale.get().strip().isdigit():
            return str(percent_to_dpi(fallback_scale.get().strip()))
        return saved_values.get(key, "")

    return ""


def displayed_keys():
    keys = [key for _, key, _ in path_rows]
    keys.extend([
        "FUSION_WINE_SCALE_PERCENT",
        "FUSION_WINE_SCALE_FALLBACK_PERCENT",
        "FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT",
    ])
    keys.extend([key for _, key in flag_rows])
    return keys


def dirty_keys():
    return [key for key in displayed_keys() if current_value_for_key(key) != saved_values.get(key, "")]


def restart_dirty_keys():
    return [key for key in dirty_keys() if key in RESTART_REQUIRED_KEYS]


def update_global_warning():
    restart_keys = restart_dirty_keys()
    all_dirty_keys = dirty_keys()

    if restart_keys:
        status_warning_var.set("⚠ Wine restart needed for modified launch/Wine settings. Use Save and restart Wine if Fusion is already running.")
    elif all_dirty_keys:
        status_warning_var.set("Unsaved changes.")
    else:
        status_warning_var.set("")


def update_dirty_indicator(key):
    dirty = current_value_for_key(key) != saved_values.get(key, "")

    warning_label = warning_labels.get(key)
    revert_button = revert_buttons.get(key)

    if warning_label is not None:
        if dirty:
            warning_label.config(text="⚠" if key in RESTART_REQUIRED_KEYS else "•")
            warning_label.grid()
        else:
            warning_label.config(text="")
            warning_label.grid_remove()

    if revert_button is not None:
        if dirty:
            revert_button.grid()
        else:
            revert_button.grid_remove()


def update_all_dirty_indicators():
    for key in displayed_keys():
        update_dirty_indicator(key)
    update_global_warning()


def register_dirty_widgets(parent, key, row, warning_column, revert_column):
    warning = tk.Label(parent, text="", width=2, fg="#c27c00")
    warning.grid(row=row, column=warning_column, sticky="w", padx=(6, 0))
    warning.grid_remove()

    revert = tk.Button(parent, text="Revert", width=6, command=lambda selected_key=key: revert_value(selected_key))
    revert.grid(row=row, column=revert_column, sticky="w", padx=(4, 0))
    revert.grid_remove()

    warning_labels[key] = warning
    revert_buttons[key] = revert


def on_value_changed(_event=None):
    stop_countdown()
    update_all_dirty_indicators()


def browse_value(key, kind):
    current = entries[key].get().strip()
    if kind == "dir":
        initialdir = current if os.path.isdir(current) else os.path.expanduser("~")
        selected = filedialog.askdirectory(title=f"Select {key}", initialdir=initialdir)
    else:
        initialdir = current if os.path.isdir(current) else os.path.dirname(current) if current else os.path.expanduser("~")
        selected = filedialog.askopenfilename(title=f"Select {key}", initialdir=initialdir)
    if selected:
        entries[key].delete(0, tk.END)
        entries[key].insert(0, selected)
        on_value_changed()


for row_index, (label, key, kind) in enumerate(path_rows, start=1):
    tk.Label(main, text=label).grid(row=row_index, column=0, sticky="w", padx=(0, 8), pady=3)
    entry = tk.Entry(main, width=100)
    entry.insert(0, paths.get(key, ""))
    entry.grid(row=row_index, column=1, sticky="ew", pady=3)
    entry.bind("<KeyRelease>", on_value_changed, add="+")
    entry.bind("<FocusOut>", on_value_changed, add="+")
    tk.Button(main, text="Browse", command=lambda k=key, t=kind: browse_value(k, t)).grid(row=row_index, column=2, padx=(8, 0), pady=3)
    entries[key] = entry
    register_dirty_widgets(main, key, row_index, 3, 4)

settings_row = len(path_rows) + 2
scale_value_var = tk.IntVar(value=initial_scale_percent())
auto_scale_var = tk.IntVar(value=1 if paths["FUSION_WINE_SCALE_PERCENT"] == "auto" else 0)
scale_label_var = tk.StringVar()


def update_scale_label(_value=None):
    percent = int(scale_value_var.get())
    dpi = percent_to_dpi(percent)
    if auto_scale_var.get():
        scale_label_var.set(f"Auto from Cinnamon/current scale: {percent}% = {dpi} DPI")
    else:
        scale_label_var.set(f"{percent}% = {dpi} DPI")
    update_dirty_indicator("FUSION_WINE_SCALE_PERCENT")
    update_global_warning()


def slider_touched(_event=None):
    auto_scale_var.set(0)
    stop_countdown()
    update_scale_label()


def auto_scale_changed():
    stop_countdown()
    if auto_scale_var.get():
        detected_scale = detected_cinnamon_scale_percent()
        if detected_scale:
            scale_value_var.set(detected_scale)
    update_scale_label()


tk.Label(main, text="Wine scale %").grid(row=settings_row, column=0, sticky="w", padx=(0, 8), pady=(14, 3))
scale_frame = tk.Frame(main)
scale_frame.grid(row=settings_row, column=1, sticky="ew", pady=(14, 3))
scale_slider = tk.Scale(scale_frame, from_=75, to=300, resolution=5, orient="horizontal", variable=scale_value_var, command=update_scale_label, length=360)
scale_slider.pack(side="left")
scale_slider.bind("<Button-1>", slider_touched, add="+")
tk.Label(scale_frame, textvariable=scale_label_var, width=34, anchor="w").pack(side="left", padx=(12, 0))
tk.Checkbutton(main, text="Auto", variable=auto_scale_var, command=auto_scale_changed).grid(row=settings_row, column=2, sticky="w", padx=(8, 0), pady=(14, 3))
register_dirty_widgets(main, "FUSION_WINE_SCALE_PERCENT", settings_row, 3, 4)
update_scale_label()

tk.Label(main, text="Fallback scale %").grid(row=settings_row + 1, column=0, sticky="w", padx=(0, 8), pady=3)
scale_fallback_entry = tk.Entry(main, width=20)
scale_fallback_entry.insert(0, paths["FUSION_WINE_SCALE_FALLBACK_PERCENT"])
scale_fallback_entry.grid(row=settings_row + 1, column=1, sticky="w", pady=3)
scale_fallback_entry.bind("<KeyRelease>", on_value_changed, add="+")
scale_fallback_entry.bind("<FocusOut>", on_value_changed, add="+")
entries["FUSION_WINE_SCALE_FALLBACK_PERCENT"] = scale_fallback_entry
register_dirty_widgets(main, "FUSION_WINE_SCALE_FALLBACK_PERCENT", settings_row + 1, 3, 4)

tk.Label(main, text="Overlay size tolerance %").grid(row=settings_row + 2, column=0, sticky="w", padx=(0, 8), pady=3)
overlay_tolerance_entry = tk.Entry(main, width=20)
overlay_tolerance_entry.insert(0, paths["FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT"])
overlay_tolerance_entry.grid(row=settings_row + 2, column=1, sticky="w", pady=3)
overlay_tolerance_entry.bind("<KeyRelease>", on_value_changed, add="+")
overlay_tolerance_entry.bind("<FocusOut>", on_value_changed, add="+")
entries["FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT"] = overlay_tolerance_entry
register_dirty_widgets(main, "FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT", settings_row + 2, 3, 4)

status_warning_label = tk.Label(main, textvariable=status_warning_var, anchor="w", fg="#b36b00")
status_warning_label.grid(row=settings_row + 3, column=0, columnspan=5, sticky="ew", pady=(10, 0))

main.columnconfigure(1, weight=1)

for key, value in flags.items():
    flag_vars[key] = tk.IntVar(value=1 if as_bool(value) else 0)


def revert_value(key):
    saved_value = saved_values.get(key, "")

    if key == "FUSION_WINE_SCALE_PERCENT":
        if saved_value == "auto":
            auto_scale_var.set(1)
            detected_scale = detected_cinnamon_scale_percent()
            if detected_scale:
                scale_value_var.set(detected_scale)
        else:
            auto_scale_var.set(0)
            if str(saved_value).isdigit():
                scale_value_var.set(int(saved_value))
        update_scale_label()
        update_all_dirty_indicators()
        return

    if key in entries:
        entries[key].delete(0, tk.END)
        entries[key].insert(0, saved_value)
        update_all_dirty_indicators()
        return

    if key in flag_vars:
        flag_vars[key].set(1 if saved_value == "1" else 0)
        update_all_dirty_indicators()
        return


def open_flags_window():
    flags_window = tk.Toplevel(root)
    flags_window.title("Fusion 360 launcher flags")
    flags_window.transient(root)
    flags_window.grab_set()

    frame = tk.Frame(flags_window, padx=14, pady=14)
    frame.pack(fill="both", expand=True)

    tk.Label(frame, text="Simple launch flags", font=("TkDefaultFont", 11, "bold")).grid(row=0, column=0, columnspan=4, sticky="w", pady=(0, 8))
    tk.Label(frame, text="Changed").grid(row=0, column=1, sticky="w", pady=(0, 8))

    for row_index, (label, key) in enumerate(flag_rows, start=1):
        tk.Checkbutton(frame, text=label, variable=flag_vars[key], command=on_value_changed).grid(row=row_index, column=0, sticky="w", pady=2)
        register_dirty_widgets(frame, key, row_index, 1, 2)
        update_dirty_indicator(key)

    buttons = tk.Frame(frame)
    buttons.grid(row=len(flag_rows) + 1, column=0, columnspan=4, sticky="ew", pady=(14, 0))
    tk.Button(buttons, text="OK", command=flags_window.destroy).pack(side="right")

    update_all_dirty_indicators()
    flags_window.wait_window()


def validate_entries():
    scale_fallback = entries["FUSION_WINE_SCALE_FALLBACK_PERCENT"].get().strip()
    overlay_tolerance = entries["FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT"].get().strip()

    if not scale_fallback.isdigit():
        messagebox.showerror("Invalid fallback scale", "Fallback scale must be a number, like 100, 125, 150, or 200.")
        return False

    if not overlay_tolerance.isdigit():
        messagebox.showerror("Invalid overlay tolerance", "Overlay size tolerance must be a number.")
        return False

    return True


def collect_config_values():
    values = {}
    for key, entry in entries.items():
        values[key] = entry.get().strip()

    for key, var in flag_vars.items():
        values[key] = "1" if var.get() else "0"

    values["FUSION_WINE_SCALE_PERCENT"] = "auto" if auto_scale_var.get() else str(scale_value_var.get())
    values["FUSION_WINE_DPI"] = "auto"
    values["FUSION_WINE_DPI_FALLBACK"] = str(percent_to_dpi(values["FUSION_WINE_SCALE_FALLBACK_PERCENT"]))

    return values


def collect_display_values():
    values = collect_config_values()
    return {key: values.get(key, "") for key in displayed_keys() + ["FUSION_WINE_DPI", "FUSION_WINE_DPI_FALLBACK"]}


def write_config_values():
    if not validate_entries():
        return False

    values = collect_config_values()

    os.makedirs(os.path.dirname(config_file), exist_ok=True)

    with open(config_file, "w", encoding="utf-8") as config:
        for key in CONFIG_KEYS:
            config.write(f"{key}={shlex.quote(values.get(key, ''))}\n")

    saved_values.update(collect_display_values())
    update_all_dirty_indicators()
    return True


def restart_wine_processes():
    restart_script = collect_config_values().get("FUSION_WINE_RESTART_SCRIPT", "").strip()

    if not restart_script:
        messagebox.showerror("Restart script missing", "No Wine restart script is configured.")
        return False

    if not os.path.isfile(restart_script):
        messagebox.showerror("Restart script missing", f"Wine restart script was not found:\n\n{restart_script}")
        return False

    result = subprocess.run(["bash", restart_script], check=False)

    if result.returncode != 0:
        messagebox.showerror(
            "Wine restart failed",
            f"Wine restart script exited with status {result.returncode}:\n\n{restart_script}",
        )
        return False

    return True


def ask_save_restart_cancel(changed_keys):
    dialog = tk.Toplevel(root)
    dialog.title("Wine restart needed")
    dialog.transient(root)
    dialog.grab_set()
    dialog.resizable(False, False)

    result = tk.StringVar(value="cancel")

    frame = tk.Frame(dialog, padx=16, pady=14)
    frame.pack(fill="both", expand=True)

    tk.Label(frame, text="⚠ Wine restart needed", font=("TkDefaultFont", 11, "bold"), fg="#b36b00").pack(anchor="w")
    tk.Label(
        frame,
        text="Some modified settings are only reliable after running the configured Wine restart script.",
        justify="left",
        wraplength=560,
    ).pack(anchor="w", pady=(8, 0))

    if changed_keys:
        tk.Label(frame, text="Modified restart-related items:", justify="left").pack(anchor="w", pady=(10, 0))
        list_text = "\n".join(f"- {key}" for key in changed_keys[:12])
        if len(changed_keys) > 12:
            list_text += f"\n- ... {len(changed_keys) - 12} more"
        tk.Label(frame, text=list_text, justify="left", fg="#555555").pack(anchor="w", padx=(12, 0), pady=(2, 0))

    button_frame = tk.Frame(frame)
    button_frame.pack(fill="x", pady=(16, 0))

    def choose(value):
        result.set(value)
        dialog.destroy()

    tk.Button(button_frame, text="Cancel", command=lambda: choose("cancel")).pack(side="right", padx=(8, 0))
    tk.Button(button_frame, text="Save and restart Wine", command=lambda: choose("restart")).pack(side="right", padx=(8, 0))
    tk.Button(button_frame, text="Save", command=lambda: choose("save")).pack(side="right")

    dialog.protocol("WM_DELETE_WINDOW", lambda: choose("cancel"))
    dialog.wait_window()
    return result.get()


def save_with_optional_restart(show_saved_message=True):
    changed_restart_keys = restart_dirty_keys()

    if changed_restart_keys:
        action = ask_save_restart_cancel(changed_restart_keys)
        if action == "cancel":
            return False

        if not write_config_values():
            return False

        if action == "restart":
            if not restart_wine_processes():
                return False
            if show_saved_message:
                messagebox.showinfo("Saved", "Fusion launcher config saved. Wine restart script was run.")
        elif show_saved_message:
            messagebox.showinfo("Saved", "Fusion launcher config saved. Wine was not restarted.")

        return True

    if not write_config_values():
        return False

    if show_saved_message:
        messagebox.showinfo("Saved", "Fusion launcher config saved.")

    return True


def save_config_only():
    stop_countdown()
    save_with_optional_restart(show_saved_message=True)


def continue_launch():
    stop_countdown()
    if save_with_optional_restart(show_saved_message=False):
        root.destroy()


def cancel():
    root.destroy()
    sys.exit(1)

countdown_seconds = 5
countdown_remaining = countdown_seconds
countdown_active = user_interface_mode == "countdown"
countdown_job = None
focus_pause_enabled = False
countdown_label_var = tk.StringVar()


def stop_countdown(_event=None):
    global countdown_active
    global countdown_job

    if not countdown_active:
        return

    countdown_active = False

    if countdown_job is not None:
        root.after_cancel(countdown_job)

    countdown_label_var.set("Launch paused. Click Continue when ready.")


def stop_countdown_from_focus(_event=None):
    if focus_pause_enabled:
        stop_countdown()


def enable_focus_pause():
    global focus_pause_enabled
    focus_pause_enabled = True


def countdown_tick():
    global countdown_remaining
    global countdown_job

    if not countdown_active:
        return

    if countdown_remaining <= 0:
        continue_launch()
        return

    countdown_label_var.set(f"Launching Fusion in {countdown_remaining} seconds. Click this window to pause.")
    countdown_remaining -= 1
    countdown_job = root.after(1000, countdown_tick)


def open_flags_window_and_pause():
    stop_countdown()
    open_flags_window()

buttons = tk.Frame(main)
buttons.grid(row=settings_row + 4, column=0, columnspan=5, sticky="ew", pady=(16, 0))

countdown_label = tk.Label(buttons, textvariable=countdown_label_var, anchor="w")
countdown_label.pack(side="left", padx=(0, 12))

tk.Button(buttons, text="Flags...", command=open_flags_window_and_pause).pack(side="left")
tk.Button(buttons, text="Cancel", command=cancel).pack(side="right", padx=(8, 0))
tk.Button(buttons, text="Continue", command=continue_launch).pack(side="right", padx=(8, 0))
tk.Button(buttons, text="Save", command=save_config_only).pack(side="right")

root.bind_all("<ButtonPress>", stop_countdown, add="+")
root.bind_all("<KeyPress>", stop_countdown, add="+")
root.bind("<FocusIn>", stop_countdown_from_focus, add="+")
root.after(800, enable_focus_pause)

update_all_dirty_indicators()

if user_interface_mode == "silent":
    root.withdraw()

if user_interface_mode == "silent":
    print("Config incomplete -- saving defaults and continuing silently.")
    write_config_values()
    sys.exit(0)
elif countdown_active:
    countdown_tick()
else:
    countdown_label_var.set("Review settings, then click Continue.")
root.protocol("WM_DELETE_WINDOW", cancel)
root.mainloop()
