# Native Greedy Mesher

This folder contains the GDExtension scaffold for the native greedy mesher backend.

## Scope

- Native only: voxel scan, greedy face merge, vertex/index/UV/color generation
- GDScript stays responsible for: world streaming, rebuild budgets, fallback selection, material setup, mesh submission, collision policy

## Build prerequisites

1. A local `godot-cpp` checkout already generated and built for Godot 4.6
2. MSVC toolchain available via Visual Studio Build Tools / Community
3. CMake 3.21+

## Configure

```powershell
cmake -S native/voxel_mesher -B native/voxel_mesher/build -G "Visual Studio 18 2026" -A x64 -DGODOT_CPP_DIR=D:/path/to/godot-cpp
cmake --build native/voxel_mesher/build --config Release
```

Debug output is expected at:
- `res://native/voxel_mesher/bin/windows/ourera_mesher.windows.template_debug.x86_64.dll`

Release output is expected at:
- `res://native/voxel_mesher/bin/windows/ourera_mesher.windows.template_release.x86_64.dll`

## Runtime selection

- `scripts/render/mesh_builder_backend.gd` loads the GDExtension if the DLL exists and the class registers successfully.
- If loading fails, the project falls back to the current GDScript mesher automatically.
- Set `OURERA_DISABLE_NATIVE_MESHER=1` to force the GDScript path for comparison.
