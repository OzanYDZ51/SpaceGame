class_name NotifGeneral
extends RefCounted

# =============================================================================
# General Notifications — Reparation, cargo, docking, bug report
# =============================================================================

var _svc: NotificationService = null


func _init(svc: NotificationService) -> void:
	_svc = svc


func repair(recovered_count: int = 0) -> void:
	if recovered_count > 0:
		_svc.toast(Locale.t("notif.fleet_repaired") % recovered_count, UIToast.ToastType.SUCCESS)
	else:
		_svc.toast(Locale.t("notif.ship_repaired"), UIToast.ToastType.SUCCESS)


func cargo_full(lost_count: int) -> void:
	_svc.toast(Locale.t("notif.cargo_full") % lost_count, UIToast.ToastType.WARNING)


func service_unlocked(label: String) -> void:
	_svc.toast(Locale.t("notif.service_unlocked") % label, UIToast.ToastType.SUCCESS)


func insufficient_credits(required: String) -> void:
	_svc.toast(Locale.t("notif.insufficient_credits") % required, UIToast.ToastType.WARNING)


func bug_report_sent() -> void:
	_svc.toast(Locale.t("notif.bug_report_sent"), UIToast.ToastType.SUCCESS)


func bug_report_error(code: int) -> void:
	_svc.toast(Locale.t("notif.bug_report_error") % code, UIToast.ToastType.ERROR)


func bug_report_validation(msg: String) -> void:
	_svc.toast(msg, UIToast.ToastType.ERROR)


func undock_blocked() -> void:
	_svc.toast(Locale.t("notif.undock_blocked"), UIToast.ToastType.WARNING, 3.0)
