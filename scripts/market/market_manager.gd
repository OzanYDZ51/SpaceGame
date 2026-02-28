class_name MarketManager
extends Node

# =============================================================================
# MarketManager — Client-side manager for HDV (Hotel des Ventes)
# Handles API calls, caching, and signal dispatch.
# =============================================================================

signal listings_loaded(listings: Array, total: int)
signal listing_created(listing: MarketListing)
signal listing_bought(listing: MarketListing)
signal listing_cancelled(listing_id: int)
signal my_listings_loaded(listings: Array)
signal market_error(message: String)

const CACHE_TTL: float = 15.0

var _cache: Dictionary = {}  # key -> { "data": ..., "time": float }
var _loading: bool = false


func search_listings(category: String = "", search_text: String = "", sort_by: String = "newest",
		min_price: int = -1, max_price: int = -1, system_id: int = -1,
		limit: int = 50, offset: int = 0) -> void:
	if _loading:
		return
	_loading = true

	var path: String = "/api/v1/market/listings?sort_by=%s&limit=%d&offset=%d" % [sort_by, limit, offset]
	if category != "" and category != "all":
		path += "&category=" + category
	if search_text != "":
		path += "&search=" + search_text.uri_encode()
	if min_price >= 0:
		path += "&min_price=%d" % min_price
	if max_price >= 0:
		path += "&max_price=%d" % max_price
	if system_id >= 0:
		path += "&system_id=%d" % system_id

	# Check cache
	var cache_key: String = path
	if _cache.has(cache_key):
		var entry: Dictionary = _cache[cache_key]
		if Time.get_unix_time_from_system() - entry["time"] < CACHE_TTL:
			_loading = false
			listings_loaded.emit(entry["listings"], entry["total"])
			return

	var result: Dictionary = await ApiClient.get_async(path)
	_loading = false

	if result.get("_status_code", 0) != 200:
		market_error.emit(result.get("error", "search_failed"))
		return

	var raw_listings: Array = result.get("listings", [])
	var total: int = int(result.get("total", 0))
	var listings: Array[MarketListing] = []
	for d in raw_listings:
		listings.append(MarketListing.from_dict(d))

	_cache[cache_key] = {"listings": listings, "total": total, "time": Time.get_unix_time_from_system()}
	listings_loaded.emit(listings, total)


func create_listing(item_category: String, item_id: String, item_name: String,
		quantity: int, unit_price: int, duration_hours: int,
		system_id: int, station_id: String, station_name: String) -> void:
	if _loading:
		return
	_loading = true

	var body: Dictionary = {
		"item_category": item_category,
		"item_id": item_id,
		"item_name": item_name,
		"quantity": quantity,
		"unit_price": unit_price,
		"duration_hours": duration_hours,
		"system_id": system_id,
		"station_id": station_id,
		"station_name": station_name,
	}

	var result: Dictionary = await ApiClient.post_async("/api/v1/market/listings", body)
	_loading = false

	if result.get("_status_code", 0) != 201:
		market_error.emit(result.get("error", "create_failed"))
		return

	_invalidate_cache()
	var listing: MarketListing = MarketListing.from_dict(result)
	listing_created.emit(listing)


func buy_listing(listing_id: int) -> void:
	if _loading:
		return
	_loading = true

	var result: Dictionary = await ApiClient.post_async("/api/v1/market/listings/%d/buy" % listing_id)
	_loading = false

	if result.get("_status_code", 0) != 200:
		market_error.emit(result.get("error", "buy_failed"))
		return

	_invalidate_cache()
	var listing: MarketListing = MarketListing.from_dict(result)
	listing_bought.emit(listing)


func cancel_listing(listing_id: int) -> void:
	if _loading:
		return
	_loading = true

	var result: Dictionary = await ApiClient.delete_async("/api/v1/market/listings/%d" % listing_id)
	_loading = false

	if result.get("_status_code", 0) != 200:
		market_error.emit(result.get("error", "cancel_failed"))
		return

	_invalidate_cache()
	listing_cancelled.emit(listing_id)


func get_my_listings(status: String = "all") -> void:
	if _loading:
		return
	_loading = true

	var path: String = "/api/v1/market/my-listings"
	if status != "all":
		path += "?status=" + status

	var result: Dictionary = await ApiClient.get_async(path)
	_loading = false

	if result.get("_status_code", 0) != 200:
		market_error.emit(result.get("error", "fetch_failed"))
		return

	var raw: Array = result.get("listings", [])
	var listings: Array[MarketListing] = []
	for d in raw:
		listings.append(MarketListing.from_dict(d))
	my_listings_loaded.emit(listings)


func _invalidate_cache() -> void:
	_cache.clear()
