# Instant Meshes Blender Addon — Rewrite Spec

## Goal

A Blender addon that wraps the `instantmeshes-cli` command-line tool, exposing
auto-retopology directly in the Blender UI.

## Architecture

Four Python files inside a folder named `instant_meshes/`, packaged as a ZIP:

```
instant_meshes/
├── __init__.py       # Addon metadata + registration
├── operators.py      # The remesh operator
├── panel.py          # Sidebar panel UI
└── preferences.py    # Binary path setting
```

ZIP structure for Blender installation:
```
instant-meshes-blender-addon.zip
└── instant_meshes/
    ├── __init__.py
    ├── operators.py
    ├── panel.py
    └── preferences.py
```

## Blender Compatibility

- Blender 3.6+, 4.x, 5.x
- macOS / Linux / Windows

## External Dependency

The addon depends on a CLI binary called `instantmeshes-cli` (or `instantmeshes-cli.exe` on Windows).

Users download it separately from:
https://github.com/kigland/instant-meshes/releases

## CLI Usage

```
instantmeshes-cli [options] <input.obj> <output.obj>
```

Supported input formats: `.obj`, `.ply`, `.glb`, `.gltf`
Output formats: `.obj`, `.ply`

Options:

| Flag            | Type     | Default | Description                       |
|-----------------|----------|---------|-----------------------------------|
| `-f, --faces`   | int      | -1      | Target face count                 |
| `-s, --scale`   | float    | -1      | Target edge length                |
| `-v, --vertices`| int      | -1      | Target vertex count               |
| `-r, --rosy`    | 2/4/6    | 4       | Rotational symmetry               |
| `-p, --posy`    | 3/4      | 4       | Positional symmetry               |
| `-c, --crease`  | float    | -1      | Crease angle threshold (degrees)  |
| `-i, --intrinsic` | bool   | off     | Intrinsic mode                    |
| `-b, --boundaries` | bool  | off     | Align to boundaries               |
| `-D, --dominant` | bool    | off     | Quad-dominant output              |
| `-S, --smooth`  | int      | 2       | Smoothing iterations              |
| `-d, --deterministic` | bool | off   | Deterministic mode                |
| `-t, --threads` | int      | 0=auto  | Thread count                      |
| `-k, --knn`     | int      | 10      | Point-cloud neighbor count (advanced) |

Density: exactly one of `-f`, `-s`, `-v` should be used. If none, auto-calculates.

## Addon Workflow

1. User downloads `instant-meshes-cli` binary and `instant-meshes-blender-addon.zip`
2. In Blender: Edit → Preferences → Add-ons → Install → select ZIP
3. Enable the addon (toggle checkbox)
4. In Preferences, set path to the binary (or place it in `instant_meshes/bin/`)
5. In 3D Viewport, press N → find "Instant Meshes" tab in sidebar
6. Select a mesh object, configure parameters, click "Remesh Selected"

## UI Layout (Panel)

Sidebar panel (N key), category "Instant Meshes":

```
┌─ Instant Meshes ──────────────────┐
│ [  Remesh Selected  ]             │  ← button
│                                   │
│ Density:  [ Face Count ▾ ]        │  ← enum: Face Count / Edge Length / Vertex Count
│ Faces:    [   2000   ]            │  ← int, shown when Face Count selected
│                                   │
│ RoSy:     [   4   ]               │  ← int, 2/4/6
│ PoSy:     [   4   ]               │  ← int, 3/4
│                                   │
│ ▼ Advanced                         │  ← collapsible
│   Extrinsic            [✓]        │
│   Crease Angle         [-1.0 ]    │
│   Align Boundaries     [ ]        │
│   Quad-Dominant        [ ]        │
│   Smooth Iterations    [ 2  ]     │
│   Deterministic        [ ]        │
│   Threads              [ 0  ]     │
│                                   │
│ CLI ready ✓                       │  ← status indicator
└───────────────────────────────────┘
```

## Preferences

Addon preferences (Edit → Preferences → Add-ons → Instant Meshes → expand):

```
┌─ Instant Meshes Remesh ──────────────────────────┐
│                                                    │
│ instantmeshes-cli Path:  [ /usr/local/bin/... ] [📂] │
│                                                    │
│ Auto-detected: ✓ /path/to/instant_meshes/bin/...    │
│ or: ⚠ Binary not found — download from Releases     │
└────────────────────────────────────────────────────┘
```

Auto-detection logic:
- Check if `instantmeshes-cli` (or `.exe`) exists next to the addon in a `bin/` subdirectory
- Fall back to user-configured path

## Operator Logic

When "Remesh Selected" is clicked:

1. Locate the CLI binary (from preferences or auto-detect)
2. Export the active mesh object to a temporary `.obj` file (use `bpy.ops.wm.obj_export`)
3. Build CLI command string from UI parameters
4. Run `subprocess.run(cmd, capture_output=True, text=True, timeout=300)`
5. On success, import the output `.obj` into Blender (use `bpy.ops.wm.obj_import`)
6. Name the new object "<original>_remeshed"
7. Clean up temp files
8. Report status to user

## Scene Properties

All UI parameters are stored as `bpy.types.Scene` properties (persist per `.blend`):

```python
bpy.types.Scene.im_density_mode    # EnumProperty
bpy.types.Scene.im_target_faces    # IntProperty
bpy.types.Scene.im_target_scale    # FloatProperty
bpy.types.Scene.im_target_vertices # IntProperty
bpy.types.Scene.im_rosy            # IntProperty
bpy.types.Scene.im_posy            # IntProperty
bpy.types.Scene.im_extrinsic       # BoolProperty
bpy.types.Scene.im_crease_angle    # FloatProperty
bpy.types.Scene.im_align_boundaries # BoolProperty
bpy.types.Scene.im_dominant        # BoolProperty
bpy.types.Scene.im_smooth_iter     # IntProperty
bpy.types.Scene.im_deterministic   # BoolProperty
bpy.types.Scene.im_threads         # IntProperty
```

## Common Pitfalls to Avoid

1. **EnumProperty items must be a static list**, not a callback function.
   Wrong: `items=_some_function` → Right: `items=[('A', "Label", "Desc"), ...]`

2. **ZIP must contain the `instant_meshes/` folder at the root.**
   Wrong: bare `__init__.py` at zip root. Right: `zip/instant_meshes/__init__.py`

3. **All bpy.props types must be imported.** Use:
   ```python
   from bpy.props import (EnumProperty, IntProperty, FloatProperty, BoolProperty, StringProperty)
   ```

4. **Relative imports between addon files.** `from . import operators` etc.

5. **Unregister must clean up** all `bpy.types.Scene` custom properties with `del bpy.types.Scene.xxx`

6. **Reinstall issue**: if Blender says "already registered", restart Blender before reinstalling. Or use `bpy.utils.unregister_class()` properly in `unregister()`.

## Testing Checklist

- [ ] ZIP installs without Python errors
- [ ] Addon checkbox toggles on without errors
- [ ] Panel appears in 3D View sidebar (N key)
- [ ] Preferences show, binary path can be set
- [ ] Selecting a mesh and clicking "Remesh" exports, runs CLI, imports result
- [ ] Uninstall (disable addon) cleans up without leaving stale data
- [ ] Reinstall after uninstall works (no "already registered" error)
