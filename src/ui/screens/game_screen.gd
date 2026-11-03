class_name GameScreen
extends Control

## 所有页面基类。Main 负责实例化与切换。

var main: Control

func setup(main_ref: Control) -> void:
	main = main_ref
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func on_show() -> void:
	pass

func _notification(what: int) -> void:
	## 子类 `_build()` 通常只 add_child 一个根容器；这里统一撑满，避免内容塌成一条。
	if what == NOTIFICATION_READY and get_child_count() > 0:
		var root := get_child(0)
		if root is Control:
			(root as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
