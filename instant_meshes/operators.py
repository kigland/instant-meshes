import os
import subprocess
import tempfile
import time

import bpy
from bpy.types import Operator

from .preferences import get_binary_path


def _build_command(binary, scene, input_path, output_path):
    command = [binary]

    if scene.im_density_mode == 'FACES':
        command.extend(("-f", str(scene.im_target_faces)))
    elif scene.im_density_mode == 'SCALE':
        command.extend(("-s", str(scene.im_target_scale)))
    else:
        command.extend(("-v", str(scene.im_target_vertices)))

    command.extend(("-r", str(scene.im_rosy), "-p", str(scene.im_posy)))

    if not scene.im_extrinsic:
        command.append("-i")
    if scene.im_crease_angle >= 0:
        command.extend(("-c", str(scene.im_crease_angle)))
    if scene.im_align_boundaries:
        command.append("-b")
    if scene.im_dominant:
        command.append("-D")
    if scene.im_smooth_iter != 2:
        command.extend(("-S", str(scene.im_smooth_iter)))
    if scene.im_deterministic:
        command.append("-d")
    if scene.im_threads > 0:
        command.extend(("-t", str(scene.im_threads)))

    command.extend((input_path, output_path))
    return command


def _restore_selection(context, selected_objects, active_object):
    bpy.ops.object.select_all(action='DESELECT')
    for selected_object in selected_objects:
        if selected_object.name in context.view_layer.objects:
            selected_object.select_set(True)
    if active_object.name in context.view_layer.objects:
        context.view_layer.objects.active = active_object


