class_name PlayerCargo
extends RefCounted

# =============================================================================
# Player Cargo - Inventory of collected loot items
# Same pattern as PlayerInventory (RefCounted, signal-based).
# =============================================================================

signal cargo_changed()

var items: Array[Dictionary] = []    # { "name", "type", "quantity", "icon_color" }
var capacity: int = 50


func get_total_count() -> int:
	var total: int = 0
	for item in items:
		total += item.get("quantity", 1)
	return total


func get_remaining_capacity() -> int:
	return maxi(capacity - get_total_count(), 0)


func can_add(qty: int = 1) -> bool:
	return get_total_count() + qty <= capacity


func add_item(item: Dictionary) -> bool:
	var qty: int = item.get("quantity", 1)
	if not can_add(qty):
		return false
	# Stack with existing same-name item
	for existing in items:
		if existing["name"] == item["name"]:
			existing["quantity"] += qty
			cargo_changed.emit()
			return true
	# New item
	items.append(item.duplicate())
	cargo_changed.emit()
	return true


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
