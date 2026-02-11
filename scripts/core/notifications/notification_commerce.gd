class_name NotifCommerce
extends RefCounted

# =============================================================================
# Commerce Notifications — Achats, ventes, credits
# =============================================================================

var _svc: NotificationService = null


func _init(svc: NotificationService) -> void:
	_svc = svc


func bought(item_name: String, total: int = 0) -> void:
	if total > 0:
		_svc.toast("%s acheté! -%s CR" % [item_name, PlayerEconomy.format_credits(total)], UIToast.ToastType.SUCCESS)
	else:
		_svc.toast("%s acheté!" % item_name, UIToast.ToastType.SUCCESS)


func sold(item_name: String, total: int = 0) -> void:
	if total > 0:
		_svc.toast("%s vendu! +%s CR" % [item_name, PlayerEconomy.format_credits(total)], UIToast.ToastType.SUCCESS)
	else:
		_svc.toast("%s vendu!" % item_name, UIToast.ToastType.SUCCESS)


func sold_qty(item_name: String, qty: int, total: int) -> void:
	_svc.toast("%s x%d vendu! +%s CR" % [item_name, qty, PlayerEconomy.format_credits(total)], UIToast.ToastType.SUCCESS)


func purchase_failed(reason: String) -> void:
	_svc.toast(reason, UIToast.ToastType.ERROR)
