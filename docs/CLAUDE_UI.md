# UI Development Guidelines — Imperion Online

## Architecture

The UI system is a custom `_draw()` framework with 4 base classes:

| Class | Role |
|-------|------|
| `UITheme` | Autoload singleton — colors, fonts, spacing constants |
| `UIComponent` | Base Control — draw helpers, hologram shader |
| `UIScreen` | Fullscreen/overlay — blur, transitions, particles |
| `UIScreenManager` | Screen stack — manages open/close, post-processing |

All 50+ consumer files (HUD, screens, map, etc.) inherit from these.
**Never modify consumers for visual changes** — always modify the base.

## Visual Identity

- **Palette**: Orange/amber (Elite Dangerous inspired)
- **Primary**: `Color(1.0, 0.55, 0.0)` — orange
- **Accent**: `Color(0.0, 1.0, 0.6)` — green (positive/health)
- **Shields**: `Color(0.2, 0.6, 1.0)` — blue (always blue, Elite convention)
- **Font**: Rajdhani (Google Fonts, SIL OFL license)
- **Effects**: Hologram shaders (scanlines, grain, flicker, edge glow)

## Rules

1. **Colors** — always use `UITheme.CONSTANT`, never hardcode colors
2. **Fonts** — use `UITheme.get_font()`, `.get_font_medium()`, `.get_font_bold()`
3. **Font sizes** — use `UITheme.FONT_SIZE_*` constants
4. **Spacing** — use `UITheme.MARGIN_*`, `ROW_HEIGHT`, `CORNER_LENGTH`
5. **Shaders** — get materials from `UIShaderCache`, never `load()` shaders directly
6. **Transitions** — use `UITransition.*` static methods, never manual tween creation
7. **Screens** — extend `UIScreen`, register via `UIScreenManager.register_screen()`

## Shader Pipeline

```
UIComponent._draw()  →  Hologram aesthetic via draw helpers (scanlines, corners, glow)
UIScreen background  →  ui_blur.gdshader (frosted glass, via UIScreenManager)
UIScreenManager      →  ui_post_process.gdshader (full-screen scanlines+vignette)
```

**Note**: `use_panel_shader` defaults to `false`. The hologram panel shader
(`ui_hologram_panel.gdshader`) uses the FBO rendering path which conflicts with
parent modulate tweens (fade-in transitions). The hologram aesthetic is instead
achieved through `_draw()` calls (draw_panel_bg, draw_scanline, draw_corners).

## Adding a New Screen

```gdscript
class_name MyScreen
extends UIScreen

func _ready() -> void:
    screen_title = "MY SCREEN"
    screen_mode = ScreenMode.FULLSCREEN
    super._ready()

func _on_opened() -> void:
    # Setup logic here
    pass

func _draw() -> void:
    super._draw()
    # Custom drawing below title area
    var y: float = UITheme.MARGIN_SCREEN + UITheme.FONT_SIZE_TITLE + 20
    # ...
```

## Adding a New Component

```gdscript
class_name MyWidget
extends UIComponent

func _ready() -> void:
    super._ready()
    # use_panel_shader defaults to false (no FBO shader)
    # Set use_panel_shader = true only on large static panels

func _draw() -> void:
    draw_panel_bg(Rect2(Vector2.ZERO, size))
    # Custom drawing...
```

## Performance

- Hologram panel shader is opt-in (`use_panel_shader = true`), avoids unnecessary FBO overhead
- Particles are CPU-based (60 rects), negligible cost
- Blur uses `hint_screen_texture` (hardware mip-mapped)
- Post-process is a single full-screen pass
- `queue_redraw()` only during transitions, not every frame when static
