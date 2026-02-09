# Imperion Online - Claude Code Project Instructions

## Project Overview
A multiplayer open-world space game built with **Godot 4.6** (GDScript).
Inspired by X4 Foundations, Star Citizen, BSG Online, DarkOrbit.
Goal: hundreds of thousands of star systems, planetary landing, trading, combat, fleet management.

## Tech Stack
- **Engine**: Godot 4.6 (Forward+ Vulkan renderer)
- **Language**: GDScript (64-bit float vars) + GDExtension C++ for perf-critical systems later
- **Multiplayer**: ENet (UDP) for real-time + WebSocket for reliable events (future)
- **Backend**: Dedicated server (Godot headless or Node.js) + PostgreSQL + Redis (future)

## Critical Architecture Decisions

### Floating Origin System
ALL positions in the game use a floating origin. The player ship stays near world origin (0,0,0).
When the ship moves beyond `ORIGIN_SHIFT_THRESHOLD` (5000 units), ALL scene objects are shifted
back so the ship is at origin again. A cumulative `origin_offset` (stored as 3 separate float64 vars)
tracks the true universe position.
- **WHY**: Godot's Vector3 is 32-bit float. At >10km from origin, visible jitter occurs.
- **RULE**: NEVER store absolute universe positions as Vector3. Use the FloatingOrigin singleton.

### Coordinate System
- Godot uses Y-up, right-handed. Forward is -Z.
- 1 unit = 1 meter
- Star systems are spaced ~1e9 to 1e12 units apart (handled by hyperspace jumps, not continuous flight)
- Within a system, playable area is ~1e8 units (100,000 km) - floating origin handles this

### Scene Architecture
- `main.tscn` is the persistent root scene
- Star systems are loaded/unloaded dynamically into the `Universe` node
- The player ship is always present, added to the scene tree by GameManager
- UI lives in a CanvasLayer, independent of 3D scene

### Autoload Singletons (load order matters)
1. `Constants` - res://scripts/core/constants.gd
2. `FloatingOrigin` - res://scripts/core/floating_origin.gd
3. `GameManager` - res://scripts/core/game_manager.gd

## File Structure
```
scripts/
  core/           # Engine-level systems (autoloads, base classes)
  ship/           # Ship flight, weapons, shields, systems
  universe/       # Star systems, planets, stations, generation
  economy/        # Trading, inventory, dynamic economy
  combat/         # Damage model, projectiles, AI pilots
  multiplayer/    # Networking, sync, zone servers
  ui/             # HUD, menus, star map
scenes/           # .tscn scene files (kept minimal, logic in scripts)
shaders/          # .gdshader files
assets/
  models/         # .glb/.gltf 3D models
  textures/       # Texture files
  audio/          # Sound effects, music
docs/             # Architecture docs, system design notes
```

## Coding Conventions
- GDScript style: snake_case for vars/functions, PascalCase for classes/nodes
- Use `@export` for designer-tunable values
- Use signals for decoupled communication between systems
- Use typed variables: `var speed: float = 0.0`
- Keep scripts under 300 lines. Split into components if larger.
- Every system script has a class_name declaration

## How to Work on This Project
1. Read this file first for context
2. Check `docs/ARCHITECTURE.md` for system design details
3. Check the relevant `scripts/` subfolder for the system you're modifying
4. Test by having the user open Godot and press F5 (or use godot-mcp run_project)
5. Use `print()` for debug output, check Godot console

## Current State
- **Phase 1 (IN PROGRESS)**: Core flight + space environment
  - [x] Project structure and architecture
  - [x] Floating origin system
  - [x] Ship controller (6DOF flight)
  - [x] Ship camera (3rd person)
  - [x] Procedural starfield skybox
  - [x] Basic space station
  - [x] Flight HUD
  - [ ] Sound effects
  - [ ] Ship boost/cruise modes polish

## Commit Message Format for Discord Devlog
Every commit that triggers a build (non-ci: prefix) MUST include a community-friendly
French summary as the commit message. This message is automatically posted to Discord #devlog.

Rules:
- Write in French, informal/gaming tone
- Describe WHAT changed for players, not HOW the code changed
- NO file names, function names, or technical details
- NO "fix bug in X.gd" — instead "Correction du systeme de combat"
- Examples:
  - "Nouveau systeme de minage: extrayez des minerais des asteroides!"
  - "Amelioration du combat: les boucliers directionnels sont maintenant fonctionnels"
  - "Correction d'un bug ou les vaisseaux NPC ne tiraient pas correctement"

## Phase Roadmap
- Phase 2: Universe generation (star systems, planets, hyperspace jumps)
- Phase 3: Combat (weapons, shields, damage, AI enemies)
- Phase 4: Economy (stations, trading, cargo, dynamic prices)
- Phase 5: Multiplayer (dedicated server, player sync, zones)
- Phase 6: Planetary landing, FPS mode, base building, fleets