class IM_OT_Remesh(Operator):
    bl_idname = "mesh.instant_meshes_remesh"
    bl_label = "Remesh with Instant Meshes"
    bl_description = "Remesh the active mesh asynchronously with Instant Meshes; press Esc to cancel"
    bl_options = {'REGISTER', 'UNDO'}

    _active_instance = None
    _is_running = False
    _process = None
    _timer = None
    _temp_dir = None
    _stdout_file = None
    _stderr_file = None

    @classmethod
    def poll(cls, context):
        return (
            not cls._is_running
            and context.active_object is not None
            and context.active_object.type == 'MESH'
        )

    @classmethod
    def is_running(cls):
        return cls._is_running

    def invoke(self, context, event):
        return self._start(context)

    def execute(self, context):
        return self._start(context)

    def _start(self, context):
        binary = get_binary_path(context)
        if not binary:
            self.report({'ERROR'}, "instantmeshes-cli not found; set it in Add-on Preferences")
            return {'CANCELLED'}

        scene = context.scene
        if scene.im_rosy not in {2, 4, 6}:
            self.report({'ERROR'}, "RoSy must be 2, 4, or 6")
            return {'CANCELLED'}
        if scene.im_posy not in {3, 4}:
            self.report({'ERROR'}, "PoSy must be 3 or 4")
            return {'CANCELLED'}

        source_object = context.active_object
        self._source_name = source_object.name
        selected_objects = tuple(context.selected_objects)
        object_mode = source_object.mode

        try:
            if object_mode != 'OBJECT':
                bpy.ops.object.mode_set(mode='OBJECT')

            self._temp_dir = tempfile.TemporaryDirectory(prefix="instant_meshes_")
            input_path = os.path.join(self._temp_dir.name, "input.obj")
            self._output_path = os.path.join(self._temp_dir.name, "output.obj")
            try:
                bpy.ops.object.select_all(action='DESELECT')
                source_object.select_set(True)
                context.view_layer.objects.active = source_object
                bpy.ops.wm.obj_export(
                    filepath=input_path,
                    export_selected_objects=True,
                    export_materials=False,
                )
            finally:
                _restore_selection(context, selected_objects, source_object)

            self._stdout_file = open(
                os.path.join(self._temp_dir.name, "stdout.log"),
                mode='w+',
                encoding='utf-8',
                errors='replace',
            )
            self._stderr_file = open(
                os.path.join(self._temp_dir.name, "stderr.log"),
                mode='w+',
                encoding='utf-8',
                errors='replace',
            )
            command = _build_command(binary, scene, input_path, self._output_path)
            self._process = subprocess.Popen(
                command,
                stdout=self._stdout_file,
                stderr=self._stderr_file,
            )
            self._started_at = time.monotonic()
            self._timer = context.window_manager.event_timer_add(
                0.2,
                window=context.window,
            )
            context.window_manager.modal_handler_add(self)
            type(self)._active_instance = self
            type(self)._is_running = True
            self._tag_redraw(context)

        except FileNotFoundError:
            self._cleanup(context)
            self.report({'ERROR'}, f"Binary not found: {binary}")
            return {'CANCELLED'}
        except (OSError, RuntimeError) as error:
            self._cleanup(context)
            self.report({'ERROR'}, f"Remeshing failed: {error}")
            return {'CANCELLED'}

        self.report({'INFO'}, "Remeshing started; press Esc to cancel")
        return {'RUNNING_MODAL'}

    def modal(self, context, event):
        if event.type == 'ESC':
            self._terminate_process()
            self._cleanup(context)
            self.report({'WARNING'}, "Remeshing cancelled")
            return {'CANCELLED'}

        if event.type != 'TIMER':
            return {'PASS_THROUGH'}

        if time.monotonic() - self._started_at > 300:
            self._terminate_process()
            self._cleanup(context)
            self.report({'ERROR'}, "Remeshing timed out after 300 seconds")
            return {'CANCELLED'}

        return_code = self._process.poll()
        if return_code is None:
            return {'PASS_THROUGH'}

        stdout, stderr = self._read_process_output()
        if return_code != 0:
            detail = (stderr or stdout or "unknown CLI error").strip()
            self._cleanup(context)
            self.report({'ERROR'}, f"Instant Meshes failed: {detail[:500]}")
            return {'CANCELLED'}

        if not os.path.isfile(self._output_path):
            self._cleanup(context)
            self.report({'ERROR'}, "Instant Meshes did not create an output OBJ")
            return {'CANCELLED'}

        try:
            existing_objects = {
                obj.as_pointer() for obj in context.scene.objects
            }
            bpy.ops.wm.obj_import(filepath=self._output_path)
            imported_objects = [
                obj for obj in context.scene.objects
                if obj.as_pointer() not in existing_objects
            ]
            if not imported_objects:
                raise RuntimeError("The output OBJ did not contain an importable object")

            imported_object = imported_objects[0]
            imported_object.name = f"{self._source_name}_remeshed"
            bpy.ops.object.select_all(action='DESELECT')
            imported_object.select_set(True)
            context.view_layer.objects.active = imported_object
        except (OSError, RuntimeError) as error:
            self._cleanup(context)
            self.report({'ERROR'}, f"Could not import remeshed OBJ: {error}")
            return {'CANCELLED'}

        self._cleanup(context)
        self.report({'INFO'}, "Remeshing complete")
        return {'FINISHED'}

    def cancel(self, context):
        self._terminate_process()
        self._cleanup(context)

    def _read_process_output(self):
        output = []
        for log_file in (self._stdout_file, self._stderr_file):
            if log_file:
                log_file.flush()
                log_file.seek(0)
                output.append(log_file.read())
            else:
                output.append("")
        return tuple(output)

    def _terminate_process(self):
        if not self._process or self._process.poll() is not None:
            return

        self._process.terminate()
        try:
            self._process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self._process.kill()
            self._process.wait()

    def _cleanup(self, context):
        if self._timer:
            context.window_manager.event_timer_remove(self._timer)
            self._timer = None

        for attribute in ("_stdout_file", "_stderr_file"):
            log_file = getattr(self, attribute, None)
            if log_file:
                log_file.close()
                setattr(self, attribute, None)

        if self._temp_dir:
            self._temp_dir.cleanup()
            self._temp_dir = None

        self._process = None
        type(self)._active_instance = None
        type(self)._is_running = False
        self._tag_redraw(context)

    @staticmethod
    def _tag_redraw(context):
        if context.screen:
            for area in context.screen.areas:
                if area.type == 'VIEW_3D':
                    area.tag_redraw()


def register():
    bpy.utils.register_class(IM_OT_Remesh)


def unregister():
    active_instance = IM_OT_Remesh._active_instance
    if active_instance:
        active_instance._terminate_process()
        active_instance._cleanup(bpy.context)
    bpy.utils.unregister_class(IM_OT_Remesh)
