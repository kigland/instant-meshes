import bpy
import os
import subprocess
import tempfile
import shutil
from bpy.props import (
    IntProperty, FloatProperty, BoolProperty, EnumProperty, StringProperty,
)
from bpy.types import Operator
from . import __init__ as addon


class IM_OT_Remesh(Operator):
    bl_idname = "mesh.instant_meshes_remesh"
    bl_label = "Remesh with Instant Meshes"
    bl_description = "Run Instant Meshes CLI on the selected object"
    bl_options = {'REGISTER', 'UNDO'}

    # Density
    density_mode: EnumProperty(
        name="Density",
        items=[
            ('FACES', "Face Count", "Target number of output faces"),
            ('SCALE', "Edge Length", "Target edge length"),
            ('VERTICES', "Vertex Count", "Target number of output vertices"),
        ],
        default='FACES',
    )
    target_faces: IntProperty(name="Faces", default=2000, min=4)
    target_scale: FloatProperty(name="Scale", default=-1.0)
    target_vertices: IntProperty(name="Vertices", default=-1, min=4)

    # Symmetry
    rosy: IntProperty(name="RoSy", default=4, min=2, max=6)
    posy: IntProperty(name="PoSy", default=4, min=3, max=4)

    # Advanced
    extrinsic: BoolProperty(name="Extrinsic", default=True)
    crease_angle: FloatProperty(name="Crease Angle", default=-1,
                                 description="Dihedral angle threshold for creases (-1 = auto)")
    align_boundaries: BoolProperty(name="Align to Boundaries", default=False)
    dominant: BoolProperty(name="Quad-Dominant", default=False,
                            description="Allow non-quad faces")
    smooth_iter: IntProperty(name="Smooth Iterations", default=2, min=0, max=10)
    deterministic: BoolProperty(name="Deterministic", default=False)
    threads: IntProperty(name="Threads", default=0, min=0,
                          description="0 = auto")

    @classmethod
    def poll(cls, context):
        return (context.active_object is not None and
                context.active_object.type == 'MESH')

    def execute(self, context):
        binary = addon.get_binary_path()
        if not binary:
            self.report({'ERROR'}, "instantmeshes-cli not found. Set path in Preferences.")
            return {'CANCELLED'}

        obj = context.active_object

        # Export selected to temp OBJ
        tmp_dir = tempfile.mkdtemp(prefix="im_")
        input_path = os.path.join(tmp_dir, "input.obj")
        output_path = os.path.join(tmp_dir, "output.obj")

        # Select only the active object for export
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.ops.wm.obj_export(
            filepath=input_path,
            export_selected_objects=True,
            export_materials=False,
        )

        # Build CLI command
        cmd = [binary]

        if self.density_mode == 'FACES':
            cmd += ['-f', str(self.target_faces)]
        elif self.density_mode == 'SCALE':
            cmd += ['-s', str(self.target_scale)]
        elif self.density_mode == 'VERTICES':
            cmd += ['-v', str(self.target_vertices)]

        cmd += ['-r', str(self.rosy)]
        cmd += ['-p', str(self.posy)]

        if not self.extrinsic:
            cmd += ['-i']
        if self.crease_angle >= 0:
            cmd += ['-c', str(self.crease_angle)]
        if self.align_boundaries:
            cmd += ['-b']
        if self.dominant:
            cmd += ['-D']
        if self.smooth_iter != 2:
            cmd += ['-S', str(self.smooth_iter)]
        if self.deterministic:
            cmd += ['-d']
        if self.threads > 0:
            cmd += ['-t', str(self.threads)]

        cmd += [input_path, output_path]

        # Run CLI
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            if result.returncode != 0:
                self.report({'ERROR'}, f"Instant Meshes failed:\n{result.stderr}")
                return {'CANCELLED'}
        except FileNotFoundError:
            self.report({'ERROR'}, f"Binary not found: {binary}")
            return {'CANCELLED'}
        except subprocess.TimeoutExpired:
            self.report({'ERROR'}, "Remeshing timed out (5 min)")
            return {'CANCELLED'}

        # Import result
        bpy.ops.wm.obj_import(filepath=output_path)

        # Cleanup
        shutil.rmtree(tmp_dir, ignore_errors=True)

        # Select the new object
        imported = context.selected_objects[-1] if context.selected_objects else None
        if imported:
            imported.name = obj.name + "_remeshed"
            imported.select_set(True)
            context.view_layer.objects.active = imported

        self.report({'INFO'}, f"Remeshing complete.")
        return {'FINISHED'}

    def invoke(self, context, event):
        return context.window_manager.invoke_props_dialog(self, width=280)


class IM_OT_SetBinary(Operator):
    bl_idname = "mesh.instant_meshes_set_binary"
    bl_label = "Auto-detect Binary"
    bl_description = "Find instantmeshes-cli in the addon directory"

    def execute(self, context):
        path = addon.get_binary_path()
        if path:
            self.report({'INFO'}, f"Found: {path}")
        else:
            self.report({'WARNING'}, "Not found — place binary in blender_plugin/bin/")
        return {'FINISHED'}


def register():
    bpy.utils.register_class(IM_OT_Remesh)
    bpy.utils.register_class(IM_OT_SetBinary)


def unregister():
    bpy.utils.unregister_class(IM_OT_SetBinary)
    bpy.utils.unregister_class(IM_OT_Remesh)
