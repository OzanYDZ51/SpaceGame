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
		_svc.toast("FLOTTE RÉPARÉE — %d vaisseau(x) récupéré(s)" % recovered_count, UIToast.ToastType.SUCCESS)
	else:
		_svc.toast("VAISSEAU RÉPARÉ", UIToast.ToastType.SUCCESS)


func cargo_full(lost_count: int) -> void:
	_svc.toast("SOUTE PLEINE — %d objet(s) perdu(s)" % lost_count, UIToast.ToastType.WARNING)


func service_unlocked(label: String) -> void:
	_svc.toast("%s DÉBLOQUÉ" % label, UIToast.ToastType.SUCCESS)


func insufficient_credits(required: String) -> void:
	_svc.toast("CRÉDITS INSUFFISANTS — %s CR requis" % required, UIToast.ToastType.WARNING)


func bug_report_sent() -> void:
	_svc.toast("Bug report envoye!", UIToast.ToastType.SUCCESS)


func bug_report_error(code: int) -> void:
	_svc.toast("Erreur d'envoi (code %d)" % code, UIToast.ToastType.ERROR)


func bug_report_validation(msg: String) -> void:
	_svc.toast(msg, UIToast.ToastType.ERROR)
