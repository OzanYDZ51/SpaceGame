class_name NotificationService
extends Node

# =============================================================================
# Notification Service — Central dispatch hub for all game notifications.
# Child of GameManager. Categories are RefCounted sub-modules.
# =============================================================================

var commerce: NotifCommerce = null
var fleet: NotifFleet = null
var squadron: NotifSquadron = null
var nav: NotifNavigation = null
var general: NotifGeneral = null

var _toast_manager: UIToastManager = null


func initialize(toast_manager: UIToastManager) -> void:
	_toast_manager = toast_manager
	commerce = NotifCommerce.new(self)
	fleet = NotifFleet.new(self)
	squadron = NotifSquadron.new(self)
	nav = NotifNavigation.new(self)
	general = NotifGeneral.new(self)


func toast(msg: String, type: int = UIToast.ToastType.INFO, lifetime: float = 0.0) -> void:
	if _toast_manager == null:
		return
	if lifetime > 0.0:
		_toast_manager.show_toast(msg, type, lifetime)
	else:
		_toast_manager.show_toast(msg, type)
