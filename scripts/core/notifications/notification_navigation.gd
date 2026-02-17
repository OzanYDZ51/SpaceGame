class_name NotifNavigation
extends RefCounted

# =============================================================================
# Navigation Notifications — Routes, destinations
# =============================================================================

var _svc: NotificationService = null


func _init(svc: NotificationService) -> void:
	_svc = svc


func route_started(sys_name: String, jumps: int) -> void:
	_svc.toast(Locale.t("notif.route_to") % [sys_name, jumps, "s" if jumps > 1 else ""])


func route_completed() -> void:
	_svc.toast(Locale.t("notif.destination_reached"))


func route_not_found() -> void:
	_svc.toast(Locale.t("notif.no_route"))


func route_cancelled() -> void:
	_svc.toast(Locale.t("notif.route_cancelled"))


func already_here() -> void:
	_svc.toast(Locale.t("notif.already_there"))
