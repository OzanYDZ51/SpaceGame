class_name MarketListing
extends RefCounted

# =============================================================================
# MarketListing — Data class for a single HDV listing
# =============================================================================

var id: int = 0
var seller_id: String = ""
var seller_name: String = ""
var system_id: int = 0
var station_id: String = ""
var station_name: String = ""
var item_category: String = ""
var item_id: String = ""
var item_name: String = ""
var quantity: int = 1
var unit_price: int = 0
var listing_fee: int = 0
var status: String = "active"
var created_at: String = ""
var expires_at: String = ""
var sold_to_name: String = ""


static func from_dict(d: Dictionary) -> MarketListing:
	var l := MarketListing.new()
	l.id = int(d.get("id", 0))
	l.seller_id = str(d.get("seller_id", ""))
	l.seller_name = str(d.get("seller_name", ""))
	l.system_id = int(d.get("system_id", 0))
	l.station_id = str(d.get("station_id", ""))
	l.station_name = str(d.get("station_name", ""))
	l.item_category = str(d.get("item_category", ""))
	l.item_id = str(d.get("item_id", ""))
	l.item_name = str(d.get("item_name", ""))
	l.quantity = int(d.get("quantity", 1))
	l.unit_price = int(d.get("unit_price", 0))
	l.listing_fee = int(d.get("listing_fee", 0))
	l.status = str(d.get("status", "active"))
	l.created_at = str(d.get("created_at", ""))
	l.expires_at = str(d.get("expires_at", ""))
	l.sold_to_name = str(d.get("sold_to_name", ""))
	return l


func get_total_price() -> int:
	return unit_price * quantity


func is_in_current_station() -> bool:
	if GameManager.current_state != Constants.GameState.DOCKED:
		return false
	var fleet = GameManager.player_fleet
	if fleet == null:
		return false
	var active_fs = fleet.get_active()
	if active_fs == null:
		return false
	return active_fs.docked_station_id == station_id and active_fs.docked_system_id == system_id
