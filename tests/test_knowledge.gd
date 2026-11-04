extends RefCounted

## 双树四态、gate 自动解锁、里程碑、旧节点兼容。

## 本套件自报期望数：EXPECT = 各组之和，runner 逐组比对实际计数。
const EXPECT := 32
const EXPECT_GROUPS := {
	"node_counts": 3, "gate_lock": 2, "gate_unlock": 4, "ch01_sequence": 3,
	"ch01_gates": 4, "chapter_reward": 4, "legacy_compat": 6, "xp_lock": 2,
	"progress_effects": 4,
}
const GROUP_DESCRIPTIONS := {
	"node_counts": "节点总数 62 与 progress/knowledge 两棵树节点数",
	"gate_lock": "未过 gate 时 CH01-1 锁定且不可解锁",
	"gate_unlock": "过 gate 后可用、解锁成功、状态转 completed、里程碑不发金币",
	"ch01_sequence": "CH01-2 依赖 CH01-1 的锁定/可用/解锁三段",
	"ch01_gates": "CH01-3..6 逐个过 gate 后解锁成功",
	"chapter_reward": "CH01 可用并解锁后发 25 金、50 xp",
	"legacy_compat": "旧节点 voltage/binary 的可用性、解锁奖励与后续解锁",
	"xp_lock": "新档 xp=0 且无法解锁 binary",
	"progress_effects": "进度总数/完成数、demorgan 节点存在、bargain 折扣效果",
}

func run(ctx: TestContext) -> void:
	var db: Node = TestUtil.data_db()
	var kg: KnowledgeGraph = db.skill_graph
	ctx.begin_group("node_counts")
	ctx.eq("node count", kg.nodes.size(), 62)
	ctx.eq("progress nodes", kg.nodes_of_tree("progress").size(), 14)
	ctx.eq("knowledge nodes", kg.nodes_of_tree("knowledge").size(), 32)

	ctx.begin_group("gate_lock")
	var st := PlayerState.new()
	st.gold = 0
	ctx.eq("CH01-1 locked before gate", kg.node_state(st, "CH01-1"), "locked")
	ctx.check("CH01-1 cannot unlock", not bool(kg.can_unlock(st, "CH01-1").get("ok", false)))
	ctx.begin_group("gate_unlock")
	st.set_flag("gate:T1.1-4", true)
	ctx.eq("CH01-1 available after gate", kg.node_state(st, "CH01-1"), "available")
	var u1 := kg.unlock(st, "CH01-1")
	ctx.check("CH01-1 unlock", bool(u1.get("ok", false)), str(u1.get("error", "")))
	ctx.eq("CH01-1 completed", kg.node_state(st, "CH01-1"), "completed")
	ctx.eq("milestone no gold", st.gold, 0)

	ctx.begin_group("ch01_sequence")
	ctx.eq("CH01-2 locked before node", kg.node_state(st, "CH01-2"), "locked")
	st.set_flag("gate:T1.2-4", true)
	ctx.eq("CH01-2 available", kg.node_state(st, "CH01-2"), "available")
	ctx.check("CH01-2 unlock", bool(kg.unlock(st, "CH01-2").get("ok", false)))

	ctx.begin_group("ch01_gates")
	for i in range(3, 7):
		st.set_flag("gate:T1.%d-4" % i, true)
		ctx.check("CH01-%d unlock" % i, bool(kg.unlock(st, "CH01-%d" % i).get("ok", false)))
	ctx.begin_group("chapter_reward")
	ctx.eq("CH01 available", kg.node_state(st, "CH01"), "available")
	var u2 := kg.unlock(st, "CH01")
	ctx.check("CH01 unlock", bool(u2.get("ok", false)))
	ctx.eq("chapter gold award", st.gold, 25)
	ctx.eq("chapter xp award", st.xp, 50)

	ctx.begin_group("legacy_compat")
	var legacy := PlayerState.new()
	legacy.gold = 0
	ctx.eq("legacy voltage available", kg.node_state(legacy, "voltage"), "available")
	ctx.eq("legacy binary locked", kg.node_state(legacy, "binary"), "locked")
	var uv := kg.unlock(legacy, "voltage")
	ctx.check("legacy voltage unlock", bool(uv.get("ok", false)))
	ctx.eq("legacy voltage gold", legacy.gold, 10)
	ctx.eq("legacy voltage xp", legacy.xp, 15)
	ctx.eq("legacy binary now available", kg.node_state(legacy, "binary"), "available")

	ctx.begin_group("xp_lock")
	var poor := PlayerState.new()
	ctx.eq("poor xp", poor.xp, 0)
	ctx.check("poor cannot unlock binary", not bool(kg.can_unlock(poor, "binary").get("ok", false)))

	ctx.begin_group("progress_effects")
	ctx.eq("progress total", int(kg.progress(st).get("total", 0)), 62)
	ctx.check("progress done grew", int(kg.progress(st).get("done", 0)) >= 3)
	ctx.check("demorgan node exists", kg.nodes.has("demorgan"))
	ctx.check("bargain effect", str(kg.node("bargain").get("effects", {})).contains("price_discount"))
