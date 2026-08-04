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
| `-c, --crease` | Crease angle threshold (degrees) | `-1` auto |
| `-i, --intrinsic` | Intrinsic mode | off |
| `-b, --boundaries` | Align to boundaries | off |
| `-D, --dominant` | Non-pure-quad output | off |
| `-S, --smooth` | Smoothing iterations | `2` |
| `-k, --knn` | Point-cloud neighbor count | `10` |
| `-d, --deterministic` | Deterministic mode | off |
| `-t, --threads` | Thread count | auto |
| `-h, --help` | Show help | — |

## Blender 插件

在 Blender 的 **Edit > Preferences > Add-ons > Install from Disk** 中安装
`instant-meshes-blender-addon.zip`，然后打开
**3D Viewport > Sidebar (N) > Instant Meshes**。

**Advanced** 默认是折叠的。点击左侧展开箭头后，才会显示 Extrinsic、Crease
Angle、Align Boundaries、Quad-Dominant、Smooth Iterations、Deterministic 和
Threads。鼠标停留在 Blender 的任意参数上，也可以看到对应的悬停说明。

### UI 参数说明

Density 的三个模式互斥：每次只会向 CLI 传递 `--faces`、`--scale` 或
`--vertices` 其中一个。三个目标值都是近似值，因为最终拓扑还需要同时满足方向场、
位置场和网格提取约束。

| UI 参数 | CLI | 默认值 | 参数作用 | 使用建议 |
|---------|-----|--------|----------|----------|
| **Density > Face Count** | `-f` | `2000` | 目标输出面数 | 最通用的密度控制方式。提高数值可以保留更多小细节，但计算时间和输出规模也会增加。 |
| **Density > Edge Length** | `-s` | `-1` | 目标边长，单位与导出的 OBJ 一致 | 适合需要统一物理网格尺度的多个模型。`-1` 表示由 CLI 自动决定。 |
| **Density > Vertex Count** | `-v` | `-1` | 目标输出顶点数 | 适合后续流程有顶点预算时使用。`-1` 表示由 CLI 自动决定。 |
| **RoSy** | `-r` | `4` | 方向场的旋转对称阶数 | 普通四边形重拓扑使用 `4`。有效值为 `2`、`4`、`6`。 |
| **PoSy** | `-p` | `4` | 位置场的平移/位置对称类型 | 四边形使用 `4`；三角形或六边形倾向的布局使用 `3`。 |
| **Extrinsic** | 关闭时传 `-i` | 开 | 使用模型在三维空间中的嵌入关系进行优化 | 通常保持开启。模型折叠严重或希望按曲面内部距离计算时可关闭，切换为 Intrinsic。 |
| **Crease Angle** | `-c` | `-1` | 用于识别和对齐锐边的二面角阈值，单位为度 | `-1` 为自动处理。硬表面模型可从 `30`-`60` 度开始尝试。数值越小，越多边会被视为锐边。 |
| **Align Boundaries** | `-b` | 关 | 让方向场沿开放边界排列 | 开放网格且边界走向重要时开启；对完全封闭的网格基本没有作用。 |
| **Quad-Dominant** | `-D` | 关 | 允许在困难区域生成少量非四边形面 | 当稳定生成结果比纯四边形更重要时开启。关闭时更倾向纯四边形输出。 |
| **Smooth Iterations** | `-S` | `2` | 网格提取前对方向场进行平滑的次数 | 增大后拓扑流向更规整，但可能削弱局部特征对齐，并增加计算时间。通常使用 `2`-`4`。 |
| **Deterministic** | `-d` | 关 | 使用确定性处理，使相同输入更容易得到一致结果 | 自动化测试、批处理和结果复现时开启；可能降低速度。 |
| **Threads** | `-t` | `0` | 最大工作线程数 | `0` 表示由 CLI 自动选择。设置正整数可以限制 CPU 占用。 |

### RoSy 与 PoSy 组合解读

| RoSy | PoSy | 常见结果 |
|------|------|----------|
| `4` | `4` | 标准四边形重拓扑，推荐默认组合 |
| `6` | `3` | 偏向三角形/六边形的布局 |
| `2` | `4` | 双向方向场，适合特殊的方向性布局，不是常规四边形首选 |

### 推荐参数组合

| 目标 | 推荐设置 |
|------|----------|
| 通用四边形重拓扑 | 按需求设置 Face Count，RoSy `4`，PoSy `4`，Extrinsic 开，Smooth `2` |
| 硬表面和锐边 | RoSy `4`，PoSy `4`，Crease Angle `30`-`60`；开放网格可开启 Align Boundaries |
| 有机曲面 | RoSy `4`，PoSy `4`，Crease Angle `-1`，Smooth `2`-`4` |
| 优先稳定生成 | 开启 Quad-Dominant，允许困难区域出现少量非四边形面 |
| 需要复现结果 | 开启 Deterministic，并设置固定的正整数 Threads |

CLI 还提供 `-k/--knn`，但插件有意不把它放进 UI。KNN 用于点云输入的邻域构建，
而当前插件只接受 Blender Mesh，并将其导出为 OBJ；因此该参数在现有插件流程中不会
产生作用。除仅用于命令行帮助的 `-h/--help` 外，UI 已覆盖所有对 Mesh/OBJ 流程有效的
CLI 参数。

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
