class_name ClanTabDiplomacy
extends UIComponent

# =============================================================================
# Clan Tab: Diplomacy - Rich relation list with colored status + action panel
# =============================================================================

var _cm: ClanManager = null
var _clan_list: UIScrollList = null
var _btn_ally: UIButton = null
var _btn_war: UIButton = null
var _btn_neutral: UIButton = null

var _selected_clan_id: String = ""
var _clan_ids: Array[String] = []

const RELATION_COLORS := {
	"ALLIE": Color(0.0, 1.0, 0.6, 0.9),
	"ENNEMI": Color(1.0, 0.2, 0.15, 0.9),
	"NEUTRE": Color(0.45, 0.65, 0.78, 0.7),
}

const RELATION_LABELS := {
	"ALLIE": "ALLIANCE",
	"ENNEMI": "EN GUERRE",
	"NEUTRE": "NEUTRE",
}

const LEFT_W := 300.0
const GAP := 16.0


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_STOP

	_clan_list = UIScrollList.new()
	_clan_list.row_height = 48.0
	_clan_list.item_draw_callback = _draw_clan_item
	_clan_list.item_selected.connect(_on_clan_selected)
	add_child(_clan_list)

	_btn_ally = UIButton.new()
	_btn_ally.text = "Proposer une alliance"
	_btn_ally.accent_color = UITheme.ACCENT
	_btn_ally.pressed.connect(func(): _set_relation("ALLIE"))
	_btn_ally.visible = false
	add_child(_btn_ally)

	_btn_war = UIButton.new()
	_btn_war.text = "Declarer la guerre"
	_btn_war.accent_color = UITheme.DANGER
	_btn_war.pressed.connect(func(): _set_relation("ENNEMI"))
	_btn_war.visible = false
	add_child(_btn_war)

	_btn_neutral = UIButton.new()
	_btn_neutral.text = "Definir comme neutre"
	_btn_neutral.pressed.connect(func(): _set_relation("NEUTRE"))
	_btn_neutral.visible = false
	add_child(_btn_neutral)


func refresh(cm: ClanManager) -> void:
	_cm = cm
	_selected_clan_id = ""
	_clan_ids.clear()
	_btn_ally.visible = false
	_btn_war.visible = false
	_btn_neutral.visible = false

	if _cm == null or not _cm.has_clan():
		return

	_clan_list.items.clear()
	for clan_id in _cm.diplomacy:
		_clan_ids.append(clan_id)
		_clan_list.items.append(clan_id)
	_clan_list.selected_index = -1
	_clan_list.queue_redraw()
	queue_redraw()


func _draw_clan_item(ctrl: Control, _index: int, rect: Rect2, item: Variant) -> void:
	var font: Font = UITheme.get_font()
	var clan_id: String = item as String
	if _cm == null or not _cm.diplomacy.has(clan_id):
		return

	var info: Dictionary = _cm.diplomacy[clan_id]
	var cname: String = info.get("name", "?")
	var tag: String = info.get("tag", "?")
	var relation: String = info.get("relation", "NEUTRE")
	var rel_col: Color = RELATION_COLORS.get(relation, UITheme.TEXT_DIM)
	var rel_label: String = RELATION_LABELS.get(relation, relation)

	# Clan name and tag (bigger font)
	ctrl.draw_string(font, Vector2(rect.position.x + 16, rect.position.y + 18), "%s [%s]" % [cname, tag], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 32, UITheme.FONT_SIZE_BODY, UITheme.TEXT)

	# Status badge with colored background
	var badge_w: float = 80.0
	var badge_x: float = rect.position.x + 16
	var badge_y: float = rect.position.y + 26
	var badge_rect := Rect2(badge_x, badge_y, badge_w, 16)
	ctrl.draw_rect(badge_rect, Color(rel_col.r, rel_col.g, rel_col.b, 0.15))
	ctrl.draw_rect(badge_rect, Color(rel_col.r, rel_col.g, rel_col.b, 0.4), false, 1.0)

	# Status dot + label
	ctrl.draw_circle(Vector2(badge_x + 8, badge_y + 8), 3.0, rel_col)
	ctrl.draw_string(font, Vector2(badge_x + 16, badge_y + 12), rel_label, HORIZONTAL_ALIGNMENT_LEFT, badge_w - 20, UITheme.FONT_SIZE_BODY, rel_col)


func _on_clan_selected(index: int) -> void:
	if index < 0 or index >= _clan_ids.size():
		_selected_clan_id = ""
		_btn_ally.visible = false
		_btn_war.visible = false
		_btn_neutral.visible = false
		queue_redraw()
		return

	_selected_clan_id = _clan_ids[index]
	var can_diplo: bool = _cm.player_has_permission(ClanRank.PERM_DIPLOMACY) if _cm else false
	_btn_ally.visible = can_diplo
	_btn_war.visible = can_diplo
	_btn_neutral.visible = can_diplo
	queue_redraw()


func _set_relation(rel: String) -> void:
	if _cm and _selected_clan_id != "":
		_cm.set_diplomacy_relation(_selected_clan_id, rel)
		_clan_list.queue_redraw()
		queue_redraw()


