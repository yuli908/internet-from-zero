class_name CliArgs
extends RefCounted

## 解析命令行参数，支持 `--key=value` 与 `--flag`。
## 同时读取引擎参数与 `--` 之后的用户参数。

static func _all() -> PackedStringArray:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	return args

static func has_flag(name: String) -> bool:
	for a in _all():
		if a == "--" + name or a.begins_with("--" + name + "="):
			return true
	return false

static func value(name: String, fallback: String = "") -> String:
	for a in _all():
		if a.begins_with("--" + name + "="):
			return a.substr(("--" + name + "=").length())
	return fallback
