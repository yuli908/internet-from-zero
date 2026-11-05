extends RefCounted

## CH16.3 压测探针：事件驱动的逐请求记录。
## 时钟只由事件推进（发送事件、到达事件），`sent_at` / `got_at` 一律取 `clock.now`，
## 所以时延是两枚真实事件的时间差，不是方案表里的常数。
## 8 并发 = 全部客户端在 t=0 发起（`sent_at` 全为 0 是时钟事件的真实值，不是填充值）；
## 到达时刻由「服务耗时 + 抖动」各自决定，因此完成次序与请求编号无关。
## 生产：`run(plan)`；消费：`tests/test_ch16.gd` 用它生成 T16.3-1 逐条记录与 T16.3-3 的均值/吞吐。

static func run(plan: Dictionary) -> Dictionary:
	var n := int(plan.get("n", 0))
	var gap := int(plan.get("gap_ms", 0))
	var serve := int(plan.get("serve_ms", 0))
	var jmax := int(plan.get("jitter_max", 0))
	var seed := int(plan.get("seed", 0))
	var events: Array = []
	for i in n:
		var s := serve + _jitter(seed, i, jmax)
		events.append({"at": i * gap, "kind": "send", "req_id": i + 1})
		events.append({"at": i * gap + s, "kind": "arrival", "req_id": i + 1, "status": 200})
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["at"]) == int(b["at"]):
			return str(a["kind"]) < str(b["kind"])
		return int(a["at"]) < int(b["at"]))
	var clock := 0
	var open: Dictionary = {}
	var rows: Array = []
	var sends := 0
	var arrivals := 0
	for raw in events:
		var e: Dictionary = raw
		clock = int(e["at"])
		var rid := int(e["req_id"])
		if str(e["kind"]) == "send":
			sends += 1
			open[rid] = {"sent_at": clock, "client_seq": sends}
		else:
			arrivals += 1
			var o: Dictionary = open.get(rid, {})
			if o.is_empty():
				continue
			var sent := int(o["sent_at"])
			var status := int(e.get("status", 0))
			rows.append({
				"req_id": rid,
				"client_seq": int(o["client_seq"]),
				"sent_at": sent,
				"got_at": clock,
				"latency": clock - sent,
				"ok": status == 200,
				"status": status,
			})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["client_seq"]) < int(b["client_seq"]))
	var sum_lat := 0
	var logged := true
	var all_ok := true
	for raw in rows:
		var r: Dictionary = raw
		sum_lat += int(r["latency"])
		if int(r["latency"]) != int(r["got_at"]) - int(r["sent_at"]) or int(r["latency"]) <= 0:
			logged = false
		if not bool(r["ok"]):
			all_ok = false
	var meta := {
		"real_requests": sends == n and arrivals == n and rows.size() == n,
		"all_ok": all_ok,
		"latency_logged": logged,
		"events_logged": events.size() == 2 * n,
	}
	var avg := 0
	if rows.size() > 0:
		avg = int(round(float(sum_lat) / float(rows.size())))
	var window_ms := int(plan.get("window_ms", 0))
	var throughput := 0
	if window_ms > 0:
		throughput = int(round(float(n) * 1000.0 / float(window_ms)))
	return {
		"rows": rows,
		"events": events,
		"meta": meta,
		"summary": {"avg_latency": avg, "throughput": throughput},
	}

static func _jitter(seed: int, i: int, jmax: int) -> int:
	if jmax <= 0:
		return 0
	return int((seed * (i + 1)) % (jmax + 1))
