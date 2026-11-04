class_name VoltageModel
extends RefCounted

## L0a 模拟电平判读。阈值全部来自 data/labs/ch01_labs.json，不在代码里写死。
## 0.8 V 以下为 0，2.0 V 以上为 1，中间为 X（禁止区）。

static func judge(v: float, low_max: float, high_min: float) -> String:
	if v <= low_max:
		return SimValue.ZERO
	if v >= high_min:
		return SimValue.ONE
	return SimValue.X

static func thresholds(cfg: Dictionary) -> Dictionary:
	var v: Dictionary = cfg.get("voltage", {})
	var low_max := float(v.get("v_low_max", 0.8))
	var high_min := float(v.get("v_high_min", 2.0))
	var max_v := float(v.get("max", 3.3))
	return {
		"min": float(v.get("min", 0.0)),
		"max": max_v,
		"step": float(v.get("step", 0.05)),
		"low_max": low_max,
		"high_min": high_min,
	}

static func cases(cfg: Dictionary, tracker: GateAttemptTracker = null) -> GateReport:
	var rep := GateReport.new()
	var th := thresholds(cfg)
	for raw in cfg.get("gate_cases", []):
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		if str(c.get("kind", "")) != "voltage_judge":
			continue
		var cid := str(c.get("id", ""))
		var v := float(c.get("v", 0.0))
		var got := judge(v, float(th["low_max"]), float(th["high_min"]))
		var want := str(c.get("expect", ""))
		var ok := got == want
		var attempt := tracker.record(cid, ok) if tracker != null else 0
		rep.add_case(GateResult.OK if ok else GateResult.E_OUTPUT_MISMATCH, cid,
			str(c.get("title", "")), {"v": v}, want, got, [], "V=%.2f V → 判 %s" % [v, got],
			bool(c.get("required", true)), attempt)
	return rep
