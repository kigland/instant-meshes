import bpy
from bpy.types import Panel
from bpy.props import (
    EnumProperty, IntProperty, FloatProperty, BoolProperty,
)


class IM_PT_Main(Panel):
    bl_label = "Instant Meshes"
    bl_idname = "IM_PT_Main"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = "Instant Meshes"

    def draw(self, context):
        layout = self.layout
        layout.use_property_split = True
        layout.use_property_decorate = False

        # Remesh button
        op = layout.operator("mesh.instant_meshes_remesh", text="Remesh Selected",
                             icon='OUTLINER_OB_MESH')
        op.target_faces = context.scene.im_target_faces
        op.target_scale = context.scene.im_target_scale
        op.target_vertices = context.scene.im_target_vertices
        op.density_mode = context.scene.im_density_mode
        op.rosy = context.scene.im_rosy
        op.posy = context.scene.im_posy
        op.extrinsic = context.scene.im_extrinsic
        op.crease_angle = context.scene.im_crease_angle
        op.align_boundaries = context.scene.im_align_boundaries
        op.dominant = context.scene.im_dominant
        op.smooth_iter = context.scene.im_smooth_iter
        op.deterministic = context.scene.im_deterministic
        op.threads = context.scene.im_threads

        # Density
        col = layout.column(align=True)
        col.prop(context.scene, "im_density_mode", text="")

        if context.scene.im_density_mode == 'FACES':
            col.prop(context.scene, "im_target_faces")
        elif context.scene.im_density_mode == 'SCALE':
            col.prop(context.scene, "im_target_scale")
        elif context.scene.im_density_mode == 'VERTICES':
            col.prop(context.scene, "im_target_vertices")

        # Symmetry
        col = layout.column(align=True)
        col.prop(context.scene, "im_rosy")
        col.prop(context.scene, "im_posy")

        # Advanced
        box = layout.box()
        box.label(text="Advanced", icon='PREFERENCES')
        col = box.column(align=True)
        col.prop(context.scene, "im_extrinsic")
        col.prop(context.scene, "im_crease_angle")
        col.prop(context.scene, "im_align_boundaries")
        col.prop(context.scene, "im_dominant")
        col.prop(context.scene, "im_smooth_iter")
        col.prop(context.scene, "im_deterministic")
        col.prop(context.scene, "im_threads")

        # Binary status
        from . import __init__ as addon
        binary = addon.get_binary_path()
        if binary:
            layout.label(text="CLI ready", icon='CHECKMARK')
        else:
            layout.label(text="CLI not found — check Preferences", icon='ERROR')


# Registrable property group (stored per .blend)
def _density_items(self, context):
    return [
        ('FACES', "Face Count", ""),
        ('SCALE', "Edge Length", ""),
        ('VERTICES', "Vertex Count", ""),
    ]


def register():
    bpy.types.Scene.im_density_mode = EnumProperty(
        name="Density", items=_density_items, default='FACES')
    bpy.types.Scene.im_target_faces = IntProperty(name="Faces", default=2000, min=4)
    bpy.types.Scene.im_target_scale = FloatProperty(name="Scale", default=-1.0)
    bpy.types.Scene.im_target_vertices = IntProperty(name="Vertices", default=-1, min=4)
    bpy.types.Scene.im_rosy = IntProperty(name="RoSy", default=4, min=2, max=6)
    bpy.types.Scene.im_posy = IntProperty(name="PoSy", default=4, min=3, max=4)
    bpy.types.Scene.im_extrinsic = BoolProperty(name="Extrinsic", default=True)
    bpy.types.Scene.im_crease_angle = FloatProperty(name="Crease Angle", default=-1)
    bpy.types.Scene.im_align_boundaries = BoolProperty(name="Align Boundaries", default=False)
    bpy.types.Scene.im_dominant = BoolProperty(name="Quad-Dominant", default=False)
    bpy.types.Scene.im_smooth_iter = IntProperty(name="Smooth Iter", default=2, min=0, max=10)
    bpy.types.Scene.im_deterministic = BoolProperty(name="Deterministic", default=False)
    bpy.types.Scene.im_threads = IntProperty(name="Threads", default=0, min=0)

    bpy.utils.register_class(IM_PT_Main)


def unregister():
    bpy.utils.unregister_class(IM_PT_Main)
    del bpy.types.Scene.im_density_mode
    del bpy.types.Scene.im_target_faces
    del bpy.types.Scene.im_target_scale
    del bpy.types.Scene.im_target_vertices
    del bpy.types.Scene.im_rosy
    del bpy.types.Scene.im_posy
    del bpy.types.Scene.im_extrinsic
    del bpy.types.Scene.im_crease_angle
    del bpy.types.Scene.im_align_boundaries
    del bpy.types.Scene.im_dominant
    del bpy.types.Scene.im_smooth_iter
    del bpy.types.Scene.im_deterministic
    del bpy.types.Scene.im_threads
