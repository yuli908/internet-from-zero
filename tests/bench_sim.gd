extends SceneTree

## L0–L1 性能基准关：N 门 + N DFF，4 tick/帧，统计每帧耗时（含 p50/p95/p99/max）。
## 运行：
##   & "C:\tools\godot-4.4.1\godot.cmd" --headless --path "D:\ai lm\internet_from_zero" \
##       -s "res://tests/bench_sim.gd" -- --sizes=50,100,200,300,400 --frames=600
## 输出：控制台表格 + artifacts/logs/bench.json。结论只陈述实测，不预设"能守住"。

const DEFAULT_SIZES := [50, 100, 200, 300, 400]
const DEFAULT_FRAMES := 600
const WARMUP_FRAMES := 80

func _initialize() -> void:
	SimDelays.configure(_load_delays())
	var sizes := _parse_sizes()
	var frames := _parse_int("--frames=", DEFAULT_FRAMES)
	var budget := float(SimDelays.budget_ms())
	var ticks := SimDelays.ticks_per_frame()
	print("=== IFZ BENCH ===")
	print("godot=%s  budget_ms=%.2f  ticks_per_frame=%d  frames=%d  warmup=%d" % [
		str(Engine.get_version_info().get("string", "?")), budget, ticks, frames, WARMUP_FRAMES])
	print("size\tgates\tdff\tp50_ms\tp95_ms\tp99_ms\tmax_ms\tevents\tverdict")
	var report := {"frame_budget_ms": budget, "ticks_per_frame": ticks, "frames": frames, "rows": []}
	for n in sizes:
		var row := _bench(n, frames, ticks)
		report["rows"].append(row)
		print("%d\t%d\t%d\t%.3f\t%.3f\t%.3f\t%.3f\t%d\t%s" % [
			n, int(row["gates"]), int(row["dffs"]), float(row["p50"]), float(row["p95"]),
			float(row["p99"]), float(row["max"]), int(row["events"]),
			"OK" if float(row["p95"]) <= budget else "OVER"])
	var threshold := _threshold(report["rows"], budget)
	report["threshold"] = threshold
	_write_json(report)
	print("---")
	if threshold <= 0:
		print("BENCH RESULT: 所有测试规模 p95 均 ≤ %.2f ms（未触及原生下沉阈值）" % budget)
	else:
		print("BENCH RESULT: p95 在 %d 门/%d DFF 首次超过 %.2f ms → 建议该规模以上走 GDExtension" % [
			threshold, threshold, budget])
	print("=== BENCH DONE ===")
	quit(0)

func _bench(n: int, frames: int, ticks: int) -> Dictionary:
	var c := _build(n)
	# 预热：让初值 X 收敛为稳定的 0/1，避免把冷启动成本算进分布。
	for i in range(WARMUP_FRAMES):
		_drive_frame(c, i, ticks)
		c.run(ticks)
	var samples := PackedFloat64Array()
	samples.resize(frames)
	var events := 0
	for f in range(frames):
		var before := c.eng.event_count
		_drive_frame(c, f, ticks)
		var t0 := Time.get_ticks_usec()
		var r := c.run(ticks)
		var used := float(Time.get_ticks_usec() - t0) / 1000.0
		samples[f] = used
		events = maxi(events, c.eng.event_count - before)
		if not bool(r.get("ok", false)):
			return {"n": n, "gates": n, "dffs": n, "error": str(r.get("error", "")),
				"p50": 999.0, "p95": 999.0, "p99": 999.0, "max": 999.0, "events": 0}
	var sorted_samples := Array(samples)
	sorted_samples.sort()
	return {
		"n": n,
		"gates": n,
		"dffs": n,
		"p50": _pct(sorted_samples, 0.50),
		"p95": _pct(sorted_samples, 0.95),
		"p99": _pct(sorted_samples, 0.99),
		"max": float(sorted_samples[sorted_samples.size() - 1]),
		"events": events,
	}

func _build(n: int) -> SimCircuit:
	## 结构（宽扇出，保证每 tick 所有元件都有活动，是每帧耗时的上界近似）：
	##  - n 级 DFF 移位链，由 clk 驱动，每帧一个上升沿；
	##  - n 个门全部挂在 `fast` 线上（每 tick 翻转一次），门类型轮换 buf/not/nand/and/xor，
	##    每个 tick 各求值一次，覆盖不同延迟。
	var c := SimCircuit.new("bench_%d" % n)
	c.add_wire("clk", SimValue.ZERO)
	c.add_wire("din", SimValue.ONE)
	c.add_wire("fast", SimValue.ZERO)
	c.add_wire("one", SimValue.ONE)
	var prev_d := "din"
	for i in range(n):
		var q := "q%d" % i
		c.add_dff(q, prev_d, "clk")
		prev_d = q
	var kinds := ["buf", "not", "nand", "and", "xor", "or", "nor", "xnor"]
	for i in range(n):
		var g := "g%d" % i
		var kind: String = kinds[i % kinds.size()]
		var ins := ["fast"] if (kind == "buf" or kind == "not") else ["fast", "one"]
		c.add_gate(g, kind, ins, -1)
	c.settle()
	return c

func _drive_frame(c: SimCircuit, f: int, ticks: int) -> void:
	## 每帧：fast 每个 tick 翻转一次；clk 在第 0 tick 上升、第 2 tick 下降。
	var base := SimValue.ONE if (f % 2 == 0) else SimValue.ZERO
	var inv := SimValue.ZERO if base == SimValue.ONE else SimValue.ONE
	for i in range(ticks):
		c.set_input("fast", base if (i % 2 == 0) else inv, i)
	c.set_input("clk", SimValue.ONE, 0)
	c.set_input("clk", SimValue.ZERO, mini(2, ticks - 1))

func _pct(sorted_samples: Array, q: float) -> float:
	var idx := int(ceili(q * float(sorted_samples.size()))) - 1
	idx = clampi(idx, 0, sorted_samples.size() - 1)
	return float(sorted_samples[idx])

func _threshold(rows: Array, budget: float) -> int:
	for row in rows:
		if float(row.get("p95", 0.0)) > budget:
			return int(row.get("n", 0))
	return 0

func _load_delays() -> Dictionary:
	var text := FileAccess.get_file_as_string("res://data/sim/delays.json")
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

func _parse_sizes() -> Array:
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--sizes="):
			var parts := str(arg).substr(8).split(",")
			var out := []
			for p in parts:
				if str(p).is_valid_int():
					out.append(int(p))
			if not out.is_empty():
				return out
	return DEFAULT_SIZES

func _parse_int(prefix: String, fallback: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with(prefix):
			var v := str(arg).substr(prefix.length())
			if v.is_valid_int():
				return int(v)
	return fallback

func _write_json(report: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/logs")
	var f := FileAccess.open("res://artifacts/logs/bench.json", FileAccess.WRITE)
	if f == null:
		print("BENCH WARN: 无法写入 artifacts/logs/bench.json")
		return
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("BENCH JSON: artifacts/logs/bench.json")
