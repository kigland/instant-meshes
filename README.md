# ✨ Instant Meshes CLI

> 🏗️ 一键自动重拓扑 · 干净 · 快速 · 可爱

基于 SIGGRAPH Asia 2015 论文 [**Instant Field-Aligned Meshes**](http://igl.ethz.ch/projects/instant-meshes/) 的命令行版本，去掉了 GUI，保留核心算法，支持 GLB / glTF / OBJ / PLY。

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS_ARM64-pink?style=flat-square" alt="macOS ARM64">
  <img src="https://img.shields.io/badge/license-BSD--3-blue?style=flat-square" alt="BSD-3">
  <img src="https://img.shields.io/badge/based_on-Instant_Meshes-ff69b4?style=flat-square" alt="based on Instant Meshes">
</p>

---

## 🎀 这是什么

把乱七八糟的高面数三角网格，变成干净整齐的四边面（或三角面），并且保持原有形状。俗称**重拓扑**。

```
    🪨 输入 (50,000 三角面)  ──→  🧊 输出 (2,000 四边面)
```

## 📦 下载

[![Download](https://img.shields.io/badge/⬇️%20下载-macOS_ARM64-f5a?style=for-the-badge)](https://github.com/kigland/instant-meshes/releases/latest)

## 🚀 快速开始

```bash
# 基本用法：输入 GLB，输出 OBJ，2000 面
./instantmeshes-cli model.glb output.obj -f 2000

# 高精度
./instantmeshes-cli model.glb output.obj -f 10000

# 三角面 / 六边面
./instantmeshes-cli model.glb output.obj -f 3000 -r 6 -p 3

# 保留硬边
./instantmeshes-cli model.ply output.obj -f 2000 -c 30
```

## 🎛️ 全部参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-f, --faces` | 目标面数 | 自动 |
| `-s, --scale` | 目标边长 | 自动 |
| `-v, --vertices` | 目标顶点数 | 自动 |
| `-r, --rosy` | 旋转对称性 `2` `4` `6` | `4` |
| `-p, --posy` | 位置对称性 `3` `4` | `4` |
| `-c, --crease` | 硬边角度阈值（度） | `-1` 自动 |
| `-i, --intrinsic` | 内蕴模式 | 关闭 |
| `-b, --boundaries` | 对齐边界 | 关闭 |
| `-D, --dominant` | 非纯四边形输出 | 关闭 |
| `-S, --smooth` | 平滑迭代次数 | `2` |
| `-k, --knn` | 点云邻居数 | `10` |
| `-d, --deterministic` | 确定性模式 | 关闭 |
| `-t, --threads` | 线程数 | 自动 |
| `-h, --help` | 帮助 | — |

## 🛠️ 从源码编译

```bash
git clone --recursive https://github.com/kigland/instant-meshes
cd instant-meshes
cmake -S . -B build
cmake --build build -j$(sysctl -n hw.logicalcpu)
# 二进制在: build/instantmeshes-cli
```

## 📚 算法简介

Instant Field-Aligned Meshes 是 ETH Zurich 发表的自动重拓扑算法。它在输入网格上计算两个场：

1. **方向场** (Orientation Field) — 决定四边形面的朝向，沿表面特征线对齐
2. **位置场** (Position Field) — 决定顶点在参数网格上的精确位置

最后通过追踪场的等值线提取四边形网格。支持 4-RoSy（四边形）、6-RoSy（六边形/三角形）等对称类型。

> 📄 **论文**: Wenzel Jakob, Marco Tarini, Daniele Panozzo, Olga Sorkine-Hornung. *Instant Field-Aligned Meshes*. ACM Transactions on Graphics (SIGGRAPH Asia 2015).  
> [PDF](http://igl.ethz.ch/projects/instant-meshes/instant-meshes-SA-2015-jakob-et-al.pdf) · [Video](https://www.youtube.com/watch?v=U6wtw6W4x3I)

## 💝 致谢

本项目基于 [wjakob/instant-meshes](https://github.com/wjakob/instant-meshes) 的核心算法。
- GLB/glTF 支持由 [cgltf](https://github.com/jkuhlmann/cgltf) 提供
- 并行计算由 [Intel TBB](https://github.com/oneapi-src/oneTBB) 支持
- 线性代数由 [Eigen](https://eigen.tuxfamily.org/) 提供
