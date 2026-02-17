class_name NotifFleet
extends RefCounted

# =============================================================================
# Fleet Notifications — Deploiement, rappel, destruction
# =============================================================================

var _svc: NotificationService = null


func _init(svc: NotificationService) -> void:
	_svc = svc


func deployed(ship_name: String) -> void:
	_svc.toast(Locale.t("notif.fleet_deploy") % ship_name, UIToast.ToastType.SUCCESS)


func recalled(ship_name: String) -> void:
	_svc.toast(Locale.t("notif.fleet_recall") % ship_name)


func lost(ship_name: String) -> void:
	_svc.toast(Locale.t("notif.fleet_lost") % ship_name, UIToast.ToastType.WARNING)


func deploy_failed(reason: String) -> void:
	_svc.toast(reason, UIToast.ToastType.WARNING)


func earned(ship_name: String, credits: int) -> void:
	_svc.toast(Locale.t("notif.fleet_sold") % [ship_name, PlayerEconomy.format_credits(credits)], UIToast.ToastType.SUCCESS)


func destroyed() -> void:
	_svc.toast(Locale.t("notif.ship_destroyed"), UIToast.ToastType.WARNING)
