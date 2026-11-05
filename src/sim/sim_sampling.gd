class_name SimSampling
extends RefCounted

## 19.3 采样链路仿真（设备侧导出，提案 19 §2.9）。
##
## 生产：`trace(cfg)` 按 cfg 描述的链路真正跑一遍——采样 → 收帧 → 量化 → 应用 → 落盘，
## 逐段导出原始字节/码值。cfg 只描述物理参数与链路拓扑（量程、位数、每段 op/ms），
## 不写任何期望值；判据侧 `src/core/sampling_link.gd` 拿这里的输出逐段比对。
## 消费：`tests/test_ch19.gd`（T19.3-1 好答案与负例）、UI 链路页（逐段显示 raw/code）。
##
## 段数上限 32：当前真实最长链 5 段（ch19 sensor_loop），余量 6.4×；
## 超限直接判红（code=7），不静默截断——截断会把「少一段」伪装成合法链。
## 扩容规则见 specs/m5/failure_contract.md §13：确需 >32 段时改本常量，同步改文档与
## 满规模探针，不在数据里逐条放行。

const MAX_STAGES := 32
const E_TABLE_CELL := 7

static func trace(cfg: Dictionary) -> Dictionary:
	var stages_cfg: Array = cfg.get("stages", [])
	if stages_cfg.is_empty():
		return _fail("sampling.stages 为空：链路没有可跑的段")
	if stages_cfg.size() > MAX_STAGES:
		return _fail("段数 %d 超过上限 %d：判红，不截断"
			% [stages_cfg.size(), MAX_STAGES])
	var declared := int(cfg.get("stage_count", stages_cfg.size()))
	if declared != stages_cfg.size():
		return _fail("网关声明 %d 段，链路实际 %d 段：声明与结构不一致"
			% [declared, stages_cfg.size()])
	var raw_v := float(cfg.get("sensor_v", 0.0))
	var vref := float(cfg.get("vref", 0.0))
	var bits := int(cfg.get("bits", 0))
	if vref <= 0.0 or bits < 1 or bits > 16:
		return _fail("量程/位数非法：vref=%s bits=%d" % [str(vref), bits])
	var lsb := vref / float(1 << bits)
	var full := (1 << bits) - 1
	var code := int(round(raw_v / lsb))
	if code < 0 or code > full:
		return _fail("采样值 %.6f V 超出 0–%.6f V 量程" % [raw_v, vref])
	## 原始帧：电压以毫伏整数打包成 16 位大端，例如 0.5 V → 500 → "01f4"。
	var mv := int(round(raw_v * 1000.0))
	if mv > 65535:
		return _fail("采样值 %.6f V 超过 16 位帧能表示的毫伏数" % raw_v)
	var frame := "%04x" % mv
	## 量化码按位数补零：8 位 → "40"，12 位 → "0040"。
	var code_digits := 2 if bits <= 8 else 4
	var code_hex := ("%0" + str(code_digits) + "x") % code
	var seen := {}
	var rows: Array = []
	for i in stages_cfg.size():
		if not (stages_cfg[i] is Dictionary):
			return _fail("第 %d 段不是对象" % (i + 1))
		var s: Dictionary = stages_cfg[i]
		var stage := str(s.get("stage", ""))
		var node := str(s.get("node", ""))
		var op := str(s.get("op", ""))
		if stage.is_empty() or node.is_empty():
			return _fail("第 %d 段缺 stage/node 名" % (i + 1))
		if seen.has(stage):
			return _fail("stage 名重复：%s（同一段不能出现两次）" % stage)
		seen[stage] = true
		var in_raw := ""
		var out_raw := ""
		var row_code: Variant = null
		match op:
			"sample":
				in_raw = "mv:%d" % mv
				out_raw = frame
			"receive":
				in_raw = frame
				out_raw = frame
			"quantize":
				in_raw = frame
				out_raw = code_hex
				row_code = code
			"pass":
				in_raw = code_hex
				out_raw = code_hex
				row_code = code
			"store":
				in_raw = code_hex
				# 落盘记录：槽位 0001 + 码值字节，原始记录本身就是证据，不是布尔位。
				out_raw = "0001%s" % code_hex
				row_code = code
			_:
				return _fail("第 %d 段 op=%s 不在 sample/receive/quantize/pass/store"
					% [i + 1, op])
		rows.append({
			"stage": stage,
			"node": node,
			"in_raw": in_raw,
			"out_raw": out_raw,
			"code": row_code,
			"sample_ms": int(s.get("ms", 0)),
		})
	var error_lsb := absf(raw_v - float(code) * lsb) / lsb
	return {
		"ok": true,
		"stages": rows,
		"meta": {
			"stage_count": rows.size(),
			"raw_v": raw_v,
			"lsb_v": lsb,
			"adc_code": code,
			"error_lsb": error_lsb,
			"stored_key": "srv:0001:%s" % code_hex,
		},
	}

static func _fail(detail: String) -> Dictionary:
	return {"ok": false, "code": E_TABLE_CELL, "detail": detail, "stages": []}
