# SpaceGame Architecture

## System Overview

```
┌─────────────────────────────────────────────────┐
│                    Main Scene                     │
│  ┌───────────┐  ┌──────────┐  ┌──────────────┐  │
│  │ StarLight  │  │ WorldEnv │  │ SkyboxMesh   │  │
│  └───────────┘  └──────────┘  └──────────────┘  │
│  ┌──────────────────────────────────────────┐    │
│  │           Universe (Node3D)               │    │
│  │  ┌────────────┐  ┌───────────────────┐   │    │
│  │  │SpaceStation│  │ Asteroids (future)│   │    │
│  │  └────────────┘  └───────────────────┘   │    │
│  └──────────────────────────────────────────┘    │
│  ┌──────────────────────────────────────────┐    │
│  │         PlayerShip (RigidBody3D)          │    │
│  │  ┌──────┐ ┌────────┐ ┌──────────────┐   │    │
│  │  │Model │ │Collider│ │ CameraPivot  │   │    │
│  │  └──────┘ └────────┘ │  └─Camera3D  │   │    │
│  │                       └──────────────┘   │    │
│  └──────────────────────────────────────────┘    │
│  ┌──────────────────────────────────────────┐    │
│  │            UI (CanvasLayer)                │    │
│  │  ┌──────────────────────────────────┐    │    │
│  │  │          FlightHUD               │    │    │
│  │  └──────────────────────────────────┘    │    │
│  └──────────────────────────────────────────┘    │
└─────────────────────────────────────────────────┘

Autoloads (always available):
  Constants -> FloatingOrigin -> GameManager
```

## Floating Origin System

The most critical system in the game. Prevents float32 precision loss.

### How it works
1. Player flies around. Ship position in scene tree is the actual Node3D position.
2. FloatingOrigin tracks `origin_offset_x/y/z` (float64 GDScript vars).
3. When `ship.position.length() > ORIGIN_SHIFT_THRESHOLD`:
   a. Calculate shift = ship.global_position
   b. Add shift to origin_offset
   c. Move ALL objects in "Universe" node by -shift
   d. Move ship to near-zero
   e. Emit `origin_shifted(shift)` signal
4. True universe position = origin_offset + local_position

### Rules for all systems
- To get a universe position: `FloatingOrigin.to_universe_pos(node.global_position)`
- To set from universe pos: `node.global_position = FloatingOrigin.to_local_pos(universe_pos)`
- When spawning objects, always use local positions relative to current origin
- Listen to `FloatingOrigin.origin_shifted` if you cache absolute positions

## Ship Flight Model

### Physics Approach
- RigidBody3D with `custom_integrator = true`
- We control all forces in `_integrate_forces(state)`
- This gives us collision detection from Godot + full control over movement

### Flight Model
- 6 Degrees of Freedom (6DOF): translate X/Y/Z + rotate pitch/yaw/roll
- Newtonian: thrust produces acceleration, no drag in space
- Optional "flight assist" dampener that kills unwanted velocity (like X4/Elite)
- Three speed modes:
  - Normal: 0-300 m/s, full maneuverability
  - Boost: 0-600 m/s, reduced maneuverability (shift held)
  - Cruise: 0-3000 m/s, very reduced maneuverability (toggle)

### Input Scheme
- Mouse: Pitch (Y) and Yaw (X)
- W/S: Thrust forward/backward
- A/D: Strafe left/right
- Space/Ctrl: Strafe up/down
- Q/E: Roll left/right
- Shift: Boost
- C: Toggle cruise mode
- V: Toggle camera mode (3rd person / cockpit)
- Scroll: Adjust camera distance (3rd person only)

## Camera System

- CameraPivot as child of ship for basic following
- Smooth rotation interpolation (doesn't snap to ship orientation)
- Two modes:
  - Third Person: Offset behind and above ship, adjustable distance
  - Cockpit: Fixed position at ship front

## Procedural Skybox

- ShaderMaterial on a large inverted sphere/box
- Star field generated via hash-based noise in fragment shader
- Multiple star layers: dim background + bright foreground stars
- Will add nebulae in Phase 2

## Future: Star System Generation

Seed-based deterministic generation:
```
master_seed
  └── sector_seed = hash(master, sector_x, sector_y, sector_z)
       └── star_seed = hash(sector_seed, star_index)
            └── planet_seed = hash(star_seed, planet_index)
```
Everything regeneratable from seed alone. No world data stored.

## Future: Multiplayer Architecture

```
[Godot Client] ←─ ENet UDP ──→ [Zone Server (per star system)]
                                       │
                                  [Redis Pub/Sub]
                                       │
                                 [World Coordinator]
                                       │
                                  [PostgreSQL]
```
- Each star system = one zone server process
- Hyperspace jump = handoff between zone servers
- Redis for cross-zone messaging and session state
- PostgreSQL for persistent data (accounts, inventory, economy)
