bl_info = {
    "name": "Instant Meshes Remesh",
    "author": "kigland",
    "version": (1, 0, 0),
    "blender": (3, 6, 0),
    "location": "View3D > Sidebar > Instant Meshes",
    "category": "Mesh",
}

from . import operators
from . import panel
from . import preferences


def register():
    preferences.register()
    operators.register()
    panel.register()


def unregister():
    panel.unregister()
    operators.unregister()
    preferences.unregister()
