class_name SaveCodec
extends RefCounted

## 存档编解码：版本号 + 校验和 + 迁移链。格式为信封包着 payload 字符串。
## 信封：{"fmt","version","algo","checksum","payload"}，payload 是 JSON 字符串。

const FORMAT_VERSION := 2
const ENVELOPE_FMT := "internet-from-zero.save"
const ALGO := "sha256"

static func encode(state: PlayerState) -> String:
	return encode_payload(state.to_dict())

static func encode_payload(payload: Dictionary, version: int = FORMAT_VERSION) -> String:
	var p := payload.duplicate(true)
	p["version"] = version
	var payload_str := JSON.stringify(p, "", true)
	var env := {
		"fmt": ENVELOPE_FMT,
		"version": version,
		"algo": ALGO,
		"checksum": checksum(payload_str),
		"payload": payload_str,
	}
	return JSON.stringify(env, "  ", true) + "\n"

static func checksum(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()

static func decode(text: String) -> Dictionary:
	if text.strip_edges().is_empty():
		return _fail("存档为空")
	var env_parser := JSON.new()
	if env_parser.parse(text) != OK:
		return _fail("存档不是合法 JSON：%s（第 %d 行）" % [env_parser.get_error_message(), env_parser.get_error_line()])
	var env: Variant = env_parser.data
	if not (env is Dictionary):
		return _fail("存档信封结构错误")
	if str(env.get("fmt", "")) != ENVELOPE_FMT:
		return _fail("不是本游戏的存档文件（fmt 不匹配）")
	var payload_str := str(env.get("payload", ""))
	if payload_str.is_empty():
		return _fail("存档缺少 payload")
	var expect := str(env.get("checksum", ""))
	if expect.is_empty():
		return _fail("存档缺少校验和")
	var actual := checksum(payload_str)
	if actual != expect:
		return _fail("校验和不匹配（存档可能损坏或被修改）")
	var p_parser := JSON.new()
	if p_parser.parse(payload_str) != OK:
		return _fail("payload 不是合法 JSON：%s" % p_parser.get_error_message())
	var payload: Variant = p_parser.data
	if not (payload is Dictionary):
		return _fail("payload 结构错误")
	var version := int(payload.get("version", 1))
	if version > FORMAT_VERSION:
		return _fail("存档版本 v%d 高于当前支持的 v%d（请升级游戏）" % [version, FORMAT_VERSION])
	var migrated_from := 0
	if version < FORMAT_VERSION:
		migrated_from = version
		var res := migrate(payload)
		if not bool(res.ok):
			return res
		payload = res.payload
	return {
		"ok": true, "error": "", "payload": payload,
		"version": FORMAT_VERSION, "migrated_from": migrated_from,
	}

static func migrate(payload: Dictionary) -> Dictionary:
	var p := payload.duplicate(true)
	var from_v := int(p.get("version", 1))
	var v := from_v
	var guard := 0
	while v < FORMAT_VERSION:
		guard += 1
		if guard > 16:
			return _fail("迁移链过长，已中止")
		match v:
			1:
				p = _migrate_v1_to_v2(p)
			_:
				return _fail("没有 v%d 的迁移器" % v)
		var nv := int(p.get("version", 0))
		if nv <= v:
			return _fail("迁移器没有推进版本号（v%d）" % v)
		v = nv
	return {"ok": true, "error": "", "payload": p, "from": from_v}

static func _migrate_v1_to_v2(p: Dictionary) -> Dictionary:
	var out := {}
	var src: Variant = p.get("player", {})
	if src is Dictionary:
		out = src.duplicate(true)
	out["version"] = 2
	if not out.has("inventory"):
		out["inventory"] = {}
	if not out.has("knowledge"):
		out["knowledge"] = {}
	if not out.has("objectives"):
		out["objectives"] = {}
	if not out.has("labs_completed"):
		out["labs_completed"] = {}
	if not out.has("flags"):
		out["flags"] = {}
	if not out.has("tutorial_done"):
		out["tutorial_done"] = {}
	if not out.has("stats"):
		out["stats"] = {"saves": 0, "play_seconds": 0.0, "ticks": 0}
	if not out.has("rng"):
		out["rng"] = {"seed": 1, "state": 0}
	if not out.has("chapter_id"):
		out["chapter_id"] = "ch01"
	if not out.has("scrap"):
		out["scrap"] = 0
	if not out.has("xp"):
		out["xp"] = 0
	return out

static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "payload": {}, "version": 0, "migrated_from": 0}
