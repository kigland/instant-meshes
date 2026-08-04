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
| `-c, --crease` | Crease angle threshold (degrees) | `-1` auto |
| `-i, --intrinsic` | Intrinsic mode | off |
| `-b, --boundaries` | Align to boundaries | off |
| `-D, --dominant` | Non-pure-quad output | off |
| `-S, --smooth` | Smoothing iterations | `2` |
| `-k, --knn` | Point-cloud neighbor count | `10` |
| `-d, --deterministic` | Deterministic mode | off |
| `-t, --threads` | Thread count | auto |
| `-h, --help` | Show help | — |

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
