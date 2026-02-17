class_name NotifSquadron
extends RefCounted

# =============================================================================
# Squadron Notifications — Escadrons: creation, formation, renommage
# =============================================================================

var _svc: NotificationService = null


func _init(svc: NotificationService) -> void:
	_svc = svc


func created(squadron_name: String) -> void:
	_svc.toast(Locale.t("notif.squadron_created") % squadron_name, UIToast.ToastType.SUCCESS)


func disbanded() -> void:
	_svc.toast(Locale.t("notif.squadron_dissolved"))


func renamed(squadron_name: String) -> void:
	_svc.toast(Locale.t("notif.squadron_renamed") % squadron_name)


func formation(display_name: String) -> void:
	_svc.toast(Locale.t("notif.squadron_formation") % display_name)


func new_leader(ship_name: String) -> void:
	_svc.toast(Locale.t("notif.squadron_new_leader") % ship_name, UIToast.ToastType.SUCCESS)
