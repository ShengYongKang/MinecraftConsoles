# OurEra (Godot 重写版原型)

这是一个基于当前仓库 Minecraft 逻辑重写的 Godot 4 原型工程，目标是先建立可维护的结构与可运行玩法闭环。

## 参考逻辑
- 区块横向尺寸：`16 x 16`
- 海平面：`63`
- 体素高度：`128`（对应原工程 `genDepth` 体系）
- 基于噪声的地形生成 + 方块可破坏/放置

## 已实现
- 第一人称移动（WASD + 空格跳跃）
- 鼠标视角控制
- 射线挖掘（左键）
- 方块放置（右键）
- 区块网格重建与碰撞
- 基于玩家位置的区块流式加载/卸载（分帧预算）

## 资源
- 临时方块纹理来自原工程：
  - `Minecraft.Client/Common/res/terrain.png`
  - 已复制到 `assets/textures/terrain.png`

## 运行方式
1. 使用 Godot 4.x 打开 `OurEra/project.godot`
2. 运行主场景 `scenes/Main.tscn`
3. `Esc` 切换鼠标锁定/释放

## 性能调参（`scripts/world.gd` 导出参数）
- `load_radius_chunks`: 加载半径（默认 4）
- `unload_radius_chunks`: 卸载半径（默认 6，需大于加载半径）
- `max_chunk_generations_per_frame`: 每帧最多生成多少区块数据
- `max_chunk_mesh_updates_per_frame`: 每帧最多重建多少区块网格
- `collision_radius_chunks`: 只给近距离区块构建碰撞，减轻 CPU 压力

## 当前边界
- 这是第一版玩法原型，尚未接入：生物、物品栏、存档、光照传播、流体、网络同步等。
- 后续可在现有结构上分层扩展（世界数据层 / 渲染层 / 交互层）。
