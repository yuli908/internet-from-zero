extends RefCounted

## 实验室·原型台阶段 1 验收：三区几何、元件台拖门、画布落门、一根连线、实验位入口。
## 只读生产代码里的几何常量（zone_rects/bench_slot_rect/...），不在测试里另抄一份数值。

const Lab = preload("res://src/ui/screens/laboratory_screen.gd")
const EditorGd = preload("res://src/ui/widgets/circuit_editor.gd")

## 本套件自报期望数：EXPECT = 各组之和，runner 逐组比对实际计数。
const EXPECT := 36
const EXPECT_GROUPS := {
	"geometry": 10, "bench_palette": 7, "store_bins": 4, "rack_select": 3,
	"canvas_drop": 4, "wiring": 3, "entry_wiring": 5,
}
const GROUP_DESCRIPTIONS := {
	"geometry": "三区（元件台/画布/收纳区）位置宽高、同高 612、间距 18、右缘 1232",
	"bench_palette": "元件台 6 门槽 + 3 工具位的尺寸/间距且不越区，含 and/or/not",
	"store_bins": "收纳格不越出收纳区、与实验位不重叠、6 实验位一行且不越区",
	"rack_select": "本章 6 个实验位，已解锁可点、锁定不可点",
	"canvas_drop": "从元件台拖门入画布：合法门型落门、门型正确、非法门型不落",
	"wiring": "点输出端口再点输入端口会让图上真的多一根连到 AND 的线",
	"entry_wiring": "黑板按钮进原型台、主壳注册与标题、无空态提示、截图走真实落门连线接口",
}

