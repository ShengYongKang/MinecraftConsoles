# MinecraftConsoles

[![Discord](https://img.shields.io/badge/Discord-Join%20Server-5865F2?logo=discord&logoColor=white)](https://discord.gg/jrum7HhegA)

![Tutorial World](.github/TutorialWorld.png)

## 项目简介

这个仓库整理并维护了 Minecraft Legacy Console Edition v1.6.0560.0（TU19）的源码，并在原始代码基础上加入了一批面向现代 Windows 环境的修复与改进。

当前仓库可以理解为三部分的组合：

- 原始 Legacy Console Edition 游戏代码
- 4J 风格的多平台工程与资源布局
- 面向 Windows x64 的现代化适配与可运行构建路径

源码来源说明：

- 原始代码基于归档资料整理而来：<https://archive.org/details/minecraft-legacy-console-edition-source-code>
- 当前仓库在此基础上继续做了修复、兼容和工程化改造

Nightly 构建：

- <https://github.com/smartcmd/MinecraftConsoles/releases/tag/nightly>

## 当前状态

### 已验证路径

- `Windows + Visual Studio 2022 + Windows64`：当前主要维护和推荐的构建方式
- `Windows + CMake + x64`：当前可用的现代构建方式

### 仓库里“看起来支持”但目前不要默认可用的内容

解决方案和源码目录里仍然保留了大量历史平台相关配置和资源，例如：

- Xbox 360
- Durango / Xbox One
- Orbis / PS4
- PS3
- PSVita
- ARM64EC

这些内容的存在主要说明这是一个保留原始工程形态的源码仓库，不代表这些平台在当前仓库状态下都能直接成功构建、运行或发布。

一句话概括当前结论：

- 现在真正可依赖的目标平台是 Windows x64

## 主要特性

相对于原始工程，仓库目前明确提供或保留了以下能力：

- 支持在 Windows 上以 Debug 和 Release 配置构建
- 补充了键盘和鼠标输入
- 增加了无边框全屏切换，默认快捷键为 `F11`
- 优化了高帧率下的计时路径
- 使用设备实际分辨率，而不是固定 `1920x1080`
- 支持 Windows 下的局域网联机与房间发现

## 局域网联机

Windows 构建包含一套基于 Winsock 的局域网多人联机实现。

- 游戏连接默认使用 TCP `25565`
- 局域网发现默认使用 UDP `25566`
- 主机在本地网络中广播房间信息
- 其他玩家可在游戏内 `Join Game` 菜单中发现房间

用户名可以在启动时通过命令行参数覆盖：

```powershell
Minecraft.Client.exe -name Steve
```

这部分功能基于 LCEMP 的思路继续实现和整合：

- <https://github.com/LCEMP/LCEMP/>

## 键盘和鼠标操作

- 移动：`W` `A` `S` `D`
- 跳跃 / 飞行上升：`Space`
- 潜行 / 飞行下降：`Shift`
- 疾跑：`Ctrl` 或双击 `W`
- 背包：`E`
- 丢弃物品：`Q`
- 合成：`C`
- 第三人称视角：`F5`
- 暂停菜单：`Esc`
- 游戏信息 / 玩家列表：`Tab`
- 攻击 / 破坏：鼠标左键
- 使用 / 放置：鼠标右键
- 切换快捷栏：鼠标滚轮或 `1` 到 `9`
- HUD 开关：`F1`
- 调试信息：`F3`
- 调试覆盖层：`F4`
- 全屏切换：`F11`
- 鼠标捕获切换：`Left Alt`
- 教程确认 / 拒绝：`Enter` / `B`

## 快速开始

### 方式一：Visual Studio 2022

1. 安装 Visual Studio 2022，并确保包含 C++ 桌面开发组件。
2. 克隆仓库。
3. 打开 `MinecraftConsoles.sln`。
4. 将 `Minecraft.Client` 设为启动项目。
5. 将构建配置设置为 `Debug` 或 `Release`。
6. 将目标平台设置为 `Windows64`。
7. 直接编译并运行。

说明：

- `Debug` 仍然是更推荐的开发配置
- `Release` 可构建，但仓库现状下仍可能存在一些运行时问题

### 方式二：CMake（Windows x64）

配置：

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
```

构建 Debug：

```powershell
cmake --build build --config Debug --target MinecraftClient
```

构建 Release：

```powershell
cmake --build build --config Release --target MinecraftClient
```

运行：

```powershell
cd .\build\Debug
.\MinecraftClient.exe
```

更细的构建说明见：

- [COMPILE.md](COMPILE.md)

## 构建前提

### 编译器与工具链

- Visual Studio 2022
- MSVC v143 工具链
- 64 位 Windows 环境

### 图形与系统依赖

当前 Windows 客户端链接并依赖以下内容：

- Direct3D 11
- XInput
- Winsock
- 仓库内自带的 Iggy、Miles、4J 相关库

从 GitHub Actions 的 nightly 描述来看，当前 Windows 构建的目标运行环境至少包括：

- Windows 7 或更高版本
- 支持 DirectX 11 的显卡

## 运行时资源说明

这个项目不是“编译出一个 exe 就能随便挪”的那种仓库。游戏运行依赖大量相对路径资源。

关键点：

- 必须从输出目录启动程序
- 输出目录需要带上资源、媒体文件和运行库
- CMake 会在 `MinecraftClient` 构建后自动复制这些内容

当前 CMake 后处理会复制或准备的内容包括：

- `Common/Media/MediaWindows64.arc`
- `Common/res`
- `Common/Trial`
- `Common/Tutorial`
- `music`
- `Windows64/GameHDD`
- `Windows64Media`
- `redist64` 运行库目录
- `iggy_w64.dll`
- `mss64.dll`

如果你手动折腾输出目录，最容易踩的坑就是：

- 资源目录不完整
- 工作目录不对
- 缺少运行时 DLL

## 仓库结构

### 根目录

- `MinecraftConsoles.sln`：Visual Studio 解决方案
- `CMakeLists.txt`：当前维护中的 CMake 入口
- `COMPILE.md`：补充构建说明
- `cmake/`：CMake 源文件列表和资源复制脚本
- `.github/workflows/`：Windows 构建与 nightly 发布流程
- `x64/`：Visual Studio 默认输出目录

### `Minecraft.World/`

游戏世界与核心逻辑静态库，基本可以把它看成“服务端逻辑 + 世界模拟 + 数据结构 + 协议层”的主体。

这里包含的内容很多，例如：

- 方块、物品、生物、实体
- 生物群系与地形生成
- 容器、配方、附魔、指令
- 存档与 NBT
- 网络包与连接逻辑
- 世界存储实现

在 CMake 中它被构建为：

- `MinecraftWorld`（静态库）

### `Minecraft.Client/`

客户端可执行程序，包含渲染、UI、输入、平台适配、资源、音频和联机前端逻辑。

比较关键的子目录：

- `Common/`：跨平台共享客户端代码、UI、教程、音频、规则、媒体资源
- `Windows64/`：当前最重要的平台适配层，包含 Win64 启动、输入、网络和窗口逻辑
- `Windows64Media/`：当前 Windows 运行时会用到的媒体资源
- `Durango/`、`Orbis/`、`PS3/`、`PSVita/`、`Xbox/`：保留的主机平台相关代码与资源
- `music/`：音乐资源

在 CMake 中它被构建为：

- `MinecraftClient`（Windows GUI 可执行程序）

### `cmake/`

- `WorldSources.cmake`：`Minecraft.World` 源文件清单
- `ClientSources.cmake`：`Minecraft.Client` 源文件清单
- `CopyAssets.cmake`：构建后资源复制逻辑

### `.github/workflows/`

- `build.yml`：在 `windows-2022` 上构建 Debug/Release
- `nightly.yml`：在主分支更新 nightly 发布包

## 工程组织方式

虽然仓库里有非常多文件，但当前可以按下面的工程关系理解：

1. `Minecraft.World` 先编译为静态库
2. `Minecraft.Client` 链接这个静态库，并接入平台层和第三方库
3. 构建结束后再把运行时资源复制到输出目录

这也是为什么你会同时看到：

- 游戏逻辑代码
- 历史主机平台代码
- Windows 适配代码
- 资源与语言文件
- 第三方库源码和二进制依赖

## 第三方与内置依赖

仓库内已经包含一部分第三方或外部依赖内容，至少包括：

- `zlib`
- Iggy 相关库与 DLL
- Miles Sound System 相关库与 DLL
- 4J 相关输入、存储、渲染库

这意味着当前仓库更接近“可自包含构建的游戏源码树”，而不是一个只依赖系统包管理器拉取依赖的现代小型项目。

## 语言与资源

仓库内保留了大量本地化和平台媒体资源。

从代码和资源目录可以看出，至少涉及：

- 英文
- 日文
- 德文
- 法文
- 西班牙文
- 意大利文
- 韩文
- 繁体中文
- 葡萄牙文
- 巴西葡萄牙文
- 俄文
- 荷兰文
- 北欧语系与其他地区语言资源

因此这个仓库不仅仅是代码仓库，同时也是一个体量很大的资源仓库。

## CI 与发布

仓库已经配置 GitHub Actions：

- `build.yml` 会在 Windows 环境构建 `Debug` 和 `Release`
- `nightly.yml` 会在 `main` 分支推送时生成并更新 nightly 包

默认上传或发布的仍然是 Windows 构建产物。

## 已知限制

- 当前 CMake 明确限制为 `Windows only`
- 当前 CMake 明确要求 `x64`
- 非 Windows 原生构建目前不在维护范围内
- macOS / Linux 用户即便能通过 Wine 或 CrossOver 运行 nightly，也不代表仓库提供了这些平台的原生构建支持
- 仓库保留的大量主机平台代码主要用于保留原始结构、参考实现和资源，不应视为“现成可用”

## 对新贡献者的建议

如果你第一次接触这个仓库，建议按下面顺序理解：

1. 先看 `README.md`
2. 再看 `COMPILE.md`
3. 优先使用 Visual Studio 2022 的 `Windows64` 配置跑通一次
4. 然后再看 `CMakeLists.txt` 和 `cmake/CopyAssets.cmake`
5. 最后再进入 `Minecraft.Client/Windows64` 和 `Minecraft.Client/Common` 定位平台行为或 UI 逻辑

如果你是要改玩法或世界逻辑，优先看：

- `Minecraft.World/`

如果你是要改输入、窗口、联机发现、Windows 启动行为，优先看：

- `Minecraft.Client/Windows64/`

如果你是要改 UI、教程、菜单、客户端行为，优先看：

- `Minecraft.Client/Common/`

## 授权与使用注意

仓库当前没有随根目录提供标准 `LICENSE` 文件。

同时，这个项目的源码来源于归档的 Legacy Console Edition 代码资料。因此在以下场景中建议你先自行确认授权和合规边界：

- 二次分发
- 商业使用
- 将代码或资源直接并入其他项目
- 发布带完整资源的二进制包

## 参考文档

- [COMPILE.md](COMPILE.md)
- Nightly Release: <https://github.com/smartcmd/MinecraftConsoles/releases/tag/nightly>
- LCEMP: <https://github.com/LCEMP/LCEMP/>
- Archive Source Reference: <https://archive.org/details/minecraft-legacy-console-edition-source-code>

## 总结

如果只用一句话描述这个仓库：

这是一个保留了 Legacy Console Edition 原始多平台工程形态、但当前主要面向 Windows x64 继续修复和可运行化的超大型游戏源码仓库。
