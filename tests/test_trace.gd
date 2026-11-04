extends RefCounted

## M3 · T3 TraceSink：5 字段 schema、kind 白名单、环形缓冲、digest 与帧粒度无关。

func run(ctx: TestContext) -> void:
	_test_schema(ctx)
	_test_monotonic_and_kinds(ctx)
	_test_history_match(ctx)
	_test_framing_digest(ctx)
	_test_ring_buffer(ctx)
	_test_reject(ctx)

func _mk(trace_cap: int = 20000) -> SimCircuit:
	var c := SimCircuit.new("trace")
	c.add_wire("a", SimValue.ZERO)
	c.add_wire("clk", SimValue.ZERO)
	c.add_gate("y", "not", ["a"])
	c.add_dff("q", "y", "clk")
	c.enable_trace(trace_cap)
	c.set_input("a", SimValue.ONE, 0)
	c.set_input("a", SimValue.ONE, 8)   # 同值重复写 → DROP
	c.set_input("clk", SimValue.ONE, 5)
	c.set_input("clk", SimValue.ZERO, 7)
	c.set_input("a", SimValue.ZERO, 10)
	c.set_input("clk", SimValue.ONE, 15)
	return c

func _test_schema(ctx: TestContext) -> void:
	var c := _mk()
	c.run_until(20)
	c.settle()
	var s: TraceSink = c.sink
	ctx.check("trace: 有事件", s.size() > 0, "size=%d" % s.size())
	var ok_shape := true
	var ok_types := true
	for i in s.size():
		var e: Dictionary = s.entry(i)
		if e.size() != 5 or not (e.has("tick") and e.has("layer") and e.has("kind")
				and e.has("subject") and e.has("payload")):
			ok_shape = false
			break
		if typeof(e["tick"]) != TYPE_INT or typeof(e["layer"]) != TYPE_STRING \
				or typeof(e["kind"]) != TYPE_STRING or typeof(e["subject"]) != TYPE_STRING \
				or typeof(e["payload"]) != TYPE_DICTIONARY:
			ok_types = false
			break
	ctx.check("trace: 每条恰好 5 字段", ok_shape)
	ctx.check("trace: 字段类型固定", ok_types)
	var kinds := {}
	var layers := {}
	for i in s.size():
		kinds[str(s.entry(i)["kind"])] = true
		layers[str(s.entry(i)["layer"])] = true
	ctx.check("trace: CHANGE 已记录", bool(kinds.get("CHANGE", false)), str(kinds.keys()))
	ctx.check("trace: EDGE 已记录", bool(kinds.get("EDGE", false)), str(kinds.keys()))
	ctx.check("trace: SAMPLE 已记录", bool(kinds.get("SAMPLE", false)), str(kinds.keys()))
	ctx.check("trace: DROP 已记录（同值合并）", bool(kinds.get("DROP", false)), str(kinds.keys()))
	ctx.check("trace: layer 全在 L0a..L6", layers.has("L2") and layers.has("L3"), str(layers.keys()))

func _test_monotonic_and_kinds(ctx: TestContext) -> void:
	var c := _mk()
	c.run_until(20)
	c.settle()
	var s: TraceSink = c.sink
	var mono := true
	var whitelisted := true
	var last := -1073741824
	for i in s.size():
		var e: Dictionary = s.entry(i)
		if int(e["tick"]) < last:
			mono = false
		last = int(e["tick"])
		if not TraceSink.KINDS.has(str(e["kind"])):
			whitelisted = false
	ctx.check("trace: tick 单调不减", mono)
	ctx.check("trace: kind 全在白名单", whitelisted)
	ctx.eq("trace: 白名单条数", TraceSink.KINDS.size(), 15)

