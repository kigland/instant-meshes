#ifndef NATIVE_FILE_DIALOG_H
#define NATIVE_FILE_DIALOG_H

#ifdef __cplusplus
extern "C" {
#endif

/// Opens a native macOS file open dialog. Returns malloc'd path or NULL.
/// `extensions` is a null-terminated array of file extensions (e.g., {"obj","ply",NULL})
char *native_open_dialog(const char **extensions);

/// Opens a native macOS file save dialog. Returns malloc'd path or NULL.
char *native_save_dialog(const char *default_name);

#ifdef __cplusplus
}
#endif

#endif
