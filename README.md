# ✨ Instant Meshes CLI

> 🏗️ One-command auto retopology · clean · fast · cute

A command-line wrapper around the [**Instant Field-Aligned Meshes**](http://igl.ethz.ch/projects/instant-meshes/) algorithm (SIGGRAPH Asia 2015). Supports GLB, glTF, OBJ, and PLY inputs. No GUI — just pure remeshing power.

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS_ARM64-pink?style=flat-square" alt="macOS ARM64">
  <img src="https://img.shields.io/badge/license-BSD--3-blue?style=flat-square" alt="BSD-3">
  <img src="https://img.shields.io/badge/based_on-Instant_Meshes-ff69b4?style=flat-square" alt="based on Instant Meshes">
</p>

---

## 🎀 What is this?

Turns messy, high-poly triangle meshes into clean, well-structured quad (or tri) meshes — while preserving the original shape. This is called **retopology** (or **remeshing**).

```
    🪨 Input (50K triangles)  ──→  🧊 Output (2K quads)
```

## 📦 Download

[![Download](https://img.shields.io/badge/⬇️%20Download-macOS_ARM64-f5a?style=for-the-badge)](https://github.com/kigland/instant-meshes/releases/latest)

The Blender addon ZIP includes the macOS ARM64 CLI. Blender detects it
automatically, so no binary path setup is required on this platform.

## 🚀 Quick Start

```bash
# Basic: GLB in, OBJ out, 2000 faces
./instantmeshes-cli model.glb output.obj -f 2000

# High resolution
./instantmeshes-cli model.glb output.obj -f 10000

# Triangle / hex mesh
./instantmeshes-cli model.glb output.obj -f 3000 -r 6 -p 3

# Preserve sharp edges
./instantmeshes-cli model.ply output.obj -f 2000 -c 30
```

## 🎛️ Options

| Flag | Description | Default |
|------|-------------|---------|
| `-f, --faces` | Target face count | auto |
| `-s, --scale` | Target edge length | auto |
| `-v, --vertices` | Target vertex count | auto |
| `-r, --rosy` | Rotational symmetry `2` `4` `6` | `4` |
| `-p, --posy` | Positional symmetry `3` `4` | `4` |
| `-c, --crease` | Crease angle threshold (degrees) | `-1` disables explicit creases |
| `-i, --intrinsic` | Intrinsic mode | off |
| `-b, --boundaries` | Align to boundaries | off |
| `-D, --dominant` | Non-pure-quad output | off |
| `-S, --smooth` | Smoothing iterations | `2` |
| `-k, --knn` | Point-cloud neighbor count | `10` |
| `-d, --deterministic` | Deterministic mode | off |
| `-t, --threads` | Thread count | auto |
| `-h, --help` | Show help | — |

## Blender Addon

Install `instant-meshes-blender-addon.zip` from Blender's
**Edit > Preferences > Add-ons > Install from Disk**, then open
**3D Viewport > Sidebar (N) > Instant Meshes**.

The **Advanced** section is collapsed by default. Expand it to access
Extrinsic, Crease Angle, Align Boundaries, Quad-Dominant, Smooth Iterations,
Deterministic, and Threads. The addon also includes a collapsible bilingual
**Parameter Guide** section with both English and Chinese help.

### Original UI-Aligned Defaults

The Blender addon defaults intentionally match the effective defaults of the
original 2015 Instant Meshes GUI, rather than the later batch-mode defaults.

| Setting | Blender addon default | Original GUI behavior |
|---------|-------------------------|-----------------------|
| Density mode | Vertex Count | The original GUI exposed Target Vertex Count |
| Vertex Count | `-1` | Automatically targets about `1/16` of the input vertices |
| RoSy / PoSy | `4 / 4` | Standard quad remeshing |
| Extrinsic | on | Enabled |
| Crease Angle | `-1` | Sharp creases disabled |
| Align Boundaries | off | Disabled |
| Quad-Dominant | on | Equivalent to original `Pure quad mesh = off` |
| Smooth Iterations | `0` | No post-extraction smoothing by default |
| Deterministic | off | Disabled |
| Threads | `0` | Automatic thread count |

### UI Parameter Guide

The three Density modes are mutually exclusive. Exactly one of `--faces`,
`--scale`, or `--vertices` is sent to the CLI. All targets are approximate
because the output must also satisfy field-alignment and extraction constraints.

| UI control | CLI | Default | What it controls | Practical guidance |
|------------|-----|---------|------------------|--------------------|
| **Density > Face Count** | `-f` | `2000` when selected | Approximate output face count | Increase it to retain smaller details, at the cost of a larger result and more processing. |
| **Density > Edge Length** | `-s` | `-1` | Target edge length in exported OBJ units | Useful when several meshes need a shared physical edge scale. `-1` uses automatic sizing. |
| **Density > Vertex Count** | `-v` | `-1` (default mode) | Approximate output vertex count | `-1` reproduces the original GUI target of about `1/16` of the input vertices. |
| **RoSy** | `-r` | `4` | Rotational symmetry of the orientation field | Use `4` for standard quad remeshing. Valid values are `2`, `4`, and `6`. |
| **PoSy** | `-p` | `4` | Symmetry of the position field | Use `4` for quads or `3` for triangle/hexagon-oriented layouts. |
| **Extrinsic** | inverse of `-i` | on | Uses the mesh's 3D embedding during optimization | Usually keep it enabled. Disable it to use intrinsic surface distances. |
| **Crease Angle** | `-c` | `-1` | Sharp-edge dihedral threshold in degrees | Keep `-1` to disable explicit crease constraints. Try `30`-`60` degrees for hard-surface meshes. |
| **Align Boundaries** | `-b` | off | Aligns the field to open mesh borders | Enable it when the direction of open borders matters. It has little effect on closed meshes. |
| **Quad-Dominant** | `-D` | on | Allows non-quads in difficult regions | This matches the original GUI. Disable it when a pure-quad result is more important. |
| **Smooth Iterations** | `-S` | `0` | Post-extraction smoothing and reprojection steps | Increase it when a more uniform result is worth some loss of local feature alignment. |
| **Deterministic** | `-d` | off | Makes repeated runs more reproducible | Useful for tests and batch pipelines, with a possible performance cost. |
| **Threads** | `-t` | `0` | Maximum worker thread count | Keep `0` for automatic selection or use a positive value to limit CPU use. |

### RoSy and PoSy Combinations

| RoSy | PoSy | Typical result |
|------|------|----------------|
| `4` | `4` | Standard quad remeshing; recommended default |
| `6` | `3` | Triangle/hexagon-oriented layout |
| `2` | `4` | Two-way orientation field for specialized directional layouts |

### Suggested Settings

| Goal | Suggested settings |
|------|--------------------|
| Original GUI default | Vertex Count `-1`, RoSy `4`, PoSy `4`, Extrinsic on, Quad-Dominant on, Smooth `0` |
| Higher-density quads | Select Face Count, choose the required budget, and keep RoSy/PoSy at `4/4` |
| Hard-surface edges | RoSy/PoSy `4/4`, Crease Angle `30`-`60`; enable Align Boundaries for open meshes |
| Organic surface | RoSy/PoSy `4/4`, Crease Angle `-1`; raise Smooth to `2`-`4` only when needed |
| Robust extraction | Keep Quad-Dominant enabled to allow a small number of non-quad faces |
| Repeatable output | Enable Deterministic and use a fixed positive Threads value |

The CLI also exposes `-k/--knn`, but the addon intentionally omits it. KNN
controls neighborhood construction for point-cloud input, while the addon only
accepts a Blender Mesh and exports it as OBJ. It has no effect in the current
addon workflow. Apart from `-h/--help`, the UI exposes every CLI parameter that
affects the Mesh/OBJ workflow.

## 🛠️ Build from Source

```bash
git clone --recursive https://github.com/kigland/instant-meshes
cd instant-meshes
cmake -S . -B build
cmake --build build -j$(sysctl -n hw.logicalcpu)
# Binary at: build/instantmeshes-cli
```

## 📚 How It Works

The Instant Field-Aligned Meshes algorithm computes two smooth fields on the input surface:

1. **Orientation Field** (RoSy) — determines local edge directions, aligned to surface features
2. **Position Field** (PoSy) — assigns each vertex a parametric (u, v) coordinate

These fields are computed hierarchically (coarse-to-fine) and then traced to extract the output quad mesh. RoSy types: `4` = quads, `6` = triangles/hexagons, `2` = lines. PoSy types: `4` = quads, `3` = triangles.

> 📄 **Paper**: Wenzel Jakob, Marco Tarini, Daniele Panozzo, Olga Sorkine-Hornung. *Instant Field-Aligned Meshes*. ACM Trans. Graph. (SIGGRAPH Asia 2015).  
> [PDF](http://igl.ethz.ch/projects/instant-meshes/instant-meshes-SA-2015-jakob-et-al.pdf) · [Video](https://www.youtube.com/watch?v=U6wtw6W4x3I)

## 💝 Credits

Based on the core algorithm from [wjakob/instant-meshes](https://github.com/wjakob/instant-meshes).
- GLB/glTF via [cgltf](https://github.com/jkuhlmann/cgltf)
- Parallelism via [Intel TBB](https://github.com/oneapi-src/oneTBB)
- Linear algebra via [Eigen](https://eigen.tuxfamily.org/)
