class_name NotifNavigation
extends RefCounted

# =============================================================================
# Navigation Notifications — Routes, destinations
# =============================================================================

var _svc: NotificationService = null


func _init(svc: NotificationService) -> void:
	_svc = svc


func route_started(sys_name: String, jumps: int) -> void:
	_svc.toast("ROUTE VERS %s — %d saut%s" % [sys_name, jumps, "s" if jumps > 1 else ""])


func route_completed() -> void:
	_svc.toast("DESTINATION ATTEINTE")


func route_not_found() -> void:
	_svc.toast("AUCUNE ROUTE TROUVEE")


func route_cancelled() -> void:
	_svc.toast("ROUTE ANNULEE")


func already_here() -> void:
	_svc.toast("DEJA SUR PLACE")
