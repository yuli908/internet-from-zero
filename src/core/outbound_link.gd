extends RefCounted

## F1 出网判据（19 §2.10）。
##
## 真值只来自 `src/sim/world_port.gd::deliver` 的真实 loopback 收发：提交的行必须同时给
## 「发送侧写出的字节」(`sent_hex`) 与「本机终端读到的字节」(`local_bytes`)，且两者逐字节
## 相同。只打印两行文本、或两处读到的不是同一份流，都判红。
##
## 首错顺序（跟课件一致）：未接线(3) → 端口/拓扑(7) → 字节被改写/顺序颠倒(10)
## → 时延越限(9) → 覆盖不全(13)。语义错先于覆盖，避免「少交一行」把改写盖过去。

const Sim = preload("res://src/sim/world_port.gd")
const E_UNCONNECTED := 3
const E_TABLE_CELL := 7
const E_DELAY_MISMATCH := 9
const E_OUTPUT_MISMATCH := 10
const E_COVERAGE := 13

static func validate_gate(got: Dictionary, c: Dictionary) -> Dictionary:
	var live: Dictionary = Sim.deliver(c.get("outbound", {}))
	if not bool(live.get("ok", false)):
		return _bad(int(live.get("code", E_UNCONNECTED)), {"bridge": "world_port"},
			"真实 loopback 可收发", "missing", str(live.get("detail", "")))

	var rows_v: Variant = got.get("rows", null)
	var rows: Array = rows_v if (rows_v is Array) else []
	if rows.is_empty():
		return _bad(E_UNCONNECTED, "rows", "至少 1 行真实收发", "missing",
			"出网证据未提交：没有 rows")

	var live_rows: Array = live["rows"]
	var lm: Dictionary = live["meta"]
	var meta_v: Variant = got.get("meta", {})
	var meta: Dictionary = meta_v if (meta_v is Dictionary) else {}

	# 1) 拓扑与真实端口：提交必须与本次真实 listen 到的端口一致（数据写 7777，以本次捕获为准）。
	if str(meta.get("transport", "")) != "tcp-loopback" or str(meta.get("host", "")) != str(lm["host"]):
		return _bad(E_TABLE_CELL, {"meta": "transport/host"},
			"%s@%s" % [str(lm["transport"]), str(lm["host"])],
			"%s@%s" % [str(meta.get("transport", "")), str(meta.get("host", ""))],
			"网桥形态不符：应为 tcp-loopback@%s" % str(lm["host"]))
	if int(meta.get("port", -1)) != int(lm["port"]):
		return _bad(E_TABLE_CELL, {"meta": "port"}, int(lm["port"]), meta.get("port", null),
			"端口不符：本次真实监听端口是 %d，交 %s" % [int(lm["port"]), str(meta.get("port", null))])

	# 2) 逐行：顺序 + 同一份字节（两个读取点必须逐字节一致，且与真实捕获一致）。
	for i in range(mini(rows.size(), live_rows.size())):
		if not (rows[i] is Dictionary):
			return _bad(E_TABLE_CELL, {"row": i + 1}, "每行为对象", rows[i],
				"第 %d 行不是对象" % (i + 1))
		var r: Dictionary = rows[i]
		var lr: Dictionary = live_rows[i]
		if str(r.get("run", "")) != str(lr["run"]):
			return _bad(E_OUTPUT_MISMATCH, {"row": i + 1, "run": r.get("run", null)},
				str(lr["run"]), r.get("run", null),
				"输出顺序颠倒：第 %d 行应为 run=%s，交 %s"
					% [i + 1, str(lr["run"]), str(r.get("run", null))])
		if str(r.get("sent_hex", "")) != str(lr["sent_hex"]):
			return _bad(E_OUTPUT_MISMATCH, {"row": i + 1, "sent_hex": r.get("sent_hex", null)},
				str(lr["sent_hex"]), r.get("sent_hex", null),
				"发送侧字节与真实捕获不符：交 %s，真 %s"
					% [str(r.get("sent_hex", null)), str(lr["sent_hex"])])
		if str(r.get("local_bytes", "")) != str(lr["local_bytes"]):
			return _bad(E_OUTPUT_MISMATCH, {"row": i + 1, "local_bytes": r.get("local_bytes", null)},
				str(lr["local_bytes"]), r.get("local_bytes", null),
				"本机读到的字节被改写：交 %s（sum16=0x%04x），真实捕获 %s（sum16=0x%04x）"
					% [str(r.get("local_bytes", null)), _sum16(str(r.get("local_bytes", ""))),
						str(lr["local_bytes"]), _sum16(str(lr["local_bytes"]))])
		if str(r.get("sent_hex", "")) != str(r.get("local_bytes", "")):
			return _bad(E_OUTPUT_MISMATCH, {"row": i + 1}, "两个读取点同一份字节",
				{"sent_hex": r.get("sent_hex", null), "local_bytes": r.get("local_bytes", null)},
				"两个读取点不是同一份字节：发送 %s ≠ 收 %s"
					% [str(r.get("sent_hex", null)), str(r.get("local_bytes", null))])

	# 3) 两次输出要随输入变：真实捕获里也不能两遍同字节。
	if live_rows.size() >= 2 and str(live_rows[0]["sent_hex"]) == str(live_rows[1]["sent_hex"]):
		return _bad(E_OUTPUT_MISMATCH, {"runs": live_rows.size()}, "两遍字节不同",
			str(live_rows[0]["sent_hex"]), "两遍输出同字节：说明没有跟着输入走")

	# 4) 时延（真值来自真实往返，提交不得超上限）。
	var delay_cfg: Dictionary = c.get("delay", {})
	var delay_key := str(delay_cfg.get("key", "deliver_us"))
	var delay_max := int(delay_cfg.get("max", 50000))
	for i in range(mini(rows.size(), live_rows.size())):
		var dv: int = int((rows[i] as Dictionary).get(delay_key, -1))
		if dv <= 0 or dv > delay_max:
			return _bad(E_DELAY_MISMATCH, {"row": i + 1, delay_key: dv},
				"1..%d us" % delay_max, dv,
				"第 %d 行 %s=%d，超出 1..%d us" % [i + 1, delay_key, dv, delay_max])

	# 5) 覆盖：行数必须与本次 runs 一致（多/少都判 13，不静默截断）。
	if rows.size() != live_rows.size():
		return _bad(E_COVERAGE, {"rows": rows.size()}, live_rows.size(), rows.size(),
			"行数不符：交 %d 行，本次真实收发 %d 行" % [rows.size(), live_rows.size()])

	return {
		"ok": true,
		"code": E_TABLE_CELL,
		"actual": {
			"rows": rows,
			"meta": meta,
			"read_points": ["sent_hex", "local_bytes"],
			"transport": str(lm["transport"]),
			"port": int(lm["port"]),
		},
		"detail": str(live["detail"]),
	}

static func _sum16(hex: String) -> int:
	var s := 0
	for b in hex.hex_decode():
		s = (s + int(b)) % 65536
	return s

static func _bad(code: int, input: Variant, expected: Variant, actual: Variant,
		detail: String) -> Dictionary:
	return {"ok": false, "code": code, "input": input,
		"expected": expected, "actual": actual, "detail": detail}
