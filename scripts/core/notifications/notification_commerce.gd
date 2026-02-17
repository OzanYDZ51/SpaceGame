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
		_svc.toast(Locale.t("notif.bought_credits") % [item_name, PlayerEconomy.format_credits(total)], UIToast.ToastType.SUCCESS)
	else:
		_svc.toast(Locale.t("notif.bought") % item_name, UIToast.ToastType.SUCCESS)


func sold(item_name: String, total: int = 0) -> void:
	if total > 0:
		_svc.toast(Locale.t("notif.sold_credits") % [item_name, PlayerEconomy.format_credits(total)], UIToast.ToastType.SUCCESS)
	else:
		_svc.toast(Locale.t("notif.sold") % item_name, UIToast.ToastType.SUCCESS)


func sold_qty(item_name: String, qty: int, total: int) -> void:
	_svc.toast(Locale.t("notif.sold_bulk") % [item_name, qty, PlayerEconomy.format_credits(total)], UIToast.ToastType.SUCCESS)


func purchase_failed(reason: String) -> void:
	_svc.toast(reason, UIToast.ToastType.ERROR)
