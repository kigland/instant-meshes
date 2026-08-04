import bpy
from bpy.props import StringProperty
from bpy.types import AddonPreferences
import os


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
        auto = _auto_detect()
        if auto:
            layout.label(text=f"Auto-detected: {auto}", icon='CHECKMARK')
        else:
            layout.label(text="Binary not found — download from Releases", icon='ERROR')


def _auto_detect():
    addon_dir = os.path.dirname(os.path.dirname(__file__))
    names = ["instantmeshes-cli", "instantmeshes-cli.exe"]
    for name in names:
        path = os.path.join(addon_dir, "bin", name)
        if os.path.isfile(path):
            return path
    return None


def register():
    bpy.utils.register_class(InstantMeshesPreferences)


def unregister():
    bpy.utils.unregister_class(InstantMeshesPreferences)
