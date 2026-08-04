bl_info = {
    "name": "Instant Meshes Remesh",
    "author": "kigland",
    "version": (1, 0, 0),
    "blender": (3, 6, 0),
    "location": "View3D > Sidebar > Instant Meshes",
    "description": "One-click quad remeshing using Instant Meshes CLI",
    "category": "Mesh",
}

import bpy
import os
import sys
from . import operators
from . import panel
from . import preferences


def get_binary_path():
    """Find instantmeshes-cli binary."""
    prefs = bpy.context.preferences.addons[__name__].preferences

    if prefs.binary_path and os.path.isfile(prefs.binary_path):
        return prefs.binary_path

    # Auto-detect: look next to this addon
    addon_dir = os.path.dirname(__file__)
    names = ["instantmeshes-cli", "instantmeshes-cli.exe"]
    for name in names:
        path = os.path.join(addon_dir, "bin", name)
        if os.path.isfile(path):
            return path

    return None


def register():
    preferences.register()
    operators.register()
    panel.register()


def unregister():
    panel.unregister()
    operators.unregister()
    preferences.unregister()