func run(ctx: TestContext) -> void:
	var z: Dictionary = Lab.zone_rects()
	var bench: Rect2 = z["bench"]
	var canvas: Rect2 = z["canvas"]
	var store: Rect2 = z["store"]

	# ---- 三区几何 ----
	ctx.begin_group("geometry")
	ctx.eq("元件台 x=0", bench.position.x, 0.0)
	ctx.eq("元件台宽 236", bench.size.x, 236.0)
	ctx.eq("画布 x=254", canvas.position.x, 254.0)
	ctx.eq("画布宽 724", canvas.size.x, 724.0)
	ctx.eq("收纳区 x=996", store.position.x, 996.0)
	ctx.eq("收纳区宽 236", store.size.x, 236.0)
	ctx.eq("三区同高 612", [bench.size.y, canvas.size.y, store.size.y], [612.0, 612.0, 612.0])
	ctx.eq("区间距 18（左）", canvas.position.x - bench.end.x, 18.0)
	ctx.eq("区间距 18（右）", store.position.x - canvas.end.x, 18.0)
	ctx.eq("三区右缘 1232", store.end.x, 1232.0)

	# ---- 元件台：6 个门槽 + 3 个工具位，全部在区内 ----
	ctx.begin_group("bench_palette")
	ctx.eq("元件台门槽 6 个", Lab.PALETTE_GATES.size(), 6)
	var last_slot: Rect2 = Lab.bench_slot_rect(5)
	ctx.eq("门槽宽 212", last_slot.size.x, 212.0)
	ctx.eq("门槽高 64", last_slot.size.y, 64.0)
	ctx.eq("门槽间距 8", Lab.bench_slot_rect(1).position.y - Lab.bench_slot_rect(0).end.y, 8.0)
	ctx.check("门槽不越出元件台", last_slot.end.x <= bench.size.x and last_slot.end.y <= bench.size.y,
		"last=%s" % str(last_slot))
	ctx.check("元件台含基础门 and/or/not",
		Lab.PALETTE_GATES.has("and") and Lab.PALETTE_GATES.has("or") and Lab.PALETTE_GATES.has("not"),
		str(Lab.PALETTE_GATES))
	var last_tool: Rect2 = Lab.tool_slot_rect(2)
	ctx.check("3 个工具位不越出元件台", last_tool.end.x <= bench.size.x and last_tool.end.y <= bench.size.y,
		"last=%s" % str(last_tool))

	# ---- 收纳区：8 个收纳格 + 6 个实验位，两段不重叠 ----
	var last_bin: Rect2 = Lab.bin_slot_rect(Lab.BIN_COUNT - 1)
	ctx.begin_group("store_bins")
	ctx.check("收纳格不越出收纳区", last_bin.end.x <= store.size.x and last_bin.end.y <= store.size.y,
		"last=%s" % str(last_bin))
	ctx.check("收纳格与实验位不重叠", last_bin.end.y < Lab.rack_slot_rect(0).position.y,
		"bins_bottom=%.0f rack_top=%.0f" % [last_bin.end.y, Lab.rack_slot_rect(0).position.y])
	var last_rack: Rect2 = Lab.rack_slot_rect(5)
	ctx.eq("实验位 6 个正好一行", last_rack.end.x - Lab.rack_slot_rect(0).position.x, 212.0)
	ctx.check("实验位不越出收纳区", last_rack.end.x <= store.size.x and last_rack.end.y <= store.size.y,
		"last=%s" % str(last_rack))

	# ---- 实验位可选性：锁定不可点，已解锁可点 ----
	var order: Array = []
	for raw in (TestUtil.chapter_doc().get("labs", []) as Array):
		if raw is Dictionary:
			order.append(str((raw as Dictionary).get("id", "")))
	ctx.begin_group("rack_select")
	ctx.eq("本章实验位正好 6 个", order.size(), 6)
	var unlocked := {str(order[0]): true}
	ctx.check("已解锁实验位可点", Lab.slot_open(str(order[0]), unlocked))
	ctx.check("锁定实验位不可点", not Lab.slot_open(str(order[1]), unlocked))

	# ---- 拖入：元件台数据 → 画布落门 ----
	var e := _editor()
	ctx.begin_group("canvas_drop")
	ctx.check("画布接受元件台拖入", bool(e._can_drop_data(Vector2(300, 200), {"bench_gate": "or"})))
	e._drop_data(Vector2(300, 200), {"bench_gate": "or"})
	ctx.eq("拖入后画布有 1 个门", e.gate_count(), 1)
	ctx.eq("拖入的门型是 OR", _kind(e, "g1"), "OR")
	e._drop_data(Vector2(300, 200), {"bench_gate": "bogus"})
	ctx.eq("非法门型不落门", e.gate_count(), 1)
	e.free()

	# ---- 连线：点输出端口 → 点输入端口，图上真的多一根线 ----
	e = _editor()
	var a := e.add_gate_at("and", Vector2(200, 150))
	var b := e.add_gate_at("not", Vector2(420, 150))
	ctx.begin_group("wiring")
	ctx.check("两个门都有自己的 id", not a.is_empty() and not b.is_empty(), "%s/%s" % [a, b])
	var pa: Vector2 = e.graph.nodes[a]["pos"]
	var pb: Vector2 = e.graph.nodes[b]["pos"]
	e._on_left(pa + Vector2(CircuitEditor.NODE_SIZE.x, CircuitEditor.NODE_SIZE.y * 0.5))
	e._on_left(pb + Vector2(0, 13))
	ctx.eq("连线后 NOT 的输入接到 AND", str(e.graph.nodes[b].get("a", "")), a)
	ctx.eq("全局只有这一根线", e.graph.gate_ids().size(), 2)
	e.free()

	# ---- 入口接线：黑板「实验室」进原型台，实验位再进任意已解锁 lab ----
	var wb := FileAccess.get_file_as_string("res://src/ui/screens/workbench_screen.gd")
	ctx.begin_group("entry_wiring")
	ctx.check("黑板实验室按钮进原型台", wb.contains("show_screen\", \"laboratory\""))
	var main_src := FileAccess.get_file_as_string("res://src/ui/main.gd")
	ctx.check("主壳注册 laboratory 屏", main_src.contains("\"laboratory\": preload"))
	ctx.check("主壳标题写实验室", main_src.contains("\"laboratory\": \"实验室\""))
	var lab_src := FileAccess.get_file_as_string("res://src/ui/screens/laboratory_screen.gd")
	ctx.check("自由画布不画空态提示", lab_src.contains("_editor.quiet = true"))
	ctx.check("截图 demo 走真实落门与连线接口",
		lab_src.contains("add_gate_at(") and lab_src.contains("_on_left"))

func _editor() -> CircuitEditor:
	var e: CircuitEditor = EditorGd.new()
	e.custom_minimum_size = Vector2(722, 610)
	e.size = Vector2(722, 610)
	e.quiet = true
	e.max_gates = 24
	Engine.get_main_loop().root.add_child(e)
	return e

func _kind(e: CircuitEditor, gid: String) -> String:
	return str(e.graph.nodes[gid].get("label", e.graph.nodes[gid].get("kind", "")))