func _test_history_match(ctx: TestContext) -> void:
	## history 每条 CHANGE 对应 sink 一条 CHANGE（G9 第 4 条）。
	var c := _mk()
	c.run_until(20)
	c.settle()
	var s: TraceSink = c.sink
	ctx.eq("trace: CHANGE 总数 == history 条数", s.count_kind("CHANGE"), c.history.size())
	var per_wire_ok := true
	for w in ["a", "y", "q", "clk"]:
		var n := 0
		for h in c.history:
			if str(h["wire"]) == w:
				n += 1
		if n != s.count_changes(w):
			per_wire_ok = false
	ctx.check("trace: 每条线 CHANGE == history", per_wire_ok)

func _test_framing_digest(ctx: TestContext) -> void:
	## 同一事件序列，1 tick/帧 与 4 tick/帧 的 digest 与线值必须一致（G9 第 5 条）。
	var one := _mk()
	for t in range(1, 401):
		one.run_until(t)
	var four := _mk()
	for t in range(4, 401, 4):
		four.run_until(t)
	ctx.eq("trace: 1 tick/帧 digest == 4 tick/帧 digest", one.trace_digest(), four.trace_digest())
	ctx.eq("trace: 1 tick/帧 与 4 tick/帧 q 相同", one.probe("q"), four.probe("q"))
	ctx.eq("trace: 1 tick/帧 与 4 tick/帧 事件数相同", one.sink.size(), four.sink.size())
	var same_prefix := true
	for i in mini(one.sink.size(), four.sink.size()):
		if str(one.sink.entry(i)) != str(four.sink.entry(i)):
			same_prefix = false
			break
	ctx.check("trace: 两条事件逐条相同", same_prefix)

func _test_ring_buffer(ctx: TestContext) -> void:
	var s := TraceSink.new(8)
	for i in 10:
		s.record(i, "L2", "CHANGE", "w", {"v": str(i)})
	ctx.eq("ring: 容量=8 时保留 8 条", s.size(), 8)
	ctx.eq("ring: 丢弃最旧 2 条", s.dropped_old, 2)
	ctx.eq("ring: 最旧保留 tick == 2", int(s.entry(0)["tick"]), 2)
	ctx.eq("ring: 最新 tick == 9", int(s.entry(7)["tick"]), 9)
	var exp := s.export()
	ctx.eq("ring: 导出带丢弃计数", int(exp["dropped_old"]), 2)
	ctx.eq("ring: 导出格式", str(exp["format"]), "ifz-trace/1")

func _test_reject(ctx: TestContext) -> void:
	var s := TraceSink.new()
	ctx.check("reject: 未知 kind 被拒", not s.record(0, "L2", "BOGUS", "w", {}))
	ctx.eq("reject: 记录数不变", s.size(), 0)
	ctx.check("reject: 未知 layer 被拒", not s.record(0, "L9", "CHANGE", "w", {}))
	ctx.check("reject: 空 subject 被拒", not s.record(0, "L2", "CHANGE", "", {}))
	s.record(5, "L2", "CHANGE", "w", {})
	ctx.check("reject: tick 回退被拒", not s.record(3, "L2", "CHANGE", "w", {}))
	ctx.eq("reject: 拒绝计数", s.rejected, 4)
	ctx.check("reject: ERR_ADDR 在扩展白名单内（第二章用）",
		s.record(6, "L2", "ERR_ADDR", "w", {}))
	var d1 := s.digest()
	s.record(7, "L2", "CHANGE", "w", {"v": "2"})
	ctx.check("digest: 新事件改变摘要", s.digest() != d1)
	var t2 := TraceSink.new()
	t2.record(0, "L2", "CHANGE", "w", {"v": "1"})
	t2.record(1, "L2", "CHANGE", "w", {"v": "2"})
	ctx.eq("digest: 同内容同摘要", t2.digest(), t2.digest())
	var t3 := TraceSink.new()
	t3.record(1, "L2", "CHANGE", "w", {"v": "2"})
	t3.record(0, "L2", "CHANGE", "w", {"v": "1"})
	ctx.eq("digest: 乱序 tick 被拒后只剩 1 条", t3.size(), 1)
	ctx.eq("digest: 乱序拒绝计数", t3.rejected, 1)