func _process(_delta: float) -> void:
	if not visible:
		return

	var m: float = 12.0
	var rx: float = LEFT_W + GAP
	var rw: float = size.x - rx

	_clan_list.position = Vector2(0, 0)
	_clan_list.size = Vector2(LEFT_W, size.y)

	_btn_ally.position = Vector2(rx + m, 160)
	_btn_ally.size = Vector2(rw - m * 2, 32)
	_btn_war.position = Vector2(rx + m, 200)
	_btn_war.size = Vector2(rw - m * 2, 32)
	_btn_neutral.position = Vector2(rx + m, 240)
	_btn_neutral.size = Vector2(rw - m * 2, 32)


func _draw() -> void:
	if _cm == null or not _cm.has_clan():
		return

	var font: Font = UITheme.get_font()
	var m: float = 12.0
	var rx: float = LEFT_W + GAP
	var rw: float = size.x - rx

	# Left panel
	draw_panel_bg(Rect2(0, 0, LEFT_W, size.y))

	# Right panel
	draw_panel_bg(Rect2(rx, 0, rw, size.y))

	if _selected_clan_id != "" and _cm.diplomacy.has(_selected_clan_id):
		var info: Dictionary = _cm.diplomacy[_selected_clan_id]
		var cname: String = info.get("name", "?")
		var tag: String = info.get("tag", "?")
		var relation: String = info.get("relation", "NEUTRE")
		var rel_col: Color = RELATION_COLORS.get(relation, UITheme.TEXT_DIM)
		var rel_label: String = RELATION_LABELS.get(relation, relation)

		# Header bar
		draw_rect(Rect2(rx, 0, rw, 36), Color(UITheme.PRIMARY.r, UITheme.PRIMARY.g, UITheme.PRIMARY.b, 0.06))
		draw_rect(Rect2(rx, 0, 3, 36), rel_col)
		draw_string(font, Vector2(rx + m + 6, 24), "%s [%s]" % [cname.to_upper(), tag], HORIZONTAL_ALIGNMENT_LEFT, rw - m * 2, UITheme.FONT_SIZE_HEADER, UITheme.TEXT_HEADER)
		draw_line(Vector2(rx, 36), Vector2(rx + rw, 36), UITheme.BORDER, 1.0)

		# Relation details
		var y: float = 50.0

		# Big relation status
		draw_string(font, Vector2(rx + m, y + UITheme.FONT_SIZE_BODY), "Relation actuelle:", HORIZONTAL_ALIGNMENT_LEFT, rw * 0.5, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)
		y += 24

		# Big colored status bar
		var status_rect := Rect2(rx + m, y, rw - m * 2, 28)
		draw_rect(status_rect, Color(rel_col.r, rel_col.g, rel_col.b, 0.1))
		draw_rect(status_rect, Color(rel_col.r, rel_col.g, rel_col.b, 0.4), false, 1.0)
		draw_rect(Rect2(rx + m, y, 4, 28), rel_col)
		draw_circle(Vector2(rx + m + 20, y + 14), 5.0, rel_col)
		draw_string(font, Vector2(rx + m + 32, y + 19), rel_label, HORIZONTAL_ALIGNMENT_LEFT, rw - 50, UITheme.FONT_SIZE_HEADER, rel_col)
		y += 40

		# Time since
		var since: int = info.get("since", 0)
		var now := int(Time.get_unix_time_from_system())
		var days := int((now - since) / 86400.0)
		draw_string(font, Vector2(rx + m, y + UITheme.FONT_SIZE_BODY), "Depuis:", HORIZONTAL_ALIGNMENT_LEFT, rw * 0.4, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)
		draw_string(font, Vector2(rx + m, y + UITheme.FONT_SIZE_BODY), "%d jours" % days, HORIZONTAL_ALIGNMENT_RIGHT, rw - m * 2, UITheme.FONT_SIZE_BODY, UITheme.LABEL_VALUE)
		y += 28

		# Actions header
		draw_line(Vector2(rx + m, y), Vector2(rx + rw - m, y), UITheme.BORDER, 1.0)
		y += 8
		draw_rect(Rect2(rx + m, y + 2, 3, UITheme.FONT_SIZE_HEADER + 2), UITheme.PRIMARY)
		draw_string(font, Vector2(rx + m + 10, y + UITheme.FONT_SIZE_HEADER + 1), "ACTIONS DIPLOMATIQUES", HORIZONTAL_ALIGNMENT_LEFT, rw - 20, UITheme.FONT_SIZE_HEADER, UITheme.TEXT_HEADER)
	else:
		draw_string(font, Vector2(rx, size.y * 0.4), "Selectionnez un clan", HORIZONTAL_ALIGNMENT_CENTER, rw, UITheme.FONT_SIZE_HEADER, UITheme.TEXT_DIM)
		draw_string(font, Vector2(rx, size.y * 0.4 + 24), "pour gerer les relations diplomatiques", HORIZONTAL_ALIGNMENT_CENTER, rw, UITheme.FONT_SIZE_BODY, UITheme.TEXT_DIM)
