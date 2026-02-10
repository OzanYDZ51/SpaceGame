class_name NotifSquadron
extends RefCounted

# =============================================================================
# Squadron Notifications — Escadrons: creation, formation, renommage
# =============================================================================

var _svc: NotificationService = null


func _init(svc: NotificationService) -> void:
	_svc = svc


func created(squadron_name: String) -> void:
	_svc.toast("ESCADRON CREE: %s" % squadron_name, UIToast.ToastType.SUCCESS)


func disbanded() -> void:
	_svc.toast("ESCADRON DISSOUS")


func renamed(squadron_name: String) -> void:
	_svc.toast("ESCADRON RENOMME: %s" % squadron_name)


func formation(display_name: String) -> void:
	_svc.toast("FORMATION: %s" % display_name)


func new_leader(ship_name: String) -> void:
	_svc.toast("NOUVEAU CHEF: %s" % ship_name, UIToast.ToastType.SUCCESS)
