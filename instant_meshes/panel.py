import bpy
from bpy.props import BoolProperty, EnumProperty, FloatProperty, IntProperty
from bpy.types import Panel

from .operators import IM_OT_Remesh
from .preferences import get_binary_path


_DENSITY_ITEMS = [
    ('FACES', "Face Count", "Control density by the target number of output faces"),
    ('SCALE', "Edge Length", "Control density by the target edge length"),
    ('VERTICES', "Vertex Count", "Control density by the target number of output vertices"),
]


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
        scene = context.scene

        layout.operator(
            "mesh.instant_meshes_remesh",
            text="Remesh Selected",
            icon='MOD_REMESH',
        )

        density = layout.column(align=True)
        density.prop(scene, "im_density_mode", text="Density")
        if scene.im_density_mode == 'FACES':
            density.prop(scene, "im_target_faces", text="Faces")
        elif scene.im_density_mode == 'SCALE':
            density.prop(scene, "im_target_scale", text="Edge Length")
        else:
            density.prop(scene, "im_target_vertices", text="Vertices")

        symmetry = layout.column(align=True)
        symmetry.prop(scene, "im_rosy", text="RoSy")
        symmetry.prop(scene, "im_posy", text="PoSy")

        advanced = layout.box()
        header = advanced.row()
        header.prop(
            context.window_manager,
            "im_show_advanced",
            text="Advanced",
            icon='TRIA_DOWN' if context.window_manager.im_show_advanced else 'TRIA_RIGHT',
            emboss=False,
        )
        if context.window_manager.im_show_advanced:
            column = advanced.column(align=True)
            column.prop(scene, "im_extrinsic", text="Extrinsic")
            column.prop(scene, "im_crease_angle", text="Crease Angle")
            column.prop(scene, "im_align_boundaries", text="Align Boundaries")
            column.prop(scene, "im_dominant", text="Quad-Dominant")
            column.prop(scene, "im_smooth_iter", text="Smooth Iterations")
            column.prop(scene, "im_deterministic", text="Deterministic")
            column.prop(scene, "im_threads", text="Threads")

        if IM_OT_Remesh.is_running():
            layout.label(text="Remeshing...", icon='TIME')
        elif get_binary_path(context):
            layout.label(text="CLI ready", icon='CHECKMARK')
        else:
            layout.label(text="CLI not found", icon='ERROR')


def register():
    bpy.types.Scene.im_density_mode = EnumProperty(
        name="Density",
        description="Method used to control the remeshed surface density",
        items=_DENSITY_ITEMS,
        default='FACES',
    )
    bpy.types.Scene.im_target_faces = IntProperty(
        name="Face Count",
        description="Approximate target number of faces in the remeshed result",
        default=2000,
        min=1,
    )
    bpy.types.Scene.im_target_scale = FloatProperty(
        name="Edge Length",
        description="Target edge length in object units; -1 lets the CLI choose automatically",
        default=-1.0,
        min=-1.0,
    )
    bpy.types.Scene.im_target_vertices = IntProperty(
        name="Vertex Count",
        description="Approximate target number of output vertices; -1 lets the CLI choose automatically",
        default=-1,
        min=-1,
    )
    bpy.types.Scene.im_rosy = IntProperty(
        name="RoSy",
        description="Rotational symmetry of the orientation field: 2, 4, or 6; use 4 for quad remeshing",
        default=4,
        min=2,
        max=6,
    )
    bpy.types.Scene.im_posy = IntProperty(
        name="PoSy",
        description="Positional symmetry of the position field: 4 for quads or 3 for triangles",
        default=4,
        min=3,
        max=4,
    )
    bpy.types.Scene.im_extrinsic = BoolProperty(
        name="Extrinsic",
        description="Optimize using 3D embedding; disable to use intrinsic surface distances",
        default=True,
    )
    bpy.types.Scene.im_crease_angle = FloatProperty(
        name="Crease Angle",
        description="Dihedral angle threshold in degrees for preserving sharp creases; -1 uses automatic handling",
        default=-1.0,
    )
    bpy.types.Scene.im_align_boundaries = BoolProperty(
        name="Align Boundaries",
        description="Align the orientation field to open mesh boundaries",
        default=False,
    )
    bpy.types.Scene.im_dominant = BoolProperty(
        name="Quad-Dominant",
        description="Allow non-quad faces where needed instead of requiring a pure quad result",
        default=False,
    )
    bpy.types.Scene.im_smooth_iter = IntProperty(
        name="Smooth Iterations",
        description="Number of smoothing iterations applied to the orientation field",
        default=2,
        min=0,
    )
    bpy.types.Scene.im_deterministic = BoolProperty(
        name="Deterministic",
        description="Use deterministic processing for repeatable results at a possible speed cost",
        default=False,
    )
    bpy.types.Scene.im_threads = IntProperty(
        name="Threads",
        description="Maximum worker thread count; 0 lets the CLI choose automatically",
        default=0,
        min=0,
    )
    bpy.types.WindowManager.im_show_advanced = BoolProperty(
        name="Advanced",
        default=False,
        options={'SKIP_SAVE'},
    )

    bpy.utils.register_class(IM_PT_Main)


def unregister():
    bpy.utils.unregister_class(IM_PT_Main)

    del bpy.types.WindowManager.im_show_advanced
    del bpy.types.Scene.im_threads
    del bpy.types.Scene.im_deterministic
    del bpy.types.Scene.im_smooth_iter
    del bpy.types.Scene.im_dominant
    del bpy.types.Scene.im_align_boundaries
    del bpy.types.Scene.im_crease_angle
    del bpy.types.Scene.im_extrinsic
    del bpy.types.Scene.im_posy
    del bpy.types.Scene.im_rosy
    del bpy.types.Scene.im_target_vertices
    del bpy.types.Scene.im_target_scale
    del bpy.types.Scene.im_target_faces
    del bpy.types.Scene.im_density_mode
