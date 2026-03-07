# OurEra

Godot 4 voxel prototype inspired by the Minecraft console source layout in this repository.

## Current scope

- First-person movement, jumping, block breaking, and block placement
- Finite-height voxel terrain with 16x16 chunk columns and sea level near 63
- Streaming chunk loading and unloading around the player
- Background chunk generation with main-thread integration budgets
- Frame-budgeted mesh rebuild scheduling
- Greedy chunk meshing to reduce triangle count and rebuild cost
- Repeating atlas tiles on merged greedy quads
- Optional native GDExtension greedy mesher bridge with automatic GDScript fallback
- Collision meshes only for nearby chunks
- LRU-style eviction for clean unloaded chunk data

## Run

1. Open [project.godot](D:\UGit\MinecraftConsoles\OurEra\project.godot) in Godot 4.x
2. Run [Main.tscn](D:\UGit\MinecraftConsoles\OurEra\scenes\Main.tscn)
3. Use `WASD`, `Space`, mouse look, `LMB`, `RMB`, and `Esc`

## Assets

- Temporary block texture atlas copied from the original project:
- `Minecraft.Client/Common/res/terrain.png`
- Local copy:
- `assets/textures/terrain.png`

## Performance notes

- `World.load_radius_chunks` controls how many chunks are targeted for loading
- `World.unload_radius_chunks` controls when chunk nodes are removed
- `World.generator_thread_count` controls how many worker threads prepare chunk data
- `World.max_active_generation_jobs` caps queued and in-flight generation work
- `World.max_chunk_generations_per_frame` caps how many generation jobs are dispatched per frame
- `World.max_completed_chunk_integrations_per_frame` caps how many worker results are attached per frame
- `World.max_chunk_mesh_updates_per_frame` caps mesh rebuild work per frame
- `World.collision_radius_chunks` keeps expensive collision generation near the player
- `World.max_cached_clean_chunks` limits how many clean unloaded chunks stay in memory

## Tradeoff

Dirty unloaded chunks are kept in memory and are not evicted yet. That avoids losing block edits before a save system exists, but long play sessions with many modified chunks will still grow memory usage.
