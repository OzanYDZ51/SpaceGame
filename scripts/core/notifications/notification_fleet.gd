class_name NotifFleet
extends RefCounted

# =============================================================================
# Fleet Notifications — Deploiement, rappel, destruction
# =============================================================================

var _svc: NotificationService = null


func _init(svc: NotificationService) -> void:
	_svc = svc


func deployed(ship_name: String) -> void:
	_svc.toast("DEPLOIEMENT: %s" % ship_name, UIToast.ToastType.SUCCESS)


func recalled(ship_name: String) -> void:
	_svc.toast("RAPPEL: %s" % ship_name)


func lost(ship_name: String) -> void:
	_svc.toast("VAISSEAU PERDU: %s" % ship_name, UIToast.ToastType.WARNING)


func deploy_failed(reason: String) -> void:
	_svc.toast(reason, UIToast.ToastType.WARNING)


func destroyed() -> void:
	_svc.toast("VAISSEAU DETRUIT", UIToast.ToastType.WARNING)
