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

_HELP_ITEMS = [
    ('DENSITY', "Density", "How the output mesh density is controlled"),
    ('FACES', "Face Count", "Target output face count"),
    ('SCALE', "Edge Length", "Target output edge length"),
    ('VERTICES', "Vertex Count", "Target output vertex count"),
    ('ROSY', "RoSy", "Orientation-field rotational symmetry"),
    ('POSY', "PoSy", "Position-field symmetry"),
    ('EXTRINSIC', "Extrinsic", "Extrinsic or intrinsic optimization"),
    ('CREASE', "Crease Angle", "Sharp crease angle threshold"),
    ('BOUNDARIES', "Align Boundaries", "Open-boundary alignment"),
    ('DOMINANT', "Quad-Dominant", "Pure quad or quad-dominant output"),
    ('SMOOTH', "Smooth Iterations", "Output smoothing and reprojection"),
    ('DETERMINISTIC', "Deterministic", "Repeatable processing"),
    ('THREADS', "Threads", "Worker thread limit"),
]

_PARAMETER_HELP = {
    'DENSITY': (
        ("EN", "Selects Face Count, Edge Length, or", "Vertex Count. Only one target is used."),
        ("中文", "选择面数、边长或顶点数控制密度。", "每次只会使用一种目标。"),
    ),
    'FACES': (
        ("EN", "Approximate output face count.", "Higher values preserve more detail."),
        ("中文", "近似的输出面数。", "数值越高，保留的细节越多。"),
    ),
    'SCALE': (
        ("EN", "Target edge length in exported OBJ units.", "Use -1 for automatic sizing."),
        ("中文", "目标边长，单位与导出的 OBJ 一致。", "-1 表示自动计算。"),
    ),
    'VERTICES': (
        ("EN", "Approximate output vertex count.", "-1 uses about 1/16 of input vertices."),
        ("中文", "近似的输出顶点数。", "-1 使用输入顶点数约 1/16。"),
    ),
    'ROSY': (
        ("EN", "Orientation-field rotational symmetry.", "Use 4 for standard quad remeshing."),
        ("中文", "方向场的旋转对称阶数。", "标准四边形重拓扑使用 4。"),
    ),
    'POSY': (
        ("EN", "Position-field symmetry.", "Use 4 for quads or 3 for triangles."),
        ("中文", "位置场的对称类型。", "四边形使用 4，三角形使用 3。"),
    ),
    'EXTRINSIC': (
        ("EN", "Uses the 3D embedding when enabled.", "Disable for intrinsic surface distances."),
        ("中文", "开启时使用三维空间嵌入关系。", "关闭后使用曲面内部距离。"),
    ),
    'CREASE': (
        ("EN", "Sharp-edge dihedral threshold in degrees.", "-1 disables explicit crease constraints."),
        ("中文", "锐边二面角阈值，单位为度。", "-1 表示关闭显式锐边约束。"),
    ),
    'BOUNDARIES': (
        ("EN", "Aligns the field to open mesh borders.", "It has little effect on closed meshes."),
        ("中文", "让方向场沿开放网格边界排列。", "对封闭网格基本没有作用。"),
    ),
    'DOMINANT': (
        ("EN", "Allows non-quads in difficult regions.", "Enabled matches the original GUI default."),
        ("中文", "允许困难区域出现非四边形面。", "开启时与原版 GUI 默认一致。"),
    ),
    'SMOOTH': (
        ("EN", "Output smoothing and reprojection steps.", "0 matches the original GUI default."),
        ("中文", "输出网格的平滑与重新投影次数。", "0 与原版 GUI 默认一致。"),
    ),
    'DETERMINISTIC': (
        ("EN", "Makes repeated runs more reproducible.", "It may reduce processing speed."),
        ("中文", "让重复运行的结果更容易复现。", "可能会降低处理速度。"),
    ),
    'THREADS': (
        ("EN", "Limits the number of worker threads.", "0 lets the CLI choose automatically."),
        ("中文", "限制工作线程数量。", "0 表示由 CLI 自动选择。"),
    ),
}


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

        guide = layout.box()
        guide_header = guide.row()
        guide_header.prop(
            context.window_manager,
            "im_show_help",
            text="Parameter Guide / 参数说明",
            icon='TRIA_DOWN' if context.window_manager.im_show_help else 'TRIA_RIGHT',
            emboss=False,
        )
        if context.window_manager.im_show_help:
            guide.use_property_split = False
            guide.prop(context.window_manager, "im_help_topic", text="")
            for language, *lines in _PARAMETER_HELP[context.window_manager.im_help_topic]:
                guide.label(text=language, icon='INFO')
                for line in lines:
                    guide.label(text=line)

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
        default='VERTICES',
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
        description="Approximate target number of output vertices; -1 uses the original UI default of about 1/16 of the input vertices",
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
        description="Dihedral angle threshold in degrees for preserving sharp creases; -1 disables explicit crease constraints",
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
        default=True,
    )
    bpy.types.Scene.im_smooth_iter = IntProperty(
        name="Smooth Iterations",
        description="Number of output-mesh smoothing and reprojection steps",
        default=0,
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
    bpy.types.WindowManager.im_show_help = BoolProperty(
        name="Parameter Guide / 参数说明",
        default=False,
        options={'SKIP_SAVE'},
    )
    bpy.types.WindowManager.im_help_topic = EnumProperty(
        name="Parameter",
        items=_HELP_ITEMS,
        default='DENSITY',
        options={'SKIP_SAVE'},
    )

    bpy.utils.register_class(IM_PT_Main)


def unregister():
    bpy.utils.unregister_class(IM_PT_Main)

    del bpy.types.WindowManager.im_help_topic
    del bpy.types.WindowManager.im_show_help
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
