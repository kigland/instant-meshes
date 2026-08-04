import os
import platform
import stat
import sys

import bpy
from bpy.props import StringProperty
from bpy.types import AddonPreferences


def _ensure_bundled_binary_is_executable(path):
    if os.name == 'nt' or os.access(path, os.X_OK):
        return True

    try:
        os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
    except OSError:
        return False

    return os.access(path, os.X_OK)


def _bundled_binary_path(addon_dir):
    machine = platform.machine().lower()
    if sys.platform == 'darwin' and machine in {'arm64', 'aarch64'}:
        return os.path.join(
            addon_dir,
            "bin",
            "instantmeshes-cli-macos-arm64",
        )
    return None


def auto_detect_binary():
    """Return the bundled CLI or a binary in the legacy sibling bin folder."""
    addon_dir = os.path.dirname(os.path.abspath(__file__))
    bundled_path = _bundled_binary_path(addon_dir)
    if (
        bundled_path
        and os.path.isfile(bundled_path)
        and _ensure_bundled_binary_is_executable(bundled_path)
    ):
        return bundled_path

    legacy_bin_dir = os.path.normpath(
        os.path.join(addon_dir, os.pardir, "bin")
    )
    filenames = (
        ("instantmeshes-cli.exe",)
        if os.name == 'nt'
        else ("instantmeshes-cli",)
    )

    for filename in filenames:
        candidate = os.path.join(legacy_bin_dir, filename)
        if os.path.isfile(candidate) and (
            os.name == 'nt' or os.access(candidate, os.X_OK)
        ):
            return candidate

    return None


def get_binary_path(context=None):
    """Resolve the configured binary, then try the automatic location."""
    context = context or bpy.context
    addon = context.preferences.addons.get(__package__)
    if addon:
        configured_path = bpy.path.abspath(addon.preferences.binary_path)
        if configured_path and os.path.isfile(configured_path) and (
            os.name == 'nt' or os.access(configured_path, os.X_OK)
        ):
            return configured_path

    return auto_detect_binary()


class InstantMeshesPreferences(AddonPreferences):
    bl_idname = __package__

    binary_path: StringProperty(
        name="instantmeshes-cli Path",
        description="Path to the instantmeshes-cli executable",
        subtype='FILE_PATH',
        default="",
    )

    def draw(self, context):
        layout = self.layout
        layout.prop(self, "binary_path")

        detected_path = auto_detect_binary()
        if detected_path:
            layout.label(text="Auto-detected CLI ready", icon='CHECKMARK')
            layout.label(text=detected_path)
        elif get_binary_path(context):
            layout.label(text="Configured CLI is ready", icon='CHECKMARK')
        else:
            layout.label(text="Binary not found - download from Releases", icon='ERROR')


def register():
    bpy.utils.register_class(InstantMeshesPreferences)


def unregister():
    bpy.utils.unregister_class(InstantMeshesPreferences)
