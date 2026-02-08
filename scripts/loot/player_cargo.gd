class_name PlayerCargo
extends RefCounted

# =============================================================================
# Player Cargo - Inventory of collected loot items
# Same pattern as PlayerInventory (RefCounted, signal-based).
# =============================================================================

signal cargo_changed()

var items: Array[Dictionary] = []    # { "name", "type", "quantity", "icon_color" }
var max_capacity: int = 50           # future use


func add_item(item: Dictionary) -> void:
	# Stack with existing same-name item
	for existing in items:
		if existing["name"] == item["name"]:
			existing["quantity"] += item.get("quantity", 1)
			cargo_changed.emit()
			return
	# New item
	items.append(item.duplicate())
	cargo_changed.emit()


func add_items(new_items: Array[Dictionary]) -> void:
	for item in new_items:
		add_item(item)


func remove_item(item_name: String, qty: int = 1) -> bool:
	for i in items.size():
		if items[i]["name"] == item_name:
			items[i]["quantity"] -= qty
			if items[i]["quantity"] <= 0:
				items.remove_at(i)
			cargo_changed.emit()
			return true
	return false


func get_all() -> Array[Dictionary]:
	return items


func get_total_count() -> int:
	var total: int = 0
	for item in items:
		total += item.get("quantity", 1)
	return total


func clear() -> void:
	items.clear()
	cargo_changed.emit()


func serialize() -> Array:
	var result: Array = []
	for item in items:
		result.append({
			"item_name": item.get("name", ""),
			"item_type": item.get("type", ""),
			"quantity": item.get("quantity", 1),
			"icon_color": item.get("icon_color", ""),
		})
	return result
