class_name UILayout
extends RefCounted

# =============================================================================
# UI Layout - Static utility for standard screen positions
# =============================================================================

## Returns the rect for the title area at the top of a screen.
static func title_rect(screen_size: Vector2) -> Rect2:
	return Rect2(
		UITheme.MARGIN_SCREEN,
		UITheme.MARGIN_SCREEN,
		screen_size.x - UITheme.MARGIN_SCREEN * 2,
		UITheme.FONT_SIZE_TITLE + 20
	)


## Returns a sidebar rect on the given side.
static func sidebar_rect(screen_size: Vector2, side: int = 0, width: float = 300.0) -> Rect2:
	var top: float = UITheme.MARGIN_SCREEN + UITheme.FONT_SIZE_TITLE + 30
	var h: float = screen_size.y - top - UITheme.MARGIN_SCREEN
	if side == 0:  # Left
		return Rect2(UITheme.MARGIN_SCREEN, top, width, h)
	else:  # Right
		return Rect2(screen_size.x - UITheme.MARGIN_SCREEN - width, top, width, h)


## Returns the main content rect, accounting for an optional sidebar.
static func content_rect(screen_size: Vector2, has_sidebar: bool = false, sidebar_w: float = 300.0) -> Rect2:
	var top: float = UITheme.MARGIN_SCREEN + UITheme.FONT_SIZE_TITLE + 30
	var h: float = screen_size.y - top - UITheme.MARGIN_SCREEN
	var left: float = UITheme.MARGIN_SCREEN
	var w: float = screen_size.x - UITheme.MARGIN_SCREEN * 2
	if has_sidebar:
		left += sidebar_w + UITheme.MARGIN_SECTION
		w -= sidebar_w + UITheme.MARGIN_SECTION
	return Rect2(left, top, w, h)
